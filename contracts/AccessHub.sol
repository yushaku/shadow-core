// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IAccessHub} from "contracts/interfaces/IAccessHub.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IMinter} from "contracts/interfaces/IMinter.sol";
import {ILauncherPlugin} from "contracts/interfaces/ILauncherPlugin.sol";
import {IXYSK} from "contracts/interfaces/IXYSK.sol";
import {IX33} from "contracts/interfaces/IX33.sol";

import {IRamsesV3Factory} from "contracts/CL/core/interfaces/IRamsesV3Factory.sol";
import {IPairFactory} from "contracts/interfaces/IPairFactory.sol";
import {IFeeRecipientFactory} from "contracts/interfaces/IFeeRecipientFactory.sol";
import {IRamsesV3Pool} from "contracts/CL/core/interfaces/IRamsesV3Pool.sol";
import {IFeeCollector} from "contracts/CL/gauge/interfaces/IFeeCollector.sol";
import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";

/**
 * @title AccessHub
 * @notice AccessHub is the main entry point for the protocol
 */
contract AccessHub is IAccessHub, UUPSUpgradeable, AccessControlEnumerableUpgradeable {
	bytes32 public constant SWAP_FEE_SETTER = keccak256("SWAP_FEE_SETTER");
	bytes32 public constant PROTOCOL_OPERATOR = keccak256("PROTOCOL_OPERATOR");

	address public timelock;
	address public treasury;

	/** "nice-to-have" addresses for quickly finding contracts within the system */
	address public clGaugeFactory;
	address public gaugeFactory;
	address public feeDistributorFactory;

	/** core contracts */
	IVoter public voter;
	IMinter public minter;
	ILauncherPlugin public launcherPlugin;
	IXYSK public xYushaku;
	IX33 public x33;
	IRamsesV3Factory public ramsesV3PoolFactory;
	IPairFactory public poolFactory;
	IFeeRecipientFactory public feeRecipientFactory;
	IFeeCollector public feeCollector;
	IVoteModule public voteModule;

	modifier timelocked() {
		require(msg.sender == timelock, NOT_TIMELOCK(msg.sender));
		_;
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(address admin) external initializer {
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
	}

	function _authorizeUpgrade(address newImplementation) internal view override {
		if (newImplementation == address(0)) revert INVALID_ADDRESS();
		_checkRole(DEFAULT_ADMIN_ROLE);
	}

	function setup(InitParams calldata params) external onlyRole(DEFAULT_ADMIN_ROLE) {
		voter = IVoter(params.voter);
		minter = IMinter(params.minter);
		launcherPlugin = ILauncherPlugin(params.launcherPlugin);
		xYushaku = IXYSK(params.xYushaku);
		x33 = IX33(params.x33);
		ramsesV3PoolFactory = IRamsesV3Factory(params.ramsesV3PoolFactory);
		poolFactory = IPairFactory(params.poolFactory);
		feeRecipientFactory = IFeeRecipientFactory(params.feeRecipientFactory);
		feeCollector = IFeeCollector(params.feeCollector);
		voteModule = IVoteModule(params.voteModule);
		treasury = params.treasury;
		timelock = params.timelock;

		/// @dev reference addresses
		clGaugeFactory = params.clGaugeFactory;
		gaugeFactory = params.gaugeFactory;
		feeDistributorFactory = params.feeDistributorFactory;
	}

	/***************************************************************************************/
	/* Fee Setting Logic */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function setSwapFees(
		address[] calldata _pools,
		uint24[] calldata _swapFees,
		bool[] calldata _concentrated
	) external onlyRole(SWAP_FEE_SETTER) {
		require(
			_pools.length == _swapFees.length && _swapFees.length == _concentrated.length,
			IVoter.LENGTH_MISMATCH()
		);

		for (uint256 i; i < _pools.length; ++i) {
			/// @dev we check if the pool is v3 or legacy and set their fees accordingly
			if (_concentrated[i]) {
				ramsesV3PoolFactory.setFee(_pools[i], _swapFees[i]);
			} else {
				poolFactory.setPairFee(_pools[i], _swapFees[i]);
			}
		}
	}

	/// @inheritdoc IAccessHub
	function setFeeSplitCL(
		address[] calldata _pools,
		uint8[] calldata _feeProtocol
	) external onlyRole(SWAP_FEE_SETTER) {
		/// @dev ensure continuity of length
		require(_pools.length == _feeProtocol.length, IVoter.LENGTH_MISMATCH());
		for (uint256 i; i < _pools.length; ++i) {
			ramsesV3PoolFactory.setPoolFeeProtocol(_pools[i], _feeProtocol[i]);
		}
	}

	/// @inheritdoc IAccessHub
	function setFeeSplitLegacy(
		address[] calldata _pools,
		uint256[] calldata _feeSplits
	) external onlyRole(SWAP_FEE_SETTER) {
		/// @dev ensure continuity of length
		require(_pools.length == _feeSplits.length, IVoter.LENGTH_MISMATCH());
		for (uint256 i; i < _pools.length; ++i) {
			poolFactory.setPairFeeSplit(_pools[i], _feeSplits[i]);
		}
	}

	/** Voter governance */

	/// @inheritdoc IAccessHub
	function setNewGovernorInVoter(address _newGovernor) external onlyRole(PROTOCOL_OPERATOR) {
		/// @dev no checks are needed as the voter handles this already
		voter.setGovernor(_newGovernor);
	}

	/// @inheritdoc IAccessHub
	function governanceWhitelist(
		address[] calldata _token,
		bool[] calldata _whitelisted
	) external onlyRole(PROTOCOL_OPERATOR) {
		/// @dev ensure continuity of length
		require(_token.length == _whitelisted.length, IVoter.LENGTH_MISMATCH());
		for (uint256 i; i < _token.length; ++i) {
			/// @dev if adding to the whitelist
			if (_whitelisted[i]) {
				/// @dev call the voter's whitelist function
				voter.whitelist(_token[i]);
			}
			/// @dev remove the token's whitelist
			else {
				voter.revokeWhitelist(_token[i]);
			}
		}
	}

	/// @inheritdoc IAccessHub
	function killGauge(address[] calldata _pairs) external onlyRole(PROTOCOL_OPERATOR) {
		for (uint256 i; i < _pairs.length; ++i) {
			/// @dev store pair
			address pair = _pairs[i];
			/// @dev collect fees from the pair
			feeCollector.collectProtocolFees(IRamsesV3Pool(pair));
			/// @dev kill the gauge
			voter.killGauge(voter.gaugeForPool(pair));
			/// @dev set the new fees in the pair to 95/5
			ramsesV3PoolFactory.setPoolFeeProtocol(pair, 5);
		}
	}

	/// @inheritdoc IAccessHub
	function reviveGauge(address[] calldata _pairs) external onlyRole(PROTOCOL_OPERATOR) {
		for (uint256 i; i < _pairs.length; ++i) {
			address pair = _pairs[i];
			/// @dev collect fees from the pair
			feeCollector.collectProtocolFees(IRamsesV3Pool(pair));
			/// @dev revive the pair
			voter.reviveGauge(voter.gaugeForPool(pair));
			/// @dev set fee to the factory default
			ramsesV3PoolFactory.setPoolFeeProtocol(pair, ramsesV3PoolFactory.feeProtocol());
		}
	}

	/// @inheritdoc IAccessHub
	function setEmissionsRatioInVoter(uint256 _pct) external onlyRole(PROTOCOL_OPERATOR) {
		voter.setGlobalRatio(_pct);
	}

	/// @inheritdoc IAccessHub
	function retrieveStuckEmissionsToGovernance(
		address _gauge,
		uint256 _period
	) external onlyRole(PROTOCOL_OPERATOR) {
		voter.stuckEmissionsRecovery(_gauge, _period);
	}

	/// @inheritdoc IAccessHub
	function setMainTickSpacingInVoter(
		address tokenA,
		address tokenB,
		int24 tickSpacing
	) external onlyRole(PROTOCOL_OPERATOR) {
		voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);
	}

	function createCLGaugeOveridden(
		address tokenA,
		address tokenB,
		int24 tickSpacing
	) external onlyRole(PROTOCOL_OPERATOR) {
		voter.createCLGauge(tokenA, tokenB, tickSpacing);
	}

	/***************************************************************************************/
	/* xYushaku Functions */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function transferWhitelistInXYushaku(
		address[] calldata _who,
		bool[] calldata _whitelisted
	) external onlyRole(PROTOCOL_OPERATOR) {
		/// @dev ensure continuity of length
		require(_who.length == _whitelisted.length, IVoter.LENGTH_MISMATCH());
		xYushaku.setExemption(_who, _whitelisted);
	}

	/// @inheritdoc IAccessHub
	function toggleXYushakuGovernance(bool enable) external onlyRole(PROTOCOL_OPERATOR) {
		/// @dev if enabled we call unpause otherwise we pause to disable
		enable ? xYushaku.unpause() : xYushaku.pause();
	}

	/// @inheritdoc IAccessHub
	function operatorRedeemXYushaku(uint256 _amount) external onlyRole(PROTOCOL_OPERATOR) {
		xYushaku.operatorRedeem(_amount);
	}

	/// @inheritdoc IAccessHub
	function migrateOperator(address _operator) external onlyRole(PROTOCOL_OPERATOR) {
		xYushaku.migrateOperator(_operator);
	}

	/// @inheritdoc IAccessHub
	function rescueTrappedTokens(
		address[] calldata _tokens,
		uint256[] calldata _amounts
	) external onlyRole(PROTOCOL_OPERATOR) {
		xYushaku.rescueTrappedTokens(_tokens, _amounts);
	}

	/***************************************************************************************/
	/* X33 Functions */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function transferOperatorInX33(address _newOperator) external onlyRole(PROTOCOL_OPERATOR) {
		x33.transferOperator(_newOperator);
	}

	/** Minter Functions */

	/// @inheritdoc IAccessHub
	function setEmissionsMultiplierInMinter(
		uint256 _multiplier
	) external onlyRole(PROTOCOL_OPERATOR) {
		minter.updateEmissionsMultiplier(_multiplier);
	}

	/** Reward List Functions */

	/// @inheritdoc IAccessHub
	function augmentGaugeRewardsForPair(
		address[] calldata _pools,
		address[] calldata _rewards,
		bool[] calldata _addReward
	) external onlyRole(PROTOCOL_OPERATOR) {
		/// @dev length continuity check
		require(
			_pools.length == _rewards.length && _rewards.length == _addReward.length,
			IVoter.LENGTH_MISMATCH()
		);
		/// @dev loop through all entries
		for (uint256 i; i < _pools.length; ++i) {
			/// @dev fetch the gauge address
			address gauge = voter.gaugeForPool(_pools[i]);
			/// @dev if true (add rewards)
			if (_addReward[i]) {
				voter.whitelistGaugeRewards(gauge, _rewards[i]);
			}
			/// @dev if false remove the rewards
			else {
				voter.removeGaugeRewardWhitelist(gauge, _rewards[i]);
			}
		}
	}

	/// @inheritdoc IAccessHub
	function removeFeeDistributorRewards(
		address[] calldata _pools,
		address[] calldata _rewards
	) external onlyRole(PROTOCOL_OPERATOR) {
		require(_pools.length == _rewards.length, IVoter.LENGTH_MISMATCH());
		for (uint256 i; i < _pools.length; ++i) {
			voter.removeFeeDistributorReward(
				voter.feeDistributorForGauge(voter.gaugeForPool(_pools[i])),
				_rewards[i]
			);
		}
	}

	/***************************************************************************************/
	/* LauncherPlugin specific functions */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function migratePoolInLauncherPlugin(
		address _oldPool,
		address _newPool
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.migratePool(_oldPool, _newPool);
	}

	/// @inheritdoc IAccessHub
	function setConfigsInLauncherPlugin(
		address _pool,
		uint256 _take,
		address _recipient
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.setConfigs(_pool, _take, _recipient);
	}

	/// @inheritdoc IAccessHub
	function enablePoolInLauncherPlugin(address _pool) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.enablePool(_pool);
	}

	/// @inheritdoc IAccessHub
	function disablePoolInLauncherPlugin(address _pool) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.disablePool(_pool);
	}

	/// @inheritdoc IAccessHub
	function setOperatorInLauncherPlugin(
		address _newOperator
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.setOperator(_newOperator);
	}

	/// @inheritdoc IAccessHub
	function grantAuthorityInLauncherPlugin(
		address _newAuthority,
		string calldata _label
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.grantAuthority(_newAuthority, _label);
	}

	/// @inheritdoc IAccessHub
	function labelAuthorityInLauncherPlugin(
		address _authority,
		string calldata _label
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.label(_authority, _label);
	}

	/// @inheritdoc IAccessHub
	function revokeAuthorityInLauncherPlugin(
		address _oldAuthority
	) external onlyRole(PROTOCOL_OPERATOR) {
		launcherPlugin.revokeAuthority(_oldAuthority);
	}

	/** FeeCollector functions */

	/// @inheritdoc IAccessHub
	function setTreasuryInFeeCollector(address newTreasury) external onlyRole(PROTOCOL_OPERATOR) {
		feeCollector.setTreasury(newTreasury);
	}

	/// @inheritdoc IAccessHub
	function setTreasuryFeesInFeeCollector(
		uint256 _treasuryFees
	) external onlyRole(PROTOCOL_OPERATOR) {
		feeCollector.setTreasuryFees(_treasuryFees);
	}

	/** FeeRecipientFactory functions */

	/// @inheritdoc IAccessHub
	function setFeeToTreasuryInFeeRecipientFactory(
		uint256 _feeToTreasury
	) external onlyRole(PROTOCOL_OPERATOR) {
		feeRecipientFactory.setFeeToTreasury(_feeToTreasury);
	}

	/// @inheritdoc IAccessHub
	function setTreasuryInFeeRecipientFactory(
		address _treasury
	) external onlyRole(PROTOCOL_OPERATOR) {
		feeRecipientFactory.setTreasury(_treasury);
	}

	/***************************************************************************************/
	/* CL Pool Factory functions */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function enableTickSpacing(
		int24 tickSpacing,
		uint24 initialFee
	) external onlyRole(PROTOCOL_OPERATOR) {
		ramsesV3PoolFactory.enableTickSpacing(tickSpacing, initialFee);
	}

	/// @inheritdoc IAccessHub
	function setGlobalClFeeProtocol(uint8 _feeProtocolGlobal) external onlyRole(PROTOCOL_OPERATOR) {
		ramsesV3PoolFactory.setFeeProtocol(_feeProtocolGlobal);
	}

	/// @inheritdoc IAccessHub
	/// @notice sets the address of the voter in the v3 factory for gauge fee setting
	function setVoterAddressInFactoryV3(address _voter) external timelocked {
		ramsesV3PoolFactory.setVoter(_voter);
	}

	/// @inheritdoc IAccessHub
	function setFeeCollectorInFactoryV3(address _newFeeCollector) external timelocked {
		ramsesV3PoolFactory.setFeeCollector(_newFeeCollector);
	}

	/** Legacy Pool Factory functions */

	/// @inheritdoc IAccessHub
	function setTreasuryInLegacyFactory(address _treasury) external onlyRole(PROTOCOL_OPERATOR) {
		poolFactory.setTreasury(_treasury);
	}

	/// @inheritdoc IAccessHub
	function setFeeSplitWhenNoGauge(bool status) external onlyRole(PROTOCOL_OPERATOR) {
		poolFactory.setFeeSplitWhenNoGauge(status);
	}

	/// @inheritdoc IAccessHub
	function setLegacyFeeSplitGlobal(uint256 _feeSplit) external onlyRole(PROTOCOL_OPERATOR) {
		poolFactory.setFeeSplit(_feeSplit);
	}

	/// @inheritdoc IAccessHub
	function setLegacyFeeGlobal(uint256 _fee) external onlyRole(PROTOCOL_OPERATOR) {
		poolFactory.setFee(_fee);
	}

	/// @inheritdoc IAccessHub
	function setSkimEnabledLegacy(
		address _pair,
		bool _status
	) external onlyRole(PROTOCOL_OPERATOR) {
		poolFactory.setSkimEnabled(_pair, _status);
	}

	/***************************************************************************************/
	/* VoteModule Functions*/
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function setCooldownExemption(
		address[] calldata _candidates,
		bool[] calldata _exempt
	) external timelocked {
		for (uint256 i; i < _candidates.length; ++i) {
			voteModule.setCooldownExemption(_candidates[i], _exempt[i]);
		}
	}

	/// @inheritdoc IAccessHub
	function setNewRebaseStreamingDuration(uint256 _newDuration) external timelocked {
		voteModule.setNewDuration(_newDuration);
	}

	/// @inheritdoc IAccessHub
	function setNewVoteModuleCooldown(uint256 _newCooldown) external timelocked {
		voteModule.setNewCooldown(_newCooldown);
	}

	/// @inheritdoc IAccessHub
	function kickInactive(
		address[] calldata _nonparticipants
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		IVoter voterContract = IVoter(voter);
		uint256 nextPeriod = voterContract.getPeriod() + 1;

		/// @dev loop through all input addresses to check status of vote
		for (uint256 i; i < _nonparticipants.length; ++i) {
			/// @dev store for use
			address nonparticipant = _nonparticipants[i];
			/// @dev fetch data on current voting period (nextPeriod votes)
			(address[] memory _pools, uint256[] memory _weights) = voterContract.getVotes(
				nonparticipant,
				nextPeriod
			);

			/// @dev require the user has not voted this epoch
			require(_pools.length == 0 && _weights.length == 0, KICK_FORBIDDEN(nonparticipant));
			/// @dev reset the user's votes
			voterContract.reset(nonparticipant);
		}
	}

	/***************************************************************************************/
	/* Timelock specific functions */
	/***************************************************************************************/

	/// @inheritdoc IAccessHub
	function execute(address _target, bytes calldata _payload) external timelocked {
		(bool success, ) = _target.call(_payload);
		require(success, MANUAL_EXECUTION_FAILURE(_payload));
	}

	/// @inheritdoc IAccessHub
	function setNewTimelock(address _timelock) external timelocked {
		if (timelock == _timelock) revert SAME_ADDRESS();
		timelock = _timelock;
	}
}
