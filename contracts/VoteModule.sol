// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IVoteModule} from "./interfaces/IVoteModule.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IXShadow} from "./interfaces/IXShadow.sol";

contract VoteModule is IVoteModule, ReentrancyGuard, Initializable {
    /// @inheritdoc IVoteModule
    address public accessHub;
    /// @inheritdoc IVoteModule
    address public xShadow;
    /// @inheritdoc IVoteModule
    address public voter;
    /// @notice xShadow token
    IXShadow public stakingToken;
    /// @notice underlying Shadow token
    IERC20 public underlying;

    /// @notice rebases are released over 30 minutes
    uint256 public duration = 30 minutes;

    /// @notice lock period after rebase starts accruing
    uint256 public cooldown = 12 hours;

    /// @notice decimal precision of 1e18
    uint256 public constant PRECISION = 10 ** 18;

    /// @inheritdoc IVoteModule
    uint256 public totalSupply;
    /// @inheritdoc IVoteModule
    uint256 public lastUpdateTime;
    /// @inheritdoc IVoteModule
    uint256 public rewardPerTokenStored;
    /// @inheritdoc IVoteModule
    uint256 public periodFinish;
    /// @inheritdoc IVoteModule
    uint256 public rewardRate;
    /// @inheritdoc IVoteModule
    uint256 public unlockTime;

    /// @inheritdoc IVoteModule
    mapping(address user => uint256 amount) public balanceOf;
    /// @inheritdoc IVoteModule
    mapping(address user => uint256 rewardPerToken)
        public userRewardPerTokenStored;
    /// @inheritdoc IVoteModule
    mapping(address user => uint256 rewards) public storedRewardsPerUser;
    /// @inheritdoc IVoteModule
    mapping(address delegator => address delegatee) public delegates;
    /// @inheritdoc IVoteModule
    mapping(address owner => address operator) public admins;
    /// @inheritdoc IVoteModule
    mapping(address user => bool exempt) public cooldownExempt;

    modifier onlyAccessHub() {
        /// @dev ensure it is the accessHub
        require(msg.sender == accessHub, NOT_ACCESSHUB());
        _;
    }

    constructor() {
        voter = msg.sender;
    }

    function initialize(
        address _xShadow,
        address _voter,
        address _accessHub
    ) external initializer {
        // @dev making sure who deployed calls initialize
        require(voter == msg.sender, UNAUTHORIZED());
        require(_accessHub != address(0), INVALID_ADDRESS());
        require(_xShadow != address(0), INVALID_ADDRESS());
        require(_voter != address(0), INVALID_ADDRESS());
        xShadow = _xShadow;
        voter = _voter;
        accessHub = _accessHub;
        stakingToken = IXShadow(_xShadow);
        underlying = IERC20(IXShadow(_xShadow).SHADOW());
    }

    /// @dev common multirewarder-esque modifier for updating on interactions
    modifier updateReward(address account) {
        /// @dev fetch and store the new rewardPerToken
        rewardPerTokenStored = rewardPerToken();
        /// @dev fetch and store the new last update time
        lastUpdateTime = lastTimeRewardApplicable();
        /// @dev check for address(0) calls from notifyRewardAmount
        if (account != address(0)) {
            /// @dev update the individual account's mapping for stored rewards
            storedRewardsPerUser[account] = earned(account);
            /// @dev update account's mapping for rewardspertoken
            userRewardPerTokenStored[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @inheritdoc IVoteModule
    function depositAll() external {
        deposit(IERC20(xShadow).balanceOf(msg.sender));
    }
    /// @inheritdoc IVoteModule
    function deposit(
        uint256 amount
    ) public updateReward(msg.sender) nonReentrant {
        /// @dev ensure the amount is > 0
        require(amount != 0, ZERO_AMOUNT());
        /// @dev if the caller is not exempt
        if (!cooldownExempt[msg.sender]) {
            /// @dev block interactions during the cooldown period
            require(block.timestamp >= unlockTime, COOLDOWN_ACTIVE());
        }
        /// @dev transfer xShadow in
        IERC20(xShadow).transferFrom(msg.sender, address(this), amount);
        /// @dev update accounting
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        /// @dev update data
        IVoter(voter).poke(msg.sender);

        emit Deposit(msg.sender, amount);
    }
    /// @inheritdoc IVoteModule
    function withdrawAll() external {
        /// @dev fetch stored balance
        uint256 _amount = balanceOf[msg.sender];
        /// @dev withdraw the stored balance
        withdraw(_amount);
        /// @dev claim rewards for the user
        _claim(msg.sender);
    }
    /// @inheritdoc IVoteModule
    function withdraw(
        uint256 amount
    ) public updateReward(msg.sender) nonReentrant {
        /// @dev ensure the amount is > 0
        require(amount != 0, ZERO_AMOUNT());
        /// @dev if the caller is not exempt
        if (!cooldownExempt[msg.sender]) {
            /// @dev block interactions during the cooldown period
            require(block.timestamp >= unlockTime, COOLDOWN_ACTIVE());
        }

        /// @dev reduce total "supply"
        totalSupply -= amount;
        /// @dev decrement from balance mapping
        balanceOf[msg.sender] -= amount;
        /// @dev transfer the xShadow to the caller
        IERC20(xShadow).transfer(msg.sender, amount);

        /// @dev update data via poke
        /// @dev we check in voter that msg.sender is the VoteModule
        IVoter(voter).poke(msg.sender);

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IVoteModule
    /// @dev this is ONLY callable by xShadow, which has important safety checks
    function notifyRewardAmount(
        uint256 amount
    ) external updateReward(address(0)) nonReentrant {
        /// @dev ensure > 0
        require(amount != 0, ZERO_AMOUNT());
        /// @dev only callable by xShadow contract
        require(msg.sender == xShadow, NOT_XSHADOW());
        /// @dev take the SHADOW from the contract to the voteModule
        underlying.transferFrom(xShadow, address(this), amount);

        if (block.timestamp >= periodFinish) {
            /// @dev the new reward rate being the amount divided by the duration
            rewardRate = amount / duration;
        } else {
            /// @dev remaining seconds until the period finishes
            uint256 remaining = periodFinish - block.timestamp;
            /// @dev remaining tokens to stream via t * rate
            uint256 _left = remaining * rewardRate;
            /// @dev update the rewardRate to the notified amount plus what is left, divided by the duration
            rewardRate = (amount + _left) / duration;
        }

        /// @dev update timestamp for the rebase
        lastUpdateTime = block.timestamp;
        /// @dev update periodFinish (when all rewards are streamed)
        periodFinish = block.timestamp + duration;
        /// @dev the timestamp of when people can withdraw next
        /// @dev not DoSable because only xShadow can notify
        unlockTime = cooldown + periodFinish;

        emit NotifyReward(msg.sender, amount);
    }

    /** AccessHub Gated Functions */
    /// @inheritdoc IVoteModule
    function setCooldownExemption(
        address _user,
        bool _exempt
    ) external onlyAccessHub {
        /// @dev ensure the call is not the same status
        require(cooldownExempt[_user] != _exempt, NO_CHANGE());
        /// @dev adjust the exemption status
        cooldownExempt[_user] = _exempt;

        emit ExemptedFromCooldown(_user, _exempt);
    }
    /// @inheritdoc IVoteModule
    function setNewDuration(uint256 _durationInSeconds) external onlyAccessHub {
        /// @dev safety check
        require(_durationInSeconds != 0 && _durationInSeconds <= 7 days);
        uint256 oldDuration = duration;
        duration = _durationInSeconds;

        emit NewDuration(oldDuration, duration);
    }

    /// @inheritdoc IVoteModule
    function setNewCooldown(uint256 _cooldownInSeconds) external onlyAccessHub {
        /// @dev safety check
        require(_cooldownInSeconds <= 7 days);
        uint256 oldCooldown = cooldown;
        cooldown = _cooldownInSeconds;

        emit NewCooldown(oldCooldown, cooldown);
    }

    /** User Management Functions */

    /// @inheritdoc IVoteModule
    function delegate(address delegatee) external {
        bool _isAdded = false;
        /// @dev if there exists a delegate, and the chosen delegate is the zero address
        if (delegatee == address(0) && delegates[msg.sender] != address(0)) {
            /// @dev delete the mapping
            delete delegates[msg.sender];
        } else {
            /// @dev else update delegation
            delegates[msg.sender] = delegatee;
            /// @dev flip to true if a delegate is written
            _isAdded = true;
        }
        /// @dev emit event
        emit Delegate(msg.sender, delegatee, _isAdded);
    }
    /// @inheritdoc IVoteModule
    function setAdmin(address admin) external {
        /// @dev visibility setting to false, even though default is false
        bool _isAdded = false;
        /// @dev if there exists an admin and the zero address is chosen
        if (admin == address(0) && admins[msg.sender] != address(0)) {
            /// @dev wipe mapping
            delete admins[msg.sender];
        } else {
            /// @dev else update mapping
            admins[msg.sender] = admin;
            /// @dev flip to true if an admin is written
            _isAdded = true;
        }
        /// @dev emit event
        emit SetAdmin(msg.sender, admin, _isAdded);
    }

    /** View Functions */

    /// @inheritdoc IVoteModule
    function lastTimeRewardApplicable() public view returns (uint256 _lta) {
        _lta = Math.min(block.timestamp, periodFinish);
    }
    /// @inheritdoc IVoteModule
    function earned(address account) public view returns (uint256 _reward) {
        _reward =
            (/// @dev the vote balance of the account
            (balanceOf[account] *
                /// @dev current global reward per token, subtracted from the stored reward per token for the user
                (rewardPerToken() - userRewardPerTokenStored[account])) /
                /// @dev divide by the 1e18 precision
                PRECISION) +
            /// @dev add the existing stored rewards for the account to the total
            storedRewardsPerUser[account];
    }
    /// @inheritdoc IVoteModule
    function getReward() external updateReward(msg.sender) nonReentrant {
        /// @dev redundant _sender storage for visibility (can be removed later likely)
        address _sender = msg.sender;
        /// @dev claim all the rewards
        _claim(_sender);
    }
    /// @dev internal claim function to make exiting and claiming easier
    function _claim(address _user) internal {
        /// @dev fetch the stored rewards (updated by modifier)
        uint256 reward = storedRewardsPerUser[_user];
        if (reward > 0) {
            /// @dev zero out the stored rewards
            storedRewardsPerUser[_user] = 0;
            /// @dev approve Shadow to xShadow
            underlying.approve(address(stakingToken), reward);
            /// @dev convert
            stakingToken.convertEmissionsToken(reward);
            /// @dev transfer xShadow to the user
            IERC20(xShadow).transfer(_user, reward);
            emit ClaimRewards(_user, reward);
        }
    }
    /// @inheritdoc IVoteModule
    /// @dev the return value is scaled (multiplied) by PRECISION = 10 ** 18
    function rewardPerToken() public view returns (uint256 _rpt) {
        _rpt = (
            /// @dev if there's no staked xShadow
            totalSupply == 0 /// @dev return the existing value
                ? rewardPerTokenStored /// @dev else add the existing value
                : rewardPerTokenStored +
                    /// @dev to remaining time (since update) multiplied by the current reward rate
                    /// @dev scaled to precision of 1e18, then divided by the total supply
                    (((lastTimeRewardApplicable() - lastUpdateTime) *
                        rewardRate *
                        PRECISION) / totalSupply)
        );
    }
    /// @inheritdoc IVoteModule
    function left() public view returns (uint256 _left) {
        _left = (
            /// @dev if the timestamp is past the period finish
            block.timestamp >= periodFinish /// @dev there are no rewards "left" to stream
                ? 0 /// @dev multiply the remaining seconds by the rewardRate to determine what is left to stream
                : ((periodFinish - block.timestamp) * rewardRate)
        );
    }

    /// @inheritdoc IVoteModule
    function isDelegateFor(
        address caller,
        address owner
    ) external view returns (bool approved) {
        /// @dev check the delegate mapping AND admin mapping due to hierarchy (admin > delegate)
        return (delegates[owner] == caller ||
            admins[owner] == caller ||
            /// @dev return true if caller is the owner as well
            caller == owner);
    }

    /// @inheritdoc IVoteModule
    function isAdminFor(
        address caller,
        address owner
    ) external view returns (bool approved) {
        /// @dev return whether the caller is the address in the map
        /// @dev return true if caller is the owner as well
        return (admins[owner] == caller || caller == owner);
    }
}
