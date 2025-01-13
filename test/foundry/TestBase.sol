// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {WETH9} from "./mocks/WETH9.sol";
import {Shadow} from "../../contracts/Shadow.sol";
import {AccessHub} from "../../contracts/AccessHub.sol";
import {FeeRecipientFactory} from "../../contracts/factories/FeeRecipientFactory.sol";
import {Voter} from "../../contracts/Voter.sol";
import {FeeRecipient} from "../../contracts/FeeRecipient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {XShadow} from "../../contracts/xShadow/XShadow.sol";
import {MockX33} from "./AccessHub.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestBase is Test {
    address public constant ZERO_ADDRESS = address(0);
    address public constant TREASURY = address(0x1);
    address public constant ACCESS_MANAGER = address(0x2);
    address public constant TIMELOCK = address(0x3);
    WETH9 public WETH;
    Shadow public shadow;
    AccessHub public accessHub;
    FeeRecipientFactory public feeRecipientFactory;
    MockVoter public mockVoter;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token6Decimals;
    MockMinter public mockMinter;
    MockVoteModule public mockVoteModule;
    MockLauncherPlugin public mockLauncherPlugin;
    MockFeeCollector public mockFeeCollector;

    address public alice;
    address public bob;
    uint256 public bobPrivateKey;
    address public carol;
    FeeRecipient public feeRecipient;
    MockX33 public mockX33;

    function setUp() public virtual {
        alice = makeAddr("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        WETH = new WETH9();
        shadow = new Shadow(ACCESS_MANAGER);
        AccessHub implementation = new AccessHub();
        accessHub = AccessHub(address(new ERC1967Proxy(address(implementation), "")));
        mockVoteModule = new MockVoteModule();
        mockVoter = _createMockVoter();
        feeRecipientFactory = new FeeRecipientFactory(TREASURY, address(mockVoter), address(accessHub));
        vm.prank(address(mockVoter));
        feeRecipient = FeeRecipient(feeRecipientFactory.createFeeRecipient(address(token0)));
        mockMinter = new MockMinter();
        token0 = new MockERC20();
        token1 = new MockERC20();
        token6Decimals = new MockERC20();
        token0.initialize("Token0", "TK0", 18);
        token1.initialize("Token1", "TK1", 18);
        token6Decimals.initialize("Token6Decimals", "TK6D", 6);
        mockX33 = new MockX33();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(TREASURY, "treasury");
        vm.label(ACCESS_MANAGER, "access_manager");
        vm.label(TIMELOCK, "timelock");
        vm.label(address(WETH), "weth");
        vm.label(address(shadow), "emissions_token");
        vm.label(address(feeRecipient), "fee_recipient");
        vm.label(address(accessHub), "access_hub");
        vm.label(address(mockVoter), "mock_voter");
        vm.label(address(feeRecipientFactory), "fee_recipient_factory");
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        vm.label(address(token6Decimals), "token6Decimals");
        vm.label(address(mockMinter), "mock_minter");
        vm.label(address(mockVoteModule), "mock_vote_module");
    }

    function _dealAndApprove(address token, address to, uint256 amount, address spender) internal {
        deal(token, to, amount);
        vm.prank(to);
        MockERC20(token).approve(spender, type(uint256).max);
    }

    function _createMockVoter() internal returns (MockVoter) {
        return new MockVoter(
            makeAddr("launcherPlugin"), address(mockVoteModule), address(shadow), address(mockMinter)
        );
    }
}

contract MockVoter {
    address public launcherPlugin;
    address public voteModule;
    address public shadow;
    address public governor;
    address public minter;
    address public legacyFactory;
    address public gauges;
    address public feeDistributorFactory;
    address public msig;
    address public xShadow;
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

    constructor(address _launcherPlugin, address _voteModule, address _shadow, address _minter) {
        launcherPlugin = _launcherPlugin;
        voteModule = _voteModule;
        shadow = _shadow;
        minter = _minter;
    }

    function initialize(
        address _shadow,
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
        shadow = _shadow;
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
        IERC20(shadow).transferFrom(msg.sender, address(this), _amount);
    }

    function setCooldownExemption(address _candidate, bool _exempt) external {
        isCooldownExempt[_candidate] = _exempt;
    }
}

contract MockMinter {
    address public shadow;
    address public xShadow;
    address public voter;
    address public operator;
    address public accessHub;
    uint256 public emissionsMultiplier;
    uint256 public mockPeriod;

    function kickoff(address _shadow, address _voter, uint256, uint256, address _xShadow) external {
        shadow = _shadow;
        xShadow = _xShadow;
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
        IERC20(XShadow(msg.sender).SHADOW()).transferFrom(msg.sender, address(this), amount);
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
