// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployFull} from "../../../scripts/foundry/non-cl/DeployFull.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVoter} from "../../../contracts/interfaces/IVoter.sol";
import {IVoteModule} from "../../../contracts/interfaces/IVoteModule.sol";
import {IXShadow} from "../../../contracts/interfaces/IXShadow.sol";
import {IERC20Extended} from "../../../contracts/interfaces/IERC20Extended.sol";
import {IPairFactory} from "../../../contracts/interfaces/IPairFactory.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {AccessHub} from "../../../contracts/AccessHub.sol";
import {Minter} from "../../../contracts/Minter.sol";
import {IGauge} from "../../../contracts/interfaces/IGauge.sol";
import {IPair} from "../../../contracts/interfaces/IPair.sol";
import {console} from "forge-std/console.sol";

contract FullEmissionAndVoteTest is Test, DeployFull {
    // Test user address
    address public user = makeAddr("user");
    address public protocolOperator;
    address public treasury;

    // Amount of emissions tokens to test with
    uint256 constant INITIAL_AMOUNT = 100 ether;

    DeployedContracts contracts;

    function setUp() public {
        // Set block timestamp to current unix timestamp
        vm.warp(1733961600); // 1733961600 is the unix timestamp for the first week of 2024
        // Deploy all contracts
        contracts = deployForTest();

        // Read protocol operator from testnet config
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/foundry/non-cl/config/testnet.json");
        string memory json = vm.readFile(path);
        protocolOperator = abi.decode(vm.parseJson(json, ".operator"), (address));
        treasury = abi.decode(vm.parseJson(json, ".treasury"), (address));

        // Setup protocol operator role
        vm.startPrank(treasury);
        bytes32 PROTOCOL_OPERATOR = keccak256("PROTOCOL_OPERATOR");
        AccessHub(contracts.accessHub).grantRole(PROTOCOL_OPERATOR, protocolOperator);
        vm.stopPrank();

        // Mint initial test tokens to user
        // We mint double the INITIAL_AMOUNT because the test cases require two separate deposits:
        // 1. Initial deposit into VoteModule (INITIAL_AMOUNT)
        // 2. Additional amount for creating pending rewards in VoteModule by calling exit() in xShadow (INITIAL_AMOUNT)
        vm.startPrank(contracts.minter);
        IERC20Extended(contracts.shadow).mint(user, INITIAL_AMOUNT * 2);
        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(treasury, "treasury");
        vm.label(protocolOperator, "protocolOperator");
        vm.label(contracts.accessHub, "accessHub");
        vm.label(contracts.voter, "voter");
        vm.label(contracts.minter, "minter");
        vm.label(contracts.shadow, "shadow");
        vm.label(contracts.pairFactory, "pairFactory");
        vm.label(contracts.gaugeFactory, "gaugeFactory");
        vm.label(contracts.launcherPlugin, "launcherPlugin");
        vm.label(contracts.feeRecipientFactory, "feeRecipientFactory");
        vm.label(contracts.feeDistributorFactory, "feeDistributorFactory");
        vm.label(contracts.router, "router");
        vm.label(contracts.voteModule, "voteModule");
        vm.label(contracts.xShadow, "xShadow");
    }

    /// @notice Test rewards distribution for legacy gauge system
    function test_forkRewardsLegacyGauge() public {
        // Get relevant contract addresses
        address voter = contracts.voter;
        address voteModule = contracts.voteModule;
        address xShadow = contracts.xShadow;
        address shadow = contracts.shadow;

        // Deploy mock tokens for testing
        vm.startPrank(user);
        MockERC20 token0 = new MockERC20();
        token0.initialize("Token0", "TK0", 18);
        MockERC20 token1 = new MockERC20();
        token1.initialize("Token1", "TK1", 18);
        vm.stopPrank();

        // Fund user with test tokens
        deal(address(token0), user, INITIAL_AMOUNT);
        deal(address(token1), user, INITIAL_AMOUNT);

        // Whitelist tokens in voter contract
        vm.startPrank(protocolOperator);
        address[] memory tokens = new address[](3);
        bool[] memory whitelisted = new bool[](3);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(xShadow);
        whitelisted[0] = true;
        whitelisted[1] = true;
        whitelisted[2] = true;
        AccessHub(contracts.accessHub).governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();

        // Create liquidity pool and gauge
        vm.startPrank(user);
        address testPool = IPairFactory(contracts.pairFactory).createPair(address(token0), address(token1), false);
        IVoter(voter).createGauge(testPool);
        address gauge = IVoter(voter).gaugeForPool(testPool);
        vm.stopPrank();

        // Configure gauge rewards
        vm.startPrank(protocolOperator);
        address[] memory pools = new address[](1);
        address[] memory rewards = new address[](1);
        bool[] memory addReward = new bool[](1);
        pools[0] = testPool;
        rewards[0] = address(xShadow);
        addReward[0] = true;
        AccessHub(contracts.accessHub).augmentGaugeRewardsForPair(pools, rewards, addReward);
        vm.stopPrank();

        // Initialize emissions with 50% multiplier
        vm.startPrank(protocolOperator);
        Minter(contracts.minter).kickoff(shadow, voter, INITIAL_AMOUNT, 5000, xShadow);
        Minter(contracts.minter).startEmissions();
        vm.stopPrank();

        // User converts emissions tokens to xShadow
        vm.startPrank(user);
        IERC20(shadow).approve(xShadow, INITIAL_AMOUNT);
        IXShadow(xShadow).convertEmissionsToken(INITIAL_AMOUNT);

        // Trigger initial emission period
        Minter(contracts.minter).updatePeriod();

        // User deposits xShadow into vote module
        uint256 xShadowBalance = IERC20(xShadow).balanceOf(user);
        IERC20(xShadow).approve(voteModule, xShadowBalance);
        IVoteModule(voteModule).deposit(xShadowBalance);

        // User votes for test pool with 100% weight
        pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = testPool;
        weights[0] = 10000; // 100% weight
        IVoter(voter).vote(user, pools, weights);

        // Add liquidity to pool and stake LP tokens
        MockERC20(token0).transfer(testPool, INITIAL_AMOUNT);
        MockERC20(token1).transfer(testPool, INITIAL_AMOUNT);
        IPair(testPool).mint(user);

        uint256 lpBalance = IERC20(testPool).balanceOf(user);
        IERC20(testPool).approve(gauge, lpBalance);
        IGauge(gauge).deposit(lpBalance);
        vm.stopPrank();

        // Simulate time passing (7 days)
        vm.warp(block.timestamp + 7 days);

        // Distribute rewards through voter
        vm.prank(voter);
        IVoter(voter).distribute(gauge);

        // Additional time passage (8 days)
        vm.warp(block.timestamp + 8 days);

        // Claim rewards from gauge
        vm.startPrank(user);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = xShadow;
        IGauge(gauge).getReward(user, rewardTokens);
        IGauge(gauge).getReward(user, rewardTokens);
        vm.stopPrank();

        // Verify rewards distribution
        uint256 finalXShadowBalance = IERC20(xShadow).balanceOf(user);
        uint256 expectedRewards = Minter(contracts.minter).weeklyEmissions();

        // Assert rewards are within acceptable range
        assertApproxEqAbs(
            finalXShadowBalance, expectedRewards, 200, "User should have received full rewards for 2 weeks"
        );
    }

    /// @notice Test vote module and xShadow rewards functionality
    function test_forkVoteModuleAndXShadow() public {
        // Get contract references
        address voter = contracts.voter;
        address voteModule = contracts.voteModule;
        address xShadow = contracts.xShadow;
        address shadow = contracts.shadow;

        // Whitelist xShadow token
        vm.startPrank(protocolOperator);
        address[] memory tokens = new address[](1);
        bool[] memory whitelisted = new bool[](1);
        tokens[0] = address(xShadow);
        whitelisted[0] = true;
        AccessHub(contracts.accessHub).governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();

        // Initialize emissions
        vm.startPrank(protocolOperator);
        Minter(contracts.minter).kickoff(shadow, voter, INITIAL_AMOUNT, 5000, xShadow);
        Minter(contracts.minter).startEmissions();
        vm.stopPrank();

        // User converts emissions tokens to xShadow
        vm.startPrank(user);
        IERC20(shadow).approve(xShadow, INITIAL_AMOUNT);
        IXShadow(xShadow).convertEmissionsToken(INITIAL_AMOUNT);
        uint256 initialXShadowBalance = IERC20(xShadow).balanceOf(user);
        assertGt(initialXShadowBalance, 0, "Should have received xShadow tokens");

        // Deposit xShadow into vote module
        IERC20(xShadow).approve(voteModule, initialXShadowBalance);
        IVoteModule(voteModule).deposit(initialXShadowBalance);

        // Verify deposit was successful
        uint256 voteModuleBalance = IVoteModule(voteModule).balanceOf(user);
        assertEq(voteModuleBalance, initialXShadowBalance, "VoteModule balance should match deposit");
        assertEq(IERC20(xShadow).balanceOf(user), 0, "User xShadow balance should be 0 after deposit");

        // Create additional xShadow pending rewards
        uint256 vestAmount = INITIAL_AMOUNT;
        vm.startPrank(user);
        IERC20(shadow).approve(xShadow, vestAmount);
        IXShadow(xShadow).convertEmissionsToken(vestAmount);

        // Exit position to generate rewards
        IXShadow(xShadow).exit(initialXShadowBalance);

        // Advance time and update rewards
        vm.warp(block.timestamp + 7 days);
        Minter(contracts.minter).updatePeriod();

        // Advance time to capture full rewards as rewards are streamed over 30 minutes
        vm.warp(block.timestamp + 7 days + 30 minutes);

        // Claim rewards
        IVoteModule(voteModule).getReward();

        // Verify final token balances
        assertApproxEqAbs(
            IERC20(xShadow).balanceOf(user),
            initialXShadowBalance / 2,
            2000,
            "Should have received half xShadow tokens +- 2000 wei in rewards"
        );
        assertEq(
            IERC20(shadow).balanceOf(user),
            initialXShadowBalance / 2,
            "Should have received half Shadow tokens back"
        );
    }
}
