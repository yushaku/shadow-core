// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {XYSK} from "contracts/x/XYSK.sol";

contract MockX33 {
	address public operator;
	address public accessHub;
	address public xysk;
	address public voter;
	address public voteModule;

	function initialize(
		address _operator,
		address _accessHub,
		address _xysk,
		address _voter,
		address _voteModule
	) external {
		operator = _operator;
		accessHub = _accessHub;
		xysk = _xysk;
		voter = _voter;
		voteModule = _voteModule;
	}
}

contract MockMinter {
	address public ysk;
	address public xysk;
	address public voter;
	address public operator;
	address public accessHub;
	uint256 public emissionsMultiplier;
	uint256 public mockPeriod;

	function kickoff(address _ysk, address _voter, uint256, uint256, address _xysk) external {
		ysk = _ysk;
		xysk = _xysk;
		voter = _voter;
	}

	function updatePeriod() external returns (uint256 period) {
		mockPeriod++;
		return mockPeriod;
	}

	function notifyRewardAmount(uint256 _amount) external {
		// Mock implementation
	}

	function setEmissionsMultiplier(uint256 _multiplier) external {
		emissionsMultiplier = _multiplier;
	}

	function updateEmissionsMultiplier(uint256 _multiplier) external {
		emissionsMultiplier = _multiplier;
	}
}

contract MockVoteModule {
	function notifyRewardAmount(uint256 amount) external {
		IERC20(XYSK(msg.sender).YSK()).transferFrom(msg.sender, address(this), amount);
	}

	function isAdminFor(address, address) external pure returns (bool) {
		return true;
	}
}

contract MockLauncherPlugin {
	function setConfigs(address _pool, uint256 _take, address _recipient) external {
		// Mock implementation
	}

	function enablePool(address _pool) external {
		// Mock implementation
	}

	function migratePool(address _oldPool, address _newPool) external {
		// Mock implementation
	}
}

contract MockFeeCollector {
	function collect(address _pool, uint256 _amount) external {
		// Mock implementation
	}
}

contract MockVoter {
	address public launcherPlugin;
	address public voteModule;
	address public ysk;
	address public governor;
	address public minter;
	address public legacyFactory;
	address public gauges;
	address public feeDistributorFactory;
	address public msig;
	address public xYSK;
	address public clFactory;
	address public clGaugeFactory;
	address public nfpManager;
	mapping(address => bool) public isWhitelisted;
	mapping(address => uint8) public feeSplits;
	mapping(address => uint24) public swapFees;
	mapping(address => bool) public isConcentrated;
	mapping(address => bool) public isCooldownExempt;
	// Add new state variables to track function calls
	mapping(address => bool) public isKilled;
	mapping(address => address) public gaugeForPool;
	mapping(address => address) public feeDistributorForGauge;
	uint256 public globalRatio;
	mapping(address => mapping(address => bool)) public gaugeRewardWhitelist;

	constructor(address _launcherPlugin, address _voteModule, address _ysk, address _minter) {
		launcherPlugin = _launcherPlugin;
		voteModule = _voteModule;
		ysk = _ysk;
		minter = _minter;
	}

	function initialize(
		address _ysk,
		address _legacyFactory,
		address _gauges,
		address _feeDistributorFactory,
		address _minter,
		address,
		address,
		address,
		address,
		address,
		address,
		address,
		address
	) external {
		ysk = _ysk;
		legacyFactory = _legacyFactory;
		gauges = _gauges;
		feeDistributorFactory = _feeDistributorFactory;
		minter = _minter;
	}

	function whitelist(address[] memory _tokens, bool[] memory _whitelisted) external {
		for (uint256 i = 0; i < _tokens.length; i++) {
			isWhitelisted[_tokens[i]] = _whitelisted[i];
		}
	}

	function setFeeSplits(address[] memory _pools, uint8[] memory _feeSplits) external {
		for (uint256 i = 0; i < _pools.length; i++) {
			feeSplits[_pools[i]] = _feeSplits[i];
		}
	}

	function setSwapFees(address[] memory _pools, uint24[] memory _swapFees) external {
		for (uint256 i = 0; i < _pools.length; i++) {
			swapFees[_pools[i]] = _swapFees[i];
		}
	}

	function setIsConcentrated(address[] memory _pools, bool[] memory _concentrated) external {
		for (uint256 i = 0; i < _pools.length; i++) {
			isConcentrated[_pools[i]] = _concentrated[i];
		}
	}

	function setGovernor(address _newGovernor) external {
		governor = _newGovernor;
	}

	// Add missing mock functions
	function whitelist(address _token) external {
		isWhitelisted[_token] = true;
	}

	function revokeWhitelist(address _token) external {
		isWhitelisted[_token] = false;
	}

	function killGauge(address _gauge) external {
		isKilled[_gauge] = true;
	}

	function reviveGauge(address _gauge) external {
		isKilled[_gauge] = false;
	}

	function setGlobalRatio(uint256 _ratio) external {
		globalRatio = _ratio;
	}

	function whitelistGaugeRewards(address _gauge, address _reward) external {
		gaugeRewardWhitelist[_gauge][_reward] = true;
	}

	function removeGaugeRewardWhitelist(address _gauge, address _reward) external {
		gaugeRewardWhitelist[_gauge][_reward] = false;
	}

	function removeFeeDistributorReward(address _feeDistributor, address _reward) external {
		// Mock implementation - could add state tracking if needed for tests
	}

	// Helper function to set up gauge mappings for testing
	function setGaugeForPool(address _pool, address _gauge) external {
		gaugeForPool[_pool] = _gauge;
	}

	// Helper function to set up fee distributor mappings for testing
	function setFeeDistributorForGauge(address _gauge, address _feeDistributor) external {
		feeDistributorForGauge[_gauge] = _feeDistributor;
	}

	function isGauge(address) external pure returns (bool) {
		return false;
	}

	function isFeeDistributor(address) external pure returns (bool) {
		return false;
	}

	function getPeriod() external pure returns (uint256) {
		return 1;
	}

	function notifyRewardAmount(uint256 _amount) external {
		// Mock implementation
		IERC20(ysk).transferFrom(msg.sender, address(this), _amount);
	}

	function setCooldownExemption(address _candidate, bool _exempt) external {
		isCooldownExempt[_candidate] = _exempt;
	}
}
