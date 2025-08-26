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
	/// @notice decimal precision of 1e18
	uint256 public constant PRECISION = 10 ** 18;

	address public accessHub;
	address public voter;
	IXYSK public xYSK;
	IERC20 public underlying;

	/// @notice rebases are released over 30 minutes
	uint256 public duration;

	/// @notice lock period after rebase starts accruing
	uint256 public cooldown;

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

	function _authorizeUpgrade(address newImplementation) internal view override {
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

		duration = 30 minutes;
		cooldown = 12 hours;
	}

	/// @dev Common modifier used to update reward state on user interactions
	/// @param account The address of the account to update rewards for
	/// @notice Updates global reward state and user-specific reward state
	/// @dev Similar to multi-rewarder pattern but for single reward token
	modifier updateReward(address account) {
		// Update global reward state
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = lastTimeRewardApplicable();

		// Update user-specific reward state if valid account
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

		lastUpdateTime = block.timestamp;
		periodFinish = block.timestamp + duration;
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
	/// @notice Returns the last time rewards were applicable (capped at period finish)
	/// @dev This ensures rewards stop accruing when the reward period ends
	/// @return The last time rewards were applicable
	function lastTimeRewardApplicable() public view returns (uint256) {
		return Math.min(block.timestamp, periodFinish);
	}

	/// @notice Calculates the total rewards earned by an account
	/// @dev This function computes rewards using a reward-per-token mechanism:
	///      1. Calculates new rewards since last update: (current reward per token - user's stored reward per token) * user balance
	///      2. Adds any previously stored rewards that haven't been claimed yet
	/// @param account The address to calculate rewards for
	/// @return Total rewards earned by the account (in underlying token units)
	function earned(address account) public view returns (uint256) {
		uint256 currentRewardPerToken = rewardPerToken();
		uint256 newRewards = (balanceOf[account] *
			(currentRewardPerToken - userRewardPerTokenStored[account])) / PRECISION;

		return newRewards + storedRewardsPerUser[account];
	}

	/// @inheritdoc IVoteModule
	function getReward() external updateReward(msg.sender) nonReentrant {
		_claim(msg.sender);
	}

	/// @notice Calculates the current reward per token (scaled by PRECISION)
	/// @dev This function computes the global reward per token rate:
	///      - If no tokens are staked, returns the stored value
	///      - Otherwise, adds new rewards accrued since last update to the stored value
	///      - New rewards = (time elapsed * reward rate * PRECISION) / total supply
	/// @return Current reward per token (scaled by 10^18)
	function rewardPerToken() public view returns (uint256) {
		if (totalSupply == 0) return rewardPerTokenStored;

		uint256 timeElapsed = lastTimeRewardApplicable() - lastUpdateTime;
		uint256 newRewards = (timeElapsed * rewardRate * PRECISION) / totalSupply;
		return rewardPerTokenStored + newRewards;
	}

	/// @notice Returns the amount of rewards remaining to be distributed in the current period
	/// @dev Calculates remaining rewards based on time left in the reward period
	/// @return Amount of rewards remaining to be distributed
	function left() public view returns (uint256) {
		if (block.timestamp >= periodFinish) return 0;
		return (periodFinish - block.timestamp) * rewardRate;
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
