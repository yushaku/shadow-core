// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IFeeDistributor} from "contracts/interfaces/IFeeDistributor.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";
import {ILauncherPlugin} from "contracts/interfaces/ILauncherPlugin.sol";

/**
 * @title Fee Distributor
 * @notice This contract is the central hub for distributing fees and other incentives to the users who have voted for a specific liquidity pool (gauge).
 * It aggregates fees from all the different pools and manages the complex logic of distributing them to the voters.
 *
 * Key Features:
 * - Reward Distribution: Distributes various reward tokens to voters based on their voting weight in a given period (epoch).
 * - Incentives (Bribes): Allows external users to "incentivize" or "bribe" a pool by sending tokens to this contract, which are then distributed to the voters of that pool.
 * - Fee Collection: Receives fees from the FeeRecipient contract and adds them to the pool of rewards to be distributed.
 * - Launcher Plugin Integration: Integrates with a LauncherPlugin, which can be configured to take a percentage of the fees for its services.
 * - Periodic Distribution: The rewards are distributed on a periodic basis (weekly).
 */
contract FeeDistributor is IFeeDistributor, ReentrancyGuard {
	using EnumerableSet for EnumerableSet.AddressSet;

	address public immutable voter;
	address public immutable voteModule;
	address public immutable feeRecipient;
	uint256 public immutable firstPeriod;
	ILauncherPlugin public immutable plugin;

	mapping(address owner => uint256 amount) public balanceOf;
	mapping(uint256 period => uint256 weight) public votes;
	mapping(uint256 period => mapping(address owner => uint256 weight)) public userVotes;
	mapping(uint256 period => mapping(address token => uint256 amount)) public rewardSupply;
	mapping(address token => mapping(address owner => uint256 period)) public lastClaimByToken;
	mapping(uint256 period => mapping(address owner => mapping(address token => uint256 amount)))
		public userClaimed;

	EnumerableSet.AddressSet rewards;

	constructor(address _voter, address _feeRecipient) {
		voter = _voter;
		feeRecipient = _feeRecipient;

		plugin = ILauncherPlugin(IVoter(_voter).launcherPlugin());
		voteModule = IVoter(_voter).voteModule();
		firstPeriod = getPeriod();
	}

	/// @inheritdoc IFeeDistributor
	/// @dev specific to periods rather than all
	function getPeriodReward(uint256 period, address owner, address token) external nonReentrant {
		require(IVoteModule(voteModule).isAdminFor(msg.sender, owner), NOT_AUTHORIZED());
		_getReward(period, owner, token, msg.sender);
		lastClaimByToken[token][owner] = period - 1;
	}

	/// @inheritdoc IFeeDistributor
	function getReward(address owner, address[] memory tokens) external nonReentrant {
		require(IVoteModule(voteModule).isAdminFor(msg.sender, owner), NOT_AUTHORIZED());
		_getAllRewards(owner, tokens, msg.sender);
	}

	/// @inheritdoc IFeeDistributor
	function notifyRewardAmount(address token, uint256 amount) external nonReentrant {
		require(msg.sender == feeRecipient, NOT_AUTHORIZED());
		require(amount != 0, ZERO_AMOUNT());
		require(IVoter(voter).isWhitelisted(token), IVoter.NOT_WHITELISTED());

		uint256 nextPeriod = getPeriod() + 1;
		rewards.add(token);

		/** LAUNCHPAD CONFIGS **/

		/// @dev if part of a launcher system
		if (_enabledLauncherConfig()) {
			/// @dev set config values
			/// @dev this is OK if the configs are not set, as we handle zeroing it out later
			(uint256 _take, address _recipient) = plugin.values(address(this));

			/// @dev 10_000 is the denom of 100%
			uint256 send = (amount * _take) / 10_000;
			/// @dev send fee to launcher recipient
			if (send != 0) {
				_safeTransferFrom(token, msg.sender, _recipient, send);
				/// @dev deduct from voter-earned fees to prevent a shortfall
				amount -= send;
			}
		}

		/** END LAUNCHPAD CONFIGS **/

		/// @dev logic for handling tax tokens via legacy
		/// @dev V3 (CL) does not support tax or non-typical ERC20 implementations so this is null in those cases
		uint256 balanceBefore = IERC20(token).balanceOf(address(this));
		_safeTransferFrom(token, msg.sender, address(this), amount);
		uint256 balanceAfter = IERC20(token).balanceOf(address(this));

		/// @dev increase rewards for "nextPeriod"
		amount = balanceAfter - balanceBefore;
		rewardSupply[nextPeriod][token] += amount;

		emit NotifyReward(msg.sender, token, amount, nextPeriod);
	}

	/// @inheritdoc IFeeDistributor
	/// @dev submit voting incentives(bribed) to the FeeDistributor
	function incentivize(address token, uint256 amount) external nonReentrant {
		require(amount != 0, ZERO_AMOUNT());
		require(IVoter(voter).isWhitelisted(token), IVoter.NOT_WHITELISTED());

		uint256 nextPeriod = getPeriod() + 1;
		rewards.add(token);

		/// @dev logic for handling tax tokens as bribes
		uint256 balanceBefore = IERC20(token).balanceOf(address(this));
		_safeTransferFrom(token, msg.sender, address(this), amount);
		uint256 balanceAfter = IERC20(token).balanceOf(address(this));

		amount = balanceAfter - balanceBefore;
		rewardSupply[nextPeriod][token] += amount;

		emit VotesIncentivized(msg.sender, token, amount, nextPeriod);
	}

	/***************************************************************************************/
	/* Voter.sol Functions */
	/***************************************************************************************/

	/// @inheritdoc IFeeDistributor
	/// @dev used by Voter to allow batched reward claims
	function getRewardForOwner(address owner, address[] memory tokens) external nonReentrant {
		require(msg.sender == voter, NOT_AUTHORIZED());
		_getAllRewards(owner, tokens, owner);
	}

	/// @inheritdoc IFeeDistributor
	/// @dev for the voter to remove spam rewards
	function removeReward(address _token) external {
		require(msg.sender == voter, NOT_AUTHORIZED());

		rewards.remove(_token);
		emit RewardsRemoved(_token);
	}

	/// @inheritdoc IFeeDistributor
	function _deposit(uint256 amount, address owner) external {
		require(msg.sender == voter, NOT_AUTHORIZED());

		/// @dev fetch the next period (voting power slot)
		uint256 nextPeriod = getPeriod() + 1;

		balanceOf[owner] += amount;
		votes[nextPeriod] += amount;
		userVotes[nextPeriod][owner] += amount;

		emit Deposit(owner, amount);
	}

	/// @inheritdoc IFeeDistributor
	function _withdraw(uint256 amount, address owner) external {
		/// @dev gate to the voter
		require(msg.sender == voter, NOT_AUTHORIZED());
		/// @dev fetch the next period (voting power slot)
		uint256 nextPeriod = getPeriod() + 1;
		/// @dev decrement the mapping by withdrawal amount
		balanceOf[owner] -= amount;
		/// @dev check if the owner has any votes cast
		if (userVotes[nextPeriod][owner] > 0) {
			/// @dev if so -- decrement vote by amount
			userVotes[nextPeriod][owner] -= amount;
			/// @dev and decrement cumulative votes
			votes[nextPeriod] -= amount;
		}

		emit Withdraw(owner, amount);
	}

	/***************************************************************************************/
	/* View Functions */
	/***************************************************************************************/

	/// @notice general read function for grabbing the current period (epoch)
	function getPeriod() public view returns (uint256) {
		return (block.timestamp / 1 weeks);
	}

	/// @inheritdoc IFeeDistributor
	function getRewardTokens() external view returns (address[] memory _rewards) {
		/// @dev return the values from the set
		/// @dev to prevent unbound expansion removeReward() is to be used when necessary
		_rewards = rewards.values();
	}

	/// @inheritdoc IFeeDistributor
	function earned(address token, address owner) external view returns (uint256 reward) {
		uint256 currentPeriod = getPeriod();
		uint256 lastClaim = Math.max(lastClaimByToken[token][owner], firstPeriod);

		/// @dev loop from the lastClaim up to and including the current period
		for (uint256 period = lastClaim; period <= currentPeriod; ++period) {
			/// @dev if there are votes for the period
			if (votes[period] != 0) {
				/// @dev fetch rewardSupply scaled to weight
				uint256 votesWeight = (userVotes[period][owner] * 1e18) / votes[period];
				reward += (rewardSupply[period][token] * votesWeight) / 1e18;
				/// @dev remove already claimed rewards to prevent shortfalls and over-rewarding
				reward -= userClaimed[period][owner][token];
			}
		}
	}

	/***************************************************************************************/
	/* Internal Functions */
	/***************************************************************************************/

	/// @dev a core internal function for claiming rewards
	function _getReward(uint256 period, address owner, address token, address receiver) internal {
		require(period <= getPeriod(), NOT_FINALIZED());

		/// @dev if there are any votes in the period
		if (votes[period] != 0) {
			uint256 votesWeight = (userVotes[period][owner] * 1e18) / votes[period];

			uint256 _reward = (rewardSupply[period][token] * votesWeight) / 1e18;
			_reward -= userClaimed[period][owner][token];
			userClaimed[period][owner][token] += _reward;

			if (_reward > 0) {
				_safeTransfer(token, receiver, _reward);
				emit ClaimRewards(period, owner, receiver, token, _reward);
			}
		}
	}

	function _getAllRewards(address owner, address[] memory tokens, address receiver) internal {
		uint256 currentPeriod = getPeriod();
		uint256 lastClaim;

		for (uint256 i = 0; i < tokens.length; ++i) {
			lastClaim = Math.max(lastClaimByToken[tokens[i]][owner], firstPeriod);
			/// @dev nested loop starting from the lastClaim to up to and including the current period
			for (uint256 period = lastClaim; period <= currentPeriod; ++period) {
				/// @dev call _getReward per each token
				_getReward(period, owner, tokens[i], receiver);
			}
			/// @dev we set the previous period as the last claim to follow the for-loop scheme
			lastClaimByToken[tokens[i]][owner] = currentPeriod - 1;
		}
	}

	/// @dev internal function for fetching the the current launcher config status from voter
	function _enabledLauncherConfig() internal view returns (bool _enabled) {
		/// @dev if the pool has the launcher configs enabled return true
		_enabled = plugin.launcherPluginEnabled(plugin.feeDistToPool(address(this)));
	}

	/** internal safe transfer functions */
	function _safeTransfer(address token, address to, uint256 value) internal {
		require(token.code.length > 0, TOKEN_ERROR(token));
		(bool success, bytes memory data) = token.call(
			abi.encodeWithSelector(IERC20.transfer.selector, to, value)
		);
		require(success && (data.length == 0 || abi.decode(data, (bool))), TOKEN_ERROR(token));
	}

	function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
		require(token.code.length > 0, TOKEN_ERROR(token));
		(bool success, bytes memory data) = token.call(
			abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
		);

		require(success && (data.length == 0 || abi.decode(data, (bool))), TOKEN_ERROR(token));
	}
}
