// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVoter} from "./interfaces/IVoter.sol";
import {IGauge} from "./interfaces/IGauge.sol";

import {IXShadow} from "./interfaces/IXShadow.sol";

/// @dev we use a very minimal interface for easy fetching
interface IMinimalPoolInterface {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @notice Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
contract Gauge is IGauge, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice the LP token that needs to be staked for rewards
    address public immutable stake;
    /// @notice the address of the voter contract
    address public immutable voter;
    /// @dev rewards in the array
    address[] internal rewards;
    /// @notice total supply of LP tokens staked
    uint256 public totalSupply;

    /// @dev rewards are released over 7 days
    uint256 internal constant DURATION = 7 days;
    /// @dev 1e27 precision
    uint256 internal constant PRECISION = 10 ** 18;

    IXShadow public immutable xShadow;

    mapping(address user => uint256) public balanceOf;
    mapping(address user => mapping(address token => uint256 rewardPerToken))
        public userRewardPerTokenStored;
    mapping(address user => mapping(address token => uint256 reward))
        public storedRewardsPerUser;
    mapping(address token => bool _isReward) public isReward;

    mapping(address token => Reward) internal _rewardData;

    EnumerableSet.AddressSet tokenWhitelists;

    constructor(address _stake, address _voter) {
        stake = _stake;
        voter = _voter;

        /// @dev temporary voter interface
        IVoter tempVoter = IVoter(voter);
        xShadow = IXShadow(tempVoter.xShadow());

        /// @dev temporary minimal pool interface to fetch token(0 / 1)
        IMinimalPoolInterface pool = IMinimalPoolInterface(stake);

        /// @dev add initial rewards of emissions (shadow/xshadow) and token0/token1
        tokenWhitelists.add(tempVoter.shadow());
        tokenWhitelists.add(tempVoter.xShadow());
        tokenWhitelists.add(pool.token0());
        tokenWhitelists.add(pool.token1());
    }

    /// @dev compiled with via-ir, caching is less efficient
    modifier updateReward(address account) {
        for (uint256 i; i < rewards.length; i++) {
            _rewardData[rewards[i]].rewardPerTokenStored = rewardPerToken(
                rewards[i]
            );
            _rewardData[rewards[i]].lastUpdateTime = lastTimeRewardApplicable(
                rewards[i]
            );
            if (account != address(0)) {
                storedRewardsPerUser[account][rewards[i]] = earned(
                    rewards[i],
                    account
                );
                userRewardPerTokenStored[account][rewards[i]] = _rewardData[
                    rewards[i]
                ].rewardPerTokenStored;
            }
        }
        _;
    }

    /// @inheritdoc IGauge
    function rewardsList() external view returns (address[] memory _rewards) {
        _rewards = rewards;
    }

    /// @inheritdoc IGauge
    function rewardsListLength() external view returns (uint256 _length) {
        _length = rewards.length;
    }

    /// @inheritdoc IGauge
    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        /// @dev returns the lesser of the current unix timestamp, and the timestamp for when the period finishes for the specified reward token
        return Math.min(block.timestamp, _rewardData[token].periodFinish);
    }

    /// @inheritdoc IGauge
    function rewardData(
        address token
    ) external view override returns (Reward memory data) {
        data = _rewardData[token];
    }

    /// @inheritdoc IGauge
    function earned(
        address token,
        address account
    ) public view returns (uint256 _reward) {
        _reward =
            ((balanceOf[account] *
                (rewardPerToken(token) -
                    userRewardPerTokenStored[account][token])) / PRECISION) +
            storedRewardsPerUser[account][token];
    }

    /// @inheritdoc IGauge
    function getReward(
        address account,
        address[] calldata tokens
    ) public updateReward(account) nonReentrant {
        /// @dev ensure calls from the account or the voter address
        require(msg.sender == account || msg.sender == voter, NOT_AUTHORIZED());
        /// @dev loop through the tokens
        for (uint256 i; i < tokens.length; i++) {
            /// @dev fetch the stored rewards for the user for current index's token
            uint256 _reward = storedRewardsPerUser[account][tokens[i]];
            /// @dev if the stored rewards are greater than zero
            if (_reward > 0) {
                /// @dev zero out the rewards
                storedRewardsPerUser[account][tokens[i]] = 0;
                /// @dev transfer the expected rewards
                _safeTransfer(tokens[i], account, _reward);
                emit ClaimRewards(account, tokens[i], _reward);
            }
        }
    }

    /// @inheritdoc IGauge
    function getRewardAndExit(
        address account,
        address[] calldata tokens
    ) public updateReward(account) nonReentrant {
        /// @dev ensure calls from the account or the voter address
        require(msg.sender == account || msg.sender == voter, NOT_AUTHORIZED());
        /// @dev loop through the tokens
        for (uint256 i; i < tokens.length; i++) {
            /// @dev fetch the stored rewards for the user for current index's token
            uint256 _reward = storedRewardsPerUser[account][tokens[i]];
            /// @dev if the stored rewards are greater than zero
            if (_reward > 0) {
                /// @dev zero out the rewards
                storedRewardsPerUser[account][tokens[i]] = 0;
                /// @dev if the token is xShadow
                if (tokens[i] == address(xShadow)) {
                    /// @dev store shadow token
                    address shadowToken = address(xShadow.SHADOW());
                    /// @dev calculate the amount of SHADOW owed
                    uint256 shadowToSend = xShadow.exit(_reward);
                    /// @dev send the shadow to the user
                    _safeTransfer(shadowToken, account, shadowToSend);
                    emit ClaimRewards(account, shadowToken, shadowToSend);
                } else {
                    /// @dev transfer the expected rewards
                    _safeTransfer(tokens[i], account, _reward);
                    emit ClaimRewards(account, tokens[i], _reward);
                }
            }
        }
    }

    /// @inheritdoc IGauge
    function rewardPerToken(address token) public view returns (uint256) {
        if (totalSupply == 0) {
            return _rewardData[token].rewardPerTokenStored;
        }
        return
            _rewardData[token].rewardPerTokenStored +
            ((lastTimeRewardApplicable(token) -
                _rewardData[token].lastUpdateTime) *
                _rewardData[token].rewardRate) /
            totalSupply;
    }

    /// @inheritdoc IGauge
    function depositAll() external {
        /// @dev deposits all the stake tokens for the caller
        /// @dev msg.sender is retained
        deposit(IERC20(stake).balanceOf(msg.sender));
    }

    /// @inheritdoc IGauge
    function depositFor(
        address recipient,
        uint256 amount
    ) public updateReward(recipient) nonReentrant {
        /// @dev prevent zero deposits
        require(amount != 0, ZERO_AMOUNT());
        /// @dev pull the stake from the caller
        _safeTransferFrom(stake, msg.sender, address(this), amount);
        /// @dev increment the staked supply
        totalSupply += amount;
        /// @dev add amount to the recipient
        balanceOf[recipient] += amount;

        emit Deposit(recipient, amount);
    }

    /// @inheritdoc IGauge
    function deposit(uint256 amount) public {
        /// @dev deposit an amount for the caller
        depositFor(msg.sender, amount);
    }

    /// @inheritdoc IGauge
    function withdrawAll() external {
        /// @dev withdraw the whole balance of the caller
        /// @dev msg.sender is retained throughout
        withdraw(balanceOf[msg.sender]);
    }

    /// @inheritdoc IGauge
    function withdraw(
        uint256 amount
    ) public updateReward(msg.sender) nonReentrant {
        /// @dev prevent zero withdraws
        require(amount != 0, ZERO_AMOUNT());
        /// @dev decrement the totalSupply by the withdrawal amount
        totalSupply -= amount;
        /// @dev decrement the amount from the caller's mapping
        balanceOf[msg.sender] -= amount;
        /// @dev transfer the stake token to the caller
        _safeTransfer(stake, msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IGauge
    function left(address token) public view returns (uint256) {
        /// @dev if we are at or past the periodFinish for the token, return 0
        if (block.timestamp >= _rewardData[token].periodFinish) return 0;
        /// @dev calculate the remaining time from periodFinish to current
        uint256 _remaining = _rewardData[token].periodFinish - block.timestamp;
        /// @dev return the remaining time, multiplied by the reward rate then scale to precision
        return (_remaining * _rewardData[token].rewardRate) / PRECISION;
    }

    /// @inheritdoc IGauge
    function whitelistReward(address _reward) external {
        require(msg.sender == voter, NOT_AUTHORIZED());
        /// @dev voter checks for governance whitelist before allowing call
        tokenWhitelists.add(_reward);
        emit RewardWhitelisted(_reward, true);
    }

    /// @inheritdoc IGauge
    function removeRewardWhitelist(address _reward) external {
        require(msg.sender == voter, NOT_AUTHORIZED());
        tokenWhitelists.remove(_reward);
        emit RewardWhitelisted(_reward, false);
    }

    /// @inheritdoc IGauge
    /**
     * @notice amount must be greater than left() for the token, this is to prevent griefing attacks
     * @notice notifying rewards is completely permissionless
     * @notice if nobody registers for a newly added reward for the period it will remain in the contract indefinitely
     */
    function notifyRewardAmount(
        address token,
        uint256 amount
    ) external updateReward(address(0)) nonReentrant {
        /// @dev prevent notifying the stake token
        require(token != stake, CANT_NOTIFY_STAKE());
        /// @dev do not accept 0 amounts
        require(amount != 0, ZERO_AMOUNT());
        /// @dev ensure the token is whitelisted
        require(tokenWhitelists.contains(token), NOT_WHITELISTED());

        _rewardData[token].rewardPerTokenStored = rewardPerToken(token);

        if (!isReward[token]) {
            rewards.push(token);
            isReward[token] = true;
        }

        /// @dev check actual amount transferred for compatibility with fee on transfer tokens.
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        amount = balanceAfter - balanceBefore;

        if (block.timestamp >= _rewardData[token].periodFinish) {
            _rewardData[token].rewardRate = (amount * PRECISION) / DURATION;
        } else {
            /// @dev calculate the remaining seconds based on the current timestamp
            uint256 remaining = _rewardData[token].periodFinish -
                block.timestamp;
            /// @dev calculate what is currently leftover until the reward period finishes
            uint256 _left = remaining * _rewardData[token].rewardRate;
            /// @dev block DoS
            require(
                amount * PRECISION > _left,
                NOT_GREATER_THAN_REMAINING(amount * PRECISION, _left)
            );
            /// @dev update the rewardRate to include the newly added amount
            _rewardData[token].rewardRate =
                (amount * PRECISION + _left) /
                DURATION;
        }
        /// @dev update the timestamps
        _rewardData[token].lastUpdateTime = block.timestamp;
        _rewardData[token].periodFinish = block.timestamp + DURATION;
        /// @dev check the token balance in this contract
        uint256 balance = IERC20(token).balanceOf(address(this));

        /// @dev ensure it isn't "over-emitting"
        require(
            _rewardData[token].rewardRate <= (balance * PRECISION) / DURATION,
            REWARD_TOO_HIGH()
        );

        emit NotifyReward(msg.sender, token, amount);
    }

    function isWhitelisted(address token) public view returns (bool) {
        return tokenWhitelists.contains(token);
    }

    /** internal safe transfer functions */
    function _safeTransfer(address token, address to, uint256 value) internal {
        require(
            token.code.length > 0,
            TOKEN_ERROR(
                token
            ) /* throw address of the token as a custom error to help with debugging */
        );
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            TOKEN_ERROR(
                token
            ) /* throw address of the token as a custom error to help with debugging */
        );
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(
            token.code.length > 0,
            TOKEN_ERROR(
                token
            ) /* throw address of the token as a custom error to help with debugging */
        );
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            TOKEN_ERROR(
                token
            ) /* throw address of the token as a custom error to help with debugging */
        );
    }
}
