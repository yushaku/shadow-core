// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IVoteModule} from "./interfaces/IVoteModule.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IXYSK} from "./interfaces/IXYSK.sol";

/**
 * @title Vote Module
 * @notice This contract is responsible for managing the staking and delegation of the xYSK token.
 * It serves as the primary module for determining a user's voting power within the YSK protocol.
 *
 * Key Features:
 * - Staking: Users can deposit and withdraw their xYSK tokens to and from the contract.
 * - Reward Distribution: The contract receives rewards and distributes them to stakers over a set duration.
 * - Delegation: Users can delegate their voting power to another address, allowing that address to vote on their behalf.
 * - Cooldown: A cooldown period is enforced for withdrawals after a rebase event to ensure system stability.
 * - Poke: The contract notifies the Voter contract of any changes in a user's staked balance, ensuring that their voting power is always up-to-date.
 */
contract VoteModule is
	IVoteModule,
	OwnableUpgradeable,
	ReentrancyGuardUpgradeable,
	UUPSUpgradeable
{
	address public accessHub;
	address public voter;
	IXYSK public xYSK;
	IERC20 public underlying;

	/// @notice rebases are released over 30 minutes
	uint256 public duration = 30 minutes;

	/// @notice lock period after rebase starts accruing
	uint256 public cooldown = 12 hours;

	/// @notice decimal precision of 1e18
	uint256 public constant PRECISION = 10 ** 18;

	uint256 public totalSupply;
	uint256 public lastUpdateTime;
	uint256 public rewardPerTokenStored;
	uint256 public periodFinish;
	uint256 public rewardRate;
	uint256 public unlockTime;

	mapping(address user => uint256 amount) public balanceOf;
	mapping(address user => uint256 rewardPerToken) public userRewardPerTokenStored;
	mapping(address user => uint256 rewards) public storedRewardsPerUser;
	mapping(address delegator => address delegatee) public delegates;
	mapping(address owner => address operator) public admins;
	mapping(address user => bool exempt) public cooldownExempt;

	constructor() {
		_disableInitializers();
	}

	function _authorizeUpgrade(address newImplementation) internal override {
		if (newImplementation == address(0)) revert INVALID_ADDRESS();
		_checkOwner();
	}

	modifier onlyAccessHub() {
		require(msg.sender == accessHub, NOT_ACCESSHUB());
		_;
	}

	function initialize(address _admin, address _voter, address _accessHub) external initializer {
		if (_accessHub == address(0)) revert INVALID_ADDRESS();
		if (_admin == address(0)) revert INVALID_ADDRESS();
		if (_voter == address(0)) revert INVALID_ADDRESS();

		__Ownable_init(_admin);
		voter = _voter;
		accessHub = _accessHub;
	}

	/// @dev common multi-rewarder-esquee modifier for updating on interactions
	modifier updateReward(address account) {
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = lastTimeRewardApplicable();
		if (account != address(0)) {
			storedRewardsPerUser[account] = earned(account);
			userRewardPerTokenStored[account] = rewardPerTokenStored;
		}
		_;
	}

	/***************************************************************************************/
	/* AccessHub/owner Functions */
	/***************************************************************************************/

	function setUp(address _xYSK) external onlyOwner {
		xYSK = IXYSK(_xYSK);
		underlying = IERC20(xYSK.YSK());
	}

	function setAccessHub(address _accessHub) external onlyAccessHub {
		if (_accessHub == address(0)) revert INVALID_ADDRESS();
		accessHub = _accessHub;
	}

	/// @inheritdoc IVoteModule
	function setCooldownExemption(address _user, bool _exempt) external onlyAccessHub {
		require(cooldownExempt[_user] != _exempt, NO_CHANGE());
		cooldownExempt[_user] = _exempt;

		emit ExemptedFromCooldown(_user, _exempt);
	}

	/// @inheritdoc IVoteModule
	function setNewDuration(uint256 _durationInSeconds) external onlyAccessHub {
		require(_durationInSeconds != 0 && _durationInSeconds <= 7 days, INVALID_TIME());

		uint256 oldDuration = duration;
		duration = _durationInSeconds;
		emit NewDuration(oldDuration, duration);
	}

	/// @inheritdoc IVoteModule
	function setNewCooldown(uint256 _cooldownInSeconds) external onlyAccessHub {
		require(_cooldownInSeconds <= 7 days, INVALID_TIME());

		uint256 oldCooldown = cooldown;
		cooldown = _cooldownInSeconds;
		emit NewCooldown(oldCooldown, cooldown);
	}

	/***************************************************************************************/
	/* User Functions */
	/***************************************************************************************/

	/// @inheritdoc IVoteModule
	function deposit(uint256 amount) public updateReward(msg.sender) nonReentrant {
		if (amount == 0) revert ZERO_AMOUNT();

		/// @dev if the caller is not exempt
		/// @dev block interactions during the cooldown period
		if (!cooldownExempt[msg.sender]) {
			require(block.timestamp >= unlockTime, COOLDOWN_ACTIVE());
		}

		if (amount == type(uint256).max) {
			amount = IERC20(xYSK).balanceOf(msg.sender);
		}

		/// @dev transfer xYSK in
		IERC20(xYSK).transferFrom(msg.sender, address(this), amount);
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
	function withdraw(uint256 amount) public updateReward(msg.sender) nonReentrant {
		if (amount == 0) revert ZERO_AMOUNT();

		/// @dev if the caller is not exempt
		if (!cooldownExempt[msg.sender]) {
			/// @dev block interactions during the cooldown period
			require(block.timestamp >= unlockTime, COOLDOWN_ACTIVE());
		}

		/// @dev reduce total "supply"
		totalSupply -= amount;
		/// @dev decrement from balance mapping
		balanceOf[msg.sender] -= amount;
		/// @dev transfer the xYSK to the caller
		IERC20(xYSK).transfer(msg.sender, amount);

		/// @dev update data via poke
		/// @dev we check in voter that msg.sender is the VoteModule
		IVoter(voter).poke(msg.sender);

		emit Withdraw(msg.sender, amount);
	}

	/// @inheritdoc IVoteModule
	/// @dev only callable by xYSK contract
	/// @dev this is ONLY callable by xYSK, which has important safety checks
	function notifyRewardAmount(uint256 amount) external updateReward(address(0)) nonReentrant {
		require(amount != 0, ZERO_AMOUNT());
		require(msg.sender == address(xYSK), NOT_X_YSK());

		underlying.transferFrom(address(xYSK), address(this), amount);

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
		/// @dev not DoSable because only xYSK can notify
		unlockTime = cooldown + periodFinish;

		emit NotifyReward(msg.sender, amount);
	}

	/// @inheritdoc IVoteModule
	function delegate(address delegatee) external {
		bool _isAdded = false;
		if (delegatee == address(0) && delegates[msg.sender] != address(0)) {
			delete delegates[msg.sender];
		} else {
			delegates[msg.sender] = delegatee;
			_isAdded = true;
		}

		emit Delegate(msg.sender, delegatee, _isAdded);
	}

	/// @inheritdoc IVoteModule
	function setAdmin(address admin) external {
		bool _isAdded = false;

		if (admin == address(0) && admins[msg.sender] != address(0)) {
			delete admins[msg.sender];
		} else {
			admins[msg.sender] = admin;
			_isAdded = true;
		}

		emit SetAdmin(msg.sender, admin, _isAdded);
	}

	/***************************************************************************************/
	/* Internal Functions */
	/***************************************************************************************/

	/// @dev internal claim function to make exiting and claiming easier
	function _claim(address _user) internal {
		uint256 reward = storedRewardsPerUser[_user];

		if (reward > 0) {
			storedRewardsPerUser[_user] = 0;
			underlying.approve(address(xYSK), reward);
			xYSK.convertEmissionsToken(reward);
			IERC20(xYSK).transfer(_user, reward);
			emit ClaimRewards(_user, reward);
		}
	}

	/***************************************************************************************/
	/* View Functions */
	/***************************************************************************************/

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
		_claim(msg.sender);
	}

	/// @inheritdoc IVoteModule
	/// @dev the return value is scaled (multiplied) by PRECISION = 10 ** 18
	function rewardPerToken() public view returns (uint256 _rpt) {
		_rpt = (
			/// @dev if there's no staked xYSK
			totalSupply == 0 /// @dev return the existing value
				? rewardPerTokenStored /// @dev else add the existing value
				: rewardPerTokenStored +
					/// @dev to remaining time (since update) multiplied by the current reward rate
					/// @dev scaled to precision of 1e18, then divided by the total supply
					(((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * PRECISION) /
						totalSupply)
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

	function isDelegateFor(address caller, address owner) external view returns (bool approved) {
		/// @dev check the delegate mapping AND admin mapping due to hierarchy (admin > delegate)
		return (delegates[owner] == caller || admins[owner] == caller || caller == owner);
	}

	/// @dev return whether the caller is the address in the map
	/// @dev return true if caller is the owner as well
	function isAdminFor(address caller, address owner) external view returns (bool approved) {
		return (admins[owner] == caller || caller == owner);
	}
}
