// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {Voter} from "../../contracts/Voter.sol";
import {IGauge} from "../../contracts/interfaces/IGauge.sol";
import {IGaugeFactory} from "../../contracts/interfaces/IGaugeFactory.sol";
import {IFeeDistributor} from "../../contracts/interfaces/IFeeDistributor.sol";
import {IFeeDistributorFactory} from "../../contracts/interfaces/IFeeDistributorFactory.sol";
import {IVoter} from "../../contracts/interfaces/IVoter.sol";
import {XShadow} from "../../contracts/xShadow/XShadow.sol";
import {VoteModule} from "../../contracts/VoteModule.sol";
import {PairFactory} from "../../contracts/factories/PairFactory.sol";
import {FeeRecipientFactory} from "../../contracts/factories/FeeRecipientFactory.sol";
import {GaugeFactory} from "../../contracts/factories/GaugeFactory.sol";
import {FeeDistributorFactory} from "../../contracts/factories/FeeDistributorFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPair} from "../../contracts/interfaces/IPair.sol";
import {IFeeRecipientFactory} from "../../contracts/interfaces/IFeeRecipientFactory.sol";
import {IRamsesV3Factory} from "../../contracts/CL/core/interfaces/IRamsesV3Factory.sol";
import {RamsesV3Pool} from "../../contracts/CL/core/RamsesV3Pool.sol";
import {IFeeCollector} from "../../contracts/CL/gauge/interfaces/IFeeCollector.sol";
import {IClGaugeFactory} from "../../contracts/CL/gauge/interfaces/IClGaugeFactory.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {IGaugeV3} from "../../contracts/CL/gauge/interfaces/IGaugeV3.sol";
import {IAccessHub} from "../../contracts/interfaces/IAccessHub.sol";
import {console} from "forge-std/console.sol";

contract VoterTest is TestBase {
    Voter public voter;
    address public constant CL_FACTORY = address(0xabc);
    address public constant CL_GAUGE_FACTORY = address(0xdef);
    address public constant NFP_MANAGER = address(0xbcd);
    address public constant PROTOCOL_OPERATOR = address(0x123);
    address public constant FEE_COLLECTOR = address(0x123);
    XShadow public xShadow;
    VoteModule public voteModule;
    PairFactory public pairFactory;
    GaugeFactory public gaugeFactory;
    FeeDistributorFactory public feeDistributorFactory;

    event EmissionsRatio(address indexed setter, uint256 oldRatio, uint256 newRatio);
    event Voted(address indexed voter, uint256 weight, address indexed pool);
    event Abstained(address indexed voter, uint256 weight);
    event Poke(address indexed user);
    event DistributeReward(address indexed distributor, address indexed gauge, uint256 amount);
    event Whitelisted(address indexed whitelister, address indexed token);
    event WhitelistRevoked(address indexed revoker, address indexed token, bool killed);
    event GaugeCreated(address indexed gauge, address indexed creator, address feeDistributor, address pool);
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event NewGovernor(address indexed setter, address indexed governor);
    event MainTickSpacingChanged(address token0, address token1, int24 tickSpacing);
    event NotifyReward(address indexed from, address indexed rewardToken, uint256 amount);
    event CustomGaugeCreated(address indexed gauge, address indexed creator, address pool);

    function setUp() public override {
        vm.warp(100 weeks);
        super.setUp();

        voter = new Voter(address(accessHub));

        voteModule = new VoteModule();

        xShadow = new XShadow(
            address(shadow),
            address(voter),
            address(TREASURY),
            address(accessHub),
            address(voteModule),
            address(mockMinter)
        );
        feeRecipientFactory = new FeeRecipientFactory(TREASURY, address(voter), address(accessHub));
        pairFactory =
            new PairFactory(address(voter), address(TREASURY), address(accessHub), address(feeRecipientFactory));
        gaugeFactory = new GaugeFactory();
        feeDistributorFactory = new FeeDistributorFactory();
        voteModule.initialize(address(xShadow), address(voter), address(accessHub));

        vm.startPrank(address(TIMELOCK));

        // Create InitParams struct
        IAccessHub.InitParams memory params = IAccessHub.InitParams({
            timelock: TIMELOCK,
            treasury: TREASURY,
            voter: address(voter),
            minter: address(mockMinter),
            launcherPlugin: address(mockLauncherPlugin),
            xShadow: address(xShadow),
            x33: address(mockX33),
            ramsesV3PoolFactory: address(CL_FACTORY),
            poolFactory: address(pairFactory),
            clGaugeFactory: CL_GAUGE_FACTORY,
            gaugeFactory: address(gaugeFactory),
            feeRecipientFactory: address(feeRecipientFactory),
            feeDistributorFactory: address(feeDistributorFactory),
            feeCollector: address(mockFeeCollector),
            voteModule: address(voteModule)
        });

        accessHub.initialize(params);

        accessHub.initializeVoter(
            address(shadow),
            address(pairFactory),
            address(gaugeFactory),
            address(feeDistributorFactory),
            address(mockMinter),
            TREASURY,
            address(xShadow),
            CL_FACTORY,
            CL_GAUGE_FACTORY,
            NFP_MANAGER,
            address(feeRecipientFactory),
            address(voteModule),
            address(mockLauncherPlugin)
        );
        accessHub.grantRole(accessHub.PROTOCOL_OPERATOR(), PROTOCOL_OPERATOR);

        vm.startPrank(address(PROTOCOL_OPERATOR));
        address[] memory tokens = new address[](5);
        tokens[0] = address(shadow);
        tokens[1] = address(token0);
        tokens[2] = address(token1);
        tokens[3] = address(xShadow);
        tokens[4] = address(token6Decimals);
        bool[] memory whitelisted = new bool[](5);
        whitelisted[0] = true;
        whitelisted[1] = true;
        whitelisted[2] = true;
        whitelisted[3] = true;
        whitelisted[4] = true;
        accessHub.governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();
    }

    function test_initializationSetsCorrectValues() public view {
        // Test that all initialization values are set correctly
        assertEq(voter.legacyFactory(), address(pairFactory), "Legacy factory address mismatch");
        assertEq(voter.shadow(), address(shadow), "Emissions token address mismatch");
        assertEq(voter.gaugeFactory(), address(gaugeFactory), "Gauge factory address mismatch");
        assertEq(
            voter.feeDistributorFactory(), address(feeDistributorFactory), "Fee distributor factory address mismatch"
        );
        assertEq(voter.minter(), address(mockMinter), "Minter address mismatch");
        assertEq(voter.governor(), TREASURY, "Governor address mismatch");
        assertEq(voter.xShadow(), address(xShadow), "xShadow address mismatch");
        assertEq(voter.clFactory(), CL_FACTORY, "CL factory address mismatch");
        assertEq(voter.clGaugeFactory(), CL_GAUGE_FACTORY, "CL gauge factory address mismatch");
        assertEq(voter.nfpManager(), NFP_MANAGER, "NFP manager address mismatch");
        assertEq(voter.feeRecipientFactory(), address(feeRecipientFactory), "Fee recipient factory address mismatch");
        assertEq(voter.voteModule(), address(voteModule), "Vote module address mismatch");
        assertEq(voter.launcherPlugin(), address(mockLauncherPlugin), "Launcher plugin address mismatch");
        assertEq(voter.xRatio(), 1_000_000, "xRatio should be 100%"); // 100%
    }

    function test_setGlobalRatioRevertsWhenRatioExceedsBasis() public {
        // Step 1: Try to set ratio higher than BASIS
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("RATIO_TOO_HIGH(uint256)", 1_000_001));
        voter.setGlobalRatio(1_000_001);
    }

    function test_setGlobalRatioRevertsWhenCallerNotGovernance() public {
        // Step 1: Try to set ratio from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.setGlobalRatio(500_000);
    }

    function test_voteRevertsWithMismatchedArrayLengths() public {
        // Step 1: Set up arrays with mismatched lengths
        address[] memory pools = new address[](2);
        uint256[] memory weights = new uint256[](1);

        // Step 2: Attempt to vote with mismatched arrays
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        voter.vote(alice, pools, weights);
    }

    function test_voteRevertsWithEmptyArrays() public {
        // Step 1: Set up empty arrays
        address[] memory pools = new address[](0);
        uint256[] memory weights = new uint256[](0);

        // Step 2: Attempt to vote with empty arrays
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        voter.vote(alice, pools, weights);
    }

    function test_resetRevertsWhenCallerNotAuthorized() public {
        // Step 1: Attempt reset from unauthorized account
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", bob));
        voter.reset(alice);
    }

    function test_whitelistTokenSucceeds() public {
        // Step 1: Set up test token
        address token = address(0x123);

        // Step 2: Whitelist token from authorized account
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, false);
        emit Whitelisted(address(accessHub), token);
        voter.whitelist(token);

        // Step 3: Verify token is whitelisted
        assertTrue(voter.isWhitelisted(token), "Token should be whitelisted");
    }

    function test_whitelistTokenFailsIfAlreadyWhitelisted() public {
        // Step 1: Setup test token
        address token = address(0x123);

        // Step 2: Whitelist token first time
        vm.startPrank(address(accessHub));
        voter.whitelist(token);

        // Step 3: Attempt to whitelist same token again
        vm.expectRevert(abi.encodeWithSignature("ALREADY_WHITELISTED(address)", token));
        voter.whitelist(token);
        vm.stopPrank();
    }

    function test_revokeWhitelist() public {
        // Step 1: Setup and whitelist token
        address token = address(0x123);
        vm.startPrank(address(accessHub));
        voter.whitelist(token);

        // Step 2: Revoke whitelist status
        vm.expectEmit(true, true, false, true);
        emit WhitelistRevoked(address(accessHub), token, true);
        voter.revokeWhitelist(token);
        vm.stopPrank();

        // Step 3: Verify token is no longer whitelisted
        assertFalse(voter.isWhitelisted(token), "Token should not be whitelisted");
    }

    function test_killGauge() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge from authorized account
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit GaugeKilled(gauge);
        voter.killGauge(gauge);

        // Step 3: Verify gauge is killed
        assertFalse(voter.isAlive(gauge), "Gauge should be killed");
    }

    function testFuzz_notifyRewardAmount(uint256 amount) public {
        // Step 1: Set up test amount
        vm.assume(amount > 0 && amount <= type(uint128).max);

        // Step 2: Fund mockMinter with tokens
        deal(address(shadow), address(mockMinter), amount);

        // Step 3: Approve and notify rewards
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);

        // Step 4: Verify event emission
        vm.expectEmit(true, true, false, true);
        emit NotifyReward(address(mockMinter), address(shadow), amount);
        voter.notifyRewardAmount(amount);
        vm.stopPrank();

        // Step 5: Verify reward accounting
        uint256 period = voter.getPeriod();
        assertEq(voter.totalRewardPerPeriod(period), amount, "Total reward amount mismatch");
        assertEq(shadow.balanceOf(address(voter)), amount, "Voter should have received all rewards");
    }

    function test_distribute() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        vm.stopPrank();

        // Step 2: Set up voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% weight to this pool

        // Step 3: Whitelist xShadow token and enable rewards for gauge
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));
        vm.stopPrank();

        // Step 4: Give alice xShadow tokens and set up voting power
        deal(address(xShadow), alice, 1000e18);

        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18); // Lock xShadow tokens in vote module to create voting power
        voter.vote(alice, pools, weights); // Cast vote for pool
        vm.stopPrank();

        // Step 5: Move to next epoch
        vm.warp(block.timestamp + 1 weeks);
        uint256 period = voter.getPeriod();

        // Step 6: Set up and notify rewards
        uint256 amount = 1000e18;
        deal(address(shadow), address(mockMinter), amount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);
        voter.notifyRewardAmount(amount);

        // Step 7: Move forward 2 weeks and distribute
        vm.warp(block.timestamp + 2 weeks);
        voter.distribute(gauge);

        // Step 8: Verify distribution was successful
        assertTrue(voter.gaugePeriodDistributed(gauge, period), "Gauge period should be distributed");
    }

    // @note This fails as of now because `dust` is being calculated incorrectly for all the tokens in the same variable instead per token
    function test_distribute50_50Ratio() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Set ratio to 50% (500,000 out of 1,000,000 basis points)
        vm.startPrank(address(accessHub));
        voter.setGlobalRatio(500_000);
        vm.stopPrank();

        // Step 3: Set up voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% weight to this pool

        // Step 4: Whitelist xShadow token and enable rewards for gauge
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));
        vm.stopPrank();

        // Step 5: Give alice xShadow tokens and set up voting power
        deal(address(xShadow), alice, 1000e18);

        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18); // Lock xShadow tokens in vote module to create voting power
        voter.vote(alice, pools, weights); // Cast vote for pool
        vm.stopPrank();

        // Step 6: Move to next epoch
        vm.warp(block.timestamp + 1 weeks);
        uint256 period = voter.getPeriod();

        // Step 7: Set up and notify rewards
        uint256 amount = 1000e18;
        deal(address(shadow), address(mockMinter), amount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);
        voter.notifyRewardAmount(amount);

        // Step 8: Move forward 2 weeks and distribute
        vm.warp(block.timestamp + 2 weeks);
        voter.distribute(gauge);

        // Step 9: Verify distribution was successful
        assertTrue(voter.gaugePeriodDistributed(gauge, period), "Gauge period should be distributed");
    }

    // @note This fails as of now because `dust` is being calculated incorrectly for all the tokens in the same variable instead per token
    function test_distributeForPeriod() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Set xRatio to 10% (100,000 out of 1,000,000 basis points)
        vm.startPrank(address(accessHub));
        voter.setGlobalRatio(100_000);
        vm.stopPrank();

        // Step 3: Set up voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% weight to this pool

        // Step 4: Whitelist xShadow token and enable rewards for gauge
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));
        vm.stopPrank();

        // Step 5: Give alice xShadow tokens and set up voting power
        deal(address(xShadow), alice, 1000e18);

        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18); // Lock xShadow tokens in vote module to create voting power
        voter.vote(alice, pools, weights); // Cast vote for pool

        // Step 6: Mint and deposit LP tokens to gauge to earn rewards
        deal(pool, alice, 1000e18);
        MockERC20(pool).approve(gauge, 1000e18);
        IGauge(gauge).deposit(1000e18);
        vm.stopPrank();

        // Step 7: Move to next epoch
        vm.warp(block.timestamp + 1 weeks);
        uint256 period = voter.getPeriod();

        // Step 8: Set up and notify rewards
        uint256 amount = 1000e18;
        deal(address(shadow), address(mockMinter), amount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);
        voter.notifyRewardAmount(amount);
        vm.stopPrank();

        // Step 9: Move forward 2 weeks and distribute for specific period
        vm.warp(block.timestamp + 2 weeks);
        voter.distributeForPeriod(gauge, period);

        // Step 10: Verify distribution was successful
        assertTrue(voter.gaugePeriodDistributed(gauge, period), "Gauge period should be distributed");
        assertEq(voter.totalRewardPerPeriod(period), amount, "Total reward amount mismatch");

        // Step 11: Move forward and check rewards distribution
        vm.warp(block.timestamp + 3 weeks);
        assertApproxEqAbs(
            IGauge(gauge).earned(address(shadow), alice),
            amount * 90 / 100,
            1000,
            "Alice's SHADOW rewards should match 90% of total"
        );
        assertApproxEqAbs(
            IGauge(gauge).earned(address(xShadow), alice),
            amount * 10 / 100,
            1000,
            "Alice's xSHADOW rewards should match 10% of total"
        );

        // Step 12: Claim rewards
        address[] memory gauges = new address[](1);
        gauges[0] = gauge;
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](2);
        tokens[0][0] = address(shadow);
        tokens[0][1] = address(xShadow);

        vm.startPrank(alice);
        voter.claimRewards(gauges, tokens);
        vm.stopPrank();

        // Step 13: Verify rewards were claimed correctly
        assertEq(IGauge(gauge).earned(address(shadow), alice), 0, "SHADOW rewards should be claimed");
        assertEq(IGauge(gauge).earned(address(xShadow), alice), 0, "xSHADOW rewards should be claimed");
        assertApproxEqAbs(
            shadow.balanceOf(alice), amount * 90 / 100, 1000, "Alice should have received SHADOW rewards"
        );
        assertApproxEqAbs(
            xShadow.balanceOf(alice), (amount * 10 / 100), 1000, "Alice should have received xSHADOW rewards"
        );
    }

    function test_voteForNewlyCreatedGaugeRecordsVotesInNextPeriod() public {
        // Step 1: Create initial pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting power for alice
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18); // Deposit xShadow to get voting power

        // Step 3: Setup vote parameters targeting the newly created gauge
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // Full weight to single pool

        // Step 4: Vote in same period as gauge creation
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Verify votes were recorded in next period
        uint256 currentPeriod = voter.getPeriod();
        uint256 nextPeriod = currentPeriod + 1;

        // Step 6: Check current period has no votes
        assertEq(voter.poolTotalVotesPerPeriod(pool, currentPeriod), 0, "Current period should have no votes");
        assertEq(
            voter.userVotingPowerPerPeriod(alice, currentPeriod), 0, "Current period should have no user voting power"
        );

        // Step 7: Check next period has the votes
        assertEq(voter.poolTotalVotesPerPeriod(pool, nextPeriod), 1000e18, "Next period should have votes");
        assertEq(
            voter.userVotingPowerPerPeriod(alice, nextPeriod), 1000e18, "Next period should have user voting power"
        );
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool),
            1000e18,
            "Next period should have user votes for pool"
        );
    }

    function test_killGaugeRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Try to kill gauge from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.killGauge(gauge);
    }

    function test_killGaugeRevertsWhenGaugeAlreadyDead() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge first time
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Try to kill again
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("GAUGE_INACTIVE(address)", gauge));
        voter.killGauge(gauge);
    }

    function test_killGaugeLegacyGaugeWithFeeSplitWhenNoGauge() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Set feeSplitWhenNoGauge to true
        vm.prank(address(accessHub));
        pairFactory.setFeeSplitWhenNoGauge(true);

        // Step 3: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 4: Verify fee recipient is set to governor
        assertEq(IPair(pool).feeRecipient(), voter.governor(), "Fee recipient should be governor");
    }

    function test_killGaugeLegacyGaugeWithoutFeeSplitWhenNoGauge() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Set feeSplitWhenNoGauge to false
        vm.prank(address(accessHub));
        pairFactory.setFeeSplitWhenNoGauge(false);

        // Step 3: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 4: Verify fee recipient is set to address(0)
        assertEq(IPair(pool).feeRecipient(), address(0), "Fee recipient should be address(0)");
    }

    function test_killGaugeHandlesUnclaimedRewards() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        vm.prank(address(mockMinter));
        voter.notifyRewardAmount(rewardAmount);

        // Step 6: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 7: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 8: Verify rewards were handled correctly
        assertEq(shadow.balanceOf(voter.governor()), rewardAmount, "Rewards should be sent to governor");
        assertEq(shadow.balanceOf(gauge), 0, "Gauge should have no emissions token");
        assertEq(xShadow.balanceOf(gauge), 0, "Gauge should have no xShadow");
    }

    function test_killGaugeUpdatesLastDistroToCurrentPeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge and verify event
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit GaugeKilled(gauge);
        voter.killGauge(gauge);

        // Step 3: Verify lastDistro is updated
        assertEq(voter.lastDistro(gauge), voter.getPeriod(), "Last distro should be current period");
    }

    function test_killGaugeVotesHandlesMultiplePeriodsOnlyIfPeriodsAreVoted() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's initial voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 weeks);

        // Step 4: Add rewards and votes for multiple periods
        uint256 currentTime = block.timestamp;
        uint256 rewardAmount = 1000e18;
        for (uint256 i = 0; i < 3; i++) {
            deal(address(shadow), address(mockMinter), rewardAmount);
            vm.prank(address(mockMinter));
            shadow.approve(address(voter), rewardAmount);
            vm.prank(address(mockMinter));
            voter.notifyRewardAmount(rewardAmount);

            vm.startPrank(alice);
            voter.vote(alice, pools, weights);
            vm.stopPrank();

            currentTime += 1 weeks;
            vm.warp(currentTime);
        }

        // Step 5: Record initial state and kill gauge
        uint256 expectedRewards = rewardAmount * 3;
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 6: Verify rewards were transferred correctly
        assertEq(shadow.balanceOf(voter.governor()) - governorBalanceBefore, expectedRewards);
    }

    function test_killGaugeHandlesZeroRewards() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Record initial state
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        // Step 3: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 4: Verify no rewards were transferred
        assertEq(shadow.balanceOf(voter.governor()), governorBalanceBefore);
    }

    function test_killGaugeFirstPeriodRewardsAreLost() public {
        // Step 1: Setup initial state with rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);

        // Step 2: Notify rewards first
        vm.prank(address(mockMinter));
        voter.notifyRewardAmount(rewardAmount);

        // Step 3: Create gauge after rewards are notified
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 4: Setup and cast vote for the pool
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = pool;
        weights[0] = 10000;

        vm.prank(alice);
        voter.vote(alice, pools, weights);

        // Step 5: Move to next period
        uint256 currentTime = block.timestamp;
        currentTime += 1 weeks;
        vm.warp(currentTime);

        // Step 6: Record initial state and kill gauge
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 7: Verify no rewards were sent to governor since they were lost in first period
        assertEq(shadow.balanceOf(voter.governor()) - governorBalanceBefore, 0);
    }

    function test_killGaugeNoVotesNoRewards() public {
        // Step 1: Setup initial state
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);

        // Step 2: Create gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 3: Notify rewards but don't vote
        vm.prank(address(mockMinter));
        voter.notifyRewardAmount(rewardAmount);

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Record initial state and kill gauge
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 6: Verify state after killing gauge
        assertEq(shadow.balanceOf(voter.governor()), governorBalanceBefore);
        assertEq(voter.lastDistro(gauge), voter.getPeriod());
        assertEq(shadow.balanceOf(address(voter)), rewardAmount);
    }

    function test_reviveGaugeRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge first
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Try to revive gauge from unauthorized account and verify revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.reviveGauge(gauge);
    }

    function test_reviveGaugeRevertsWhenGaugeAlreadyAlive() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Try to revive an already alive gauge and verify revert
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ACTIVE_GAUGE(address)", gauge));
        voter.reviveGauge(gauge);
    }

    function test_reviveGaugeLegacyGaugeSetsFeeRecipient() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge first
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Revive gauge
        vm.prank(address(accessHub));
        voter.reviveGauge(gauge);

        // Step 4: Verify fee recipient is set correctly
        address expectedFeeRecipient = feeRecipientFactory.feeRecipientForPair(pool);
        assertEq(IPair(pool).feeRecipient(), expectedFeeRecipient);
    }

    function test_reviveGaugeUpdatesLastDistroToCurrentPeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Move forward some periods
        vm.warp(block.timestamp + 4 weeks);

        // Step 4: Revive gauge
        vm.prank(address(accessHub));
        voter.reviveGauge(gauge);

        // Step 5: Verify lastDistro is set to current period
        assertEq(voter.lastDistro(gauge), voter.getPeriod());
    }

    function test_reviveGaugeEmitsGaugeRevivedEvent() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge first
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Revive gauge and verify event emission
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit GaugeRevived(gauge);
        voter.reviveGauge(gauge);
    }

    function test_reviveGaugeSetsIsAliveToTrue() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge first
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Verify gauge is dead
        assertFalse(voter.isAlive(gauge));

        // Step 4: Revive gauge
        vm.prank(address(accessHub));
        voter.reviveGauge(gauge);

        // Step 5: Verify gauge is alive
        assertTrue(voter.isAlive(gauge));
    }

    function test_reviveGaugeAllowsVotingAfterRevival() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Revive gauge
        vm.prank(address(accessHub));
        voter.reviveGauge(gauge);

        // Step 4: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 5: Give alice voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 6: Verify voting works after revival
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 7: Check that votes were recorded
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool), 1000e18);
    }

    function test_reviveGaugeAllowsDistributionAfterRevival() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Whitelist tokens
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));
        voter.whitelistGaugeRewards(gauge, address(shadow));
        vm.stopPrank();

        // Step 3: Kill gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 4: Revive gauge
        vm.prank(address(accessHub));
        voter.reviveGauge(gauge);

        // Step 5: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 6: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 7: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 8: Setup and notify rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        uint256 currentPeriod = voter.getPeriod();

        // Step 9: Distribute rewards
        voter.distribute(gauge);

        // Step 10: Verify distribution worked
        assertTrue(voter.gaugePeriodDistributed(gauge, currentPeriod));
    }

    function test_stuckEmissionsRecoveryRevertsForActiveGauge() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Try to recover from active gauge and verify revert
        uint256 period = voter.getPeriod();
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ACTIVE_GAUGE(address)", gauge));
        voter.stuckEmissionsRecovery(gauge, period);
    }

    function test_stuckEmissionsRecoveryNoopIfPeriodAlreadyDistributed() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill the gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        uint256 period = voter.getPeriod();

        // Step 3: Mark period as already distributed
        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        // Step 4: Record initial state and try to recover again
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        // Step 5: Verify no change in governor balance
        assertEq(
            shadow.balanceOf(voter.governor()),
            governorBalanceBefore,
            "Governor balance should not change for already distributed period"
        );
    }

    function test_stuckEmissionsRecoveryTransfersEmissionsToGovernor() public {
        // Step 1: Setup initial state with rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);

        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);

        // Step 2: Create and setup gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Move to next period and add rewards
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(address(mockMinter));
        voter.notifyRewardAmount(rewardAmount);

        // Step 6: Mock voter implementation to set gauge as not alive
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 7: Record initial state and recover stuck emissions
        uint256 period = voter.getPeriod();
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        // Step 8: Verify emissions transfer
        assertEq(
            shadow.balanceOf(voter.governor()) - governorBalanceBefore,
            rewardAmount,
            "Incorrect amount transferred to governor"
        );
    }

    function test_stuckEmissionsRecoveryMarksPeriodsAsDistributedIfClaimable() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup initial state with rewards
        uint256 rewardAmount = 3000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Move to next period and add rewards
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(address(mockMinter));
        voter.notifyRewardAmount(rewardAmount);

        // Step 6: Mock voter implementation to set gauge as not alive
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 7: Recover stuck emissions and verify period marked as distributed
        uint256 period = voter.getPeriod();
        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        assertTrue(voter.gaugePeriodDistributed(gauge, period), "Period should be marked as distributed");
    }

    function test_stuckEmissionsRecoveryDoesNotMarkPeriodDistributedIfNoRewards() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's voting power and vote (but no rewards)
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Mock voter implementation to set gauge as not alive
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 6: Recover stuck emissions and verify period not marked as distributed
        uint256 period = voter.getPeriod();
        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        assertFalse(
            voter.gaugePeriodDistributed(gauge, period), "Period should not be marked as distributed when no rewards"
        );
    }

    function test_stuckEmissionsRecoveryNoTransferForZeroEmissions() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Mock voter implementation to set gauge as not alive
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 3: Record initial state and recover stuck emissions
        uint256 period = voter.getPeriod();
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());

        vm.prank(address(accessHub));
        voter.stuckEmissionsRecovery(gauge, period);

        // Step 4: Verify no transfer occurred
        assertEq(
            shadow.balanceOf(voter.governor()),
            governorBalanceBefore,
            "Governor balance should remain unchanged"
        );
    }

    function test_stuckEmissionsRecoveryRevertsForNonGovernanceCaller() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Mock voter implementation to set gauge as not alive
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 3: Attempt recovery as non-governance and verify revert
        uint256 period = voter.getPeriod();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.stuckEmissionsRecovery(gauge, period);
    }

    function test_stuckEmissionsRecoveryHandlesMultiplePeriods() public {
        // Step 1: Setup initial state with rewards
        uint256 rewardAmount = 3000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.prank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);

        // Step 2: Create and setup gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        vm.stopPrank();

        // Step 5: Vote and notify rewards for multiple periods
        uint256 ts = block.timestamp;
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            voter.vote(alice, pools, weights);
            ts += 1 weeks;
            vm.warp(ts);
            vm.prank(address(mockMinter));
            voter.notifyRewardAmount(rewardAmount / 3);
        }

        // Step 6: Mock voter implementation to set gauge as not alive
        uint256 governorBalanceBefore = shadow.balanceOf(voter.governor());
        bytes memory code = address(new MockVoterWithSetAlive(TREASURY)).code;
        vm.etch(address(voter), code);
        MockVoterWithSetAlive(address(voter)).setAlive(gauge, false);

        // Step 7: Recover emissions for each period
        vm.startPrank(address(accessHub));
        for (uint256 i = 0; i < 3; i++) {
            voter.stuckEmissionsRecovery(gauge, 100 + i + 1);
        }
        vm.stopPrank();

        // Step 8: Verify total emissions recovered
        assertEq(
            shadow.balanceOf(voter.governor()) - governorBalanceBefore,
            rewardAmount,
            "Governor should receive all emissions from multiple periods"
        );
    }

    function test_voteRevertsWhenCallerNotAuthorizedDelegate() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Attempt unauthorized vote and verify revert
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", bob));
        voter.vote(alice, pools, weights);
    }

    function test_voteSucceedsWhenCallerIsAuthorizedDelegate() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: Setup bob as alice's delegate
        voteModule.delegate(bob);
        vm.stopPrank();

        // Step 5: Vote as delegate
        vm.prank(bob);
        voter.vote(alice, pools, weights);

        // Step 6: Verify votes were recorded correctly
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool),
            1000e18,
            "Votes should be recorded correctly for delegated vote"
        );
    }

    function test_voteRevertsWhenVotingForDeadGauge() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill the gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Setup vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Try to vote for dead gauge and verify revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VOTE_UNSUCCESSFUL()"));
        voter.vote(alice, pools, weights);
    }

    function test_voteRevertsWhenVotingWithZeroWeight() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup vote parameters with zero weight
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 0; // Zero weight

        // Step 3: Try to vote with zero weight and verify revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VOTE_UNSUCCESSFUL()"));
        voter.vote(alice, pools, weights);
    }

    function test_voteCorrectlyHandlesMultiplePools() public {
        // Step 1: Setup multiple pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Setup vote parameters for multiple pools
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60; // 60% weight
        weights[1] = 40; // 40% weight

        // Step 3: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: Vote for multiple pools
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Verify vote distribution
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool1),
            600e18,
            "Pool1 should receive 60% of voting power"
        );
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool2),
            400e18,
            "Pool2 should receive 40% of voting power"
        );
        assertEq(voter.totalVotesPerPeriod(nextPeriod), 1000e18, "Total votes should equal total voting power");
    }

    function test_voteCorrectlyUpdatesAfterMultipleVotes() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's initial voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: First vote
        voter.vote(alice, pools, weights);
        uint256 nextPeriod = voter.getPeriod() + 1;
        uint256 firstVoteAmount = voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool);

        // Step 5: Increase voting power
        deal(address(xShadow), alice, 2000e18);
        xShadow.approve(address(voteModule), 2000e18);
        voteModule.deposit(1000e18);

        // Step 6: Second vote with increased power
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 7: Verify votes were updated
        assertGt(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool),
            firstVoteAmount,
            "Vote amount should increase after second vote"
        );
    }

    function test_voteHandlesVotingPowerDecrease() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's initial voting power
        deal(address(xShadow), alice, 2000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 2000e18);
        voteModule.deposit(2000e18);

        // Step 4: First vote with higher power
        voter.vote(alice, pools, weights);
        uint256 nextPeriod = voter.getPeriod() + 1;
        uint256 firstVoteAmount = voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool);

        // Step 5: Decrease voting power
        voteModule.withdraw(1000e18);

        // Step 6: Vote again with lower power
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 7: Verify votes were decreased
        assertLt(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool),
            firstVoteAmount,
            "Vote amount should decrease after voting power reduction"
        );
    }

    function test_voteLegacyGauge() public {
        // Step 1: Create Legacy Gauge
        address legacyPool = pairFactory.createPair(address(token0), address(token1), false);
        address legacyGauge = voter.createGauge(legacyPool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = legacyPool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% to legacy

        // Step 3: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: Vote for legacy gauge
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Verify vote distribution
        uint256 nextPeriod = voter.getPeriod() + 1;

        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, legacyPool),
            1000e18,
            "User votes for legacy pool should be 1000e18"
        );
        assertEq(voter.totalVotesPerPeriod(nextPeriod), 1000e18, "Total votes should be 1000e18");
        assertTrue(voter.isLegacyGauge(legacyGauge), "Gauge should be marked as legacy");
    }

    function test_voteCLGauge() public {
        // Step 1: Setup mock CL gauge
        mockClGaugeCalls(address(token0), address(token6Decimals), 60);

        // Step 2: Create CL Gauge
        address clGauge = voter.createCLGauge(address(token0), address(token6Decimals), 60);
        address clPool = voter.poolForGauge(clGauge);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = clPool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% to CL gauge

        // Step 4: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 5: Vote for CL gauge
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 6: Verify vote distribution
        uint256 nextPeriod = voter.getPeriod() + 1;

        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, clPool),
            1000e18,
            "User votes for CL pool should be 1000e18"
        );
        assertEq(voter.totalVotesPerPeriod(nextPeriod), 1000e18, "Total votes should be 1000e18");
        assertTrue(voter.isClGauge(clGauge), "Gauge should be marked as CL gauge");
    }

    function test_voteAllGaugeTypesExceptArbitrary() public {
        // Step 1: Create Legacy Gauge
        address legacyPool = pairFactory.createPair(address(token0), address(token1), false);
        address legacyGauge = voter.createGauge(legacyPool);

        // Step 2: Setup and create CL Gauge
        mockClGaugeCalls(address(token0), address(token6Decimals), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token6Decimals), 60);
        address clPool = voter.poolForGauge(clGauge);

        // Step 3: Setup voting parameters with different weights
        address[] memory pools = new address[](2);
        pools[0] = legacyPool;
        pools[1] = clPool;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 60; // 60% to legacy
        weights[1] = 40; // 40% to CL

        // Step 4: Setup alice's voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 5: Vote for both gauge types
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 6: Verify vote distribution
        uint256 nextPeriod = voter.getPeriod() + 1;

        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, legacyPool),
            600e18, // 60% of 1000e18
            "Legacy gauge vote amount should be 600e18"
        );
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, clPool),
            400e18, // 40% of 1000e18
            "CL gauge vote amount should be 400e18"
        );

        // Step 7: Verify total votes and gauge types
        assertEq(voter.totalVotesPerPeriod(nextPeriod), 1000e18, "Total votes should be 1000e18");
        assertTrue(voter.isLegacyGauge(legacyGauge), "Gauge should be marked as legacy");
        assertTrue(voter.isClGauge(clGauge), "Gauge should be marked as CL gauge");
    }

    function test_setMainTickSpacingRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup test parameters
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;

        // Step 2: Try to set main tick spacing from unauthorized account and verify revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);
    }

    function test_setMainTickSpacingRevertsWhenGaugeDoesNotExist() public {
        // Step 1: Setup test parameters
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;

        // Step 2: Try to set main tick spacing for non-existent gauge and verify revert
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NO_GAUGE()"));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);
    }

    function test_setMainTickSpacingSuccessfullyUpdatesMainTickSpacing() public {
        // Step 1: Setup tokens and create CL gauge
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;
        mockClGaugeCalls(tokenA, tokenB, tickSpacing);
        voter.createCLGauge(tokenA, tokenB, tickSpacing);

        // Step 2: Set main tick spacing
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);

        // Step 3: Verify main tick spacing was set correctly
        assertEq(voter.mainTickSpacingForPair(tokenA, tokenB), tickSpacing, "Main tick spacing should match input");
    }

    function test_setMainTickSpacingRedirectsVotesAndFees() public {
        // Step 1: Setup tokens
        address tokenA = address(token0);
        address tokenB = address(token1);

        // Step 2: Create gauges with different tick spacings
        vm.startPrank(address(TREASURY));
        int24 tickSpacing1 = 60;
        int24 tickSpacing2 = 200;
        mockClGaugeCalls(tokenA, tokenB, tickSpacing1);
        address gauge1 = voter.createCLGauge(tokenA, tokenB, tickSpacing1);
        mockClGaugeCalls(tokenA, tokenB, tickSpacing2);
        address gauge2 = voter.createCLGauge(tokenA, tokenB, tickSpacing2);
        vm.stopPrank();
        address pool1 = voter.poolForGauge(gauge1);
        address pool2 = voter.poolForGauge(gauge2);

        // Step 3: Set main tick spacing to tickSpacing1
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing1);

        // Step 4: Verify redirections
        assertEq(voter.poolRedirect(pool2), pool1, "Pool2 should redirect to Pool1");
        assertEq(
            voter.feeDistributorForGauge(gauge2),
            voter.feeDistributorForGauge(gauge1),
            "Gauge2 should use Gauge1's fee distributor"
        );
    }

    function test_setMainTickSpacingKillsNonMainGauges() public {
        // Step 1: Setup tokens
        address tokenA = address(token0);
        address tokenB = address(token1);

        // Step 2: Create gauges with different tick spacings
        vm.startPrank(address(TREASURY));
        int24 tickSpacing1 = 60;
        int24 tickSpacing2 = 200;
        mockClGaugeCalls(tokenA, tokenB, tickSpacing1);
        address gauge1 = voter.createCLGauge(tokenA, tokenB, tickSpacing1);
        mockClGaugeCalls(tokenA, tokenB, tickSpacing2);
        address gauge2 = voter.createCLGauge(tokenA, tokenB, tickSpacing2);
        vm.stopPrank();

        // Step 3: Set main tick spacing to tickSpacing1
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing1);

        // Step 4: Verify gauge statuses
        assertTrue(voter.isAlive(gauge1), "Main gauge should be alive");
        assertFalse(voter.isAlive(gauge2), "Non-main gauge should be killed");
    }

    function test_setMainTickSpacingRevivesMainGaugeIfDead() public {
        // Step 1: Setup tokens and parameters
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;

        // Step 2: Create gauge and kill it
        mockClGaugeCalls(tokenA, tokenB, tickSpacing);
        address gauge = voter.createCLGauge(tokenA, tokenB, tickSpacing);
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Verify gauge is dead
        assertFalse(voter.isAlive(gauge), "Gauge should be dead before test");

        // Step 4: Set as main tick spacing
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);

        // Step 5: Verify gauge was revived
        assertTrue(voter.isAlive(gauge), "Main gauge should be revived");
    }

    function test_setMainTickSpacingHandlesMultipleTickSpacings() public {
        // Step 1: Setup tokens
        address tokenA = address(token0);
        address tokenB = address(token1);

        // Step 2: Create multiple gauges with different tick spacings
        int24[] memory tickSpacings = new int24[](3);
        tickSpacings[0] = 60;
        tickSpacings[1] = 200;
        tickSpacings[2] = 500;

        address[] memory gauges = new address[](3);
        address[] memory pools = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            mockClGaugeCalls(tokenA, tokenB, tickSpacings[i]);
            vm.prank(address(TREASURY));
            gauges[i] = voter.createCLGauge(tokenA, tokenB, tickSpacings[i]);
            pools[i] = voter.poolForGauge(gauges[i]);
        }

        // Step 3: Set main tick spacing to middle value
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacings[1]);

        // Step 4: Verify all redirections and statuses
        for (uint256 i = 0; i < 3; i++) {
            if (i == 1) {
                // Main gauge
                assertTrue(voter.isAlive(gauges[i]), "Main gauge should be alive");
                assertEq(voter.poolRedirect(pools[i]), pools[i], "Main pool should not redirect");
            } else {
                // Non-main gauges
                assertFalse(voter.isAlive(gauges[i]), "Non-main gauges should be killed");
                assertEq(voter.poolRedirect(pools[i]), pools[1], "Non-main pools should redirect to main pool");
                assertEq(
                    voter.feeDistributorForGauge(gauges[i]),
                    voter.feeDistributorForGauge(gauges[1]),
                    "Non-main gauges should use main gauge's fee distributor"
                );
            }
        }
    }

    function test_setMainTickSpacingMaintainsCorrectTokenOrder() public {
        // Step 1: Setup tokens
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;

        // Step 2: Create gauge with tokens in one order
        mockClGaugeCalls(tokenA, tokenB, tickSpacing);
        voter.createCLGauge(tokenA, tokenB, tickSpacing);

        // Step 3: Set main tick spacing with tokens in reverse order
        vm.prank(address(accessHub));
        voter.setMainTickSpacing(tokenB, tokenA, tickSpacing);

        // Step 4: Verify main tick spacing was set correctly regardless of token order
        assertEq(
            voter.mainTickSpacingForPair(tokenA, tokenB),
            tickSpacing,
            "Main tick spacing incorrect for tokenA,tokenB order"
        );
        assertEq(
            voter.mainTickSpacingForPair(tokenB, tokenA),
            tickSpacing,
            "Main tick spacing incorrect for tokenB,tokenA order"
        );
    }

    // @note This fails as of now because the setMainTickSpacing function is not emitting the event
    function test_setMainTickSpacingEmitsMainTickSpacingChangedEvent() public {
        // Step 1: Setup tokens
        address tokenA = address(token0);
        address tokenB = address(token1);
        int24 tickSpacing = 60;

        // Step 2: Create gauge
        mockClGaugeCalls(tokenA, tokenB, tickSpacing);
        voter.createCLGauge(tokenA, tokenB, tickSpacing);

        // Step 3: Get sorted tokens for event verification
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // Step 4: Set main tick spacing and verify event
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, true);
        emit MainTickSpacingChanged(token0, token1, tickSpacing);
        voter.setMainTickSpacing(tokenA, tokenB, tickSpacing);
    }

    function test_distributeHandlesZeroClaimableAmount() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Distribute with no votes or rewards set up
        voter.distribute(gauge);

        // Step 3: Verify no distribution occurred
        uint256 period = voter.getPeriod();
        assertFalse(voter.gaugePeriodDistributed(gauge, period), "Period should not be marked as distributed");
    }

    function test_distributeSkipsDeadGauge() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Kill the gauge
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 3: Try to distribute
        voter.distribute(gauge);

        // Step 4: Verify no distribution occurred
        uint256 period = voter.getPeriod();
        assertFalse(
            voter.gaugePeriodDistributed(gauge, period), "Dead gauge period should not be marked as distributed"
        );
    }

    function test_distributeHandlesMultiplePeriods() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 ts = block.timestamp;
        // Step 3: Add rewards for multiple periods
        uint256 rewardAmount = 1000e18;
        uint256 depositAmount = 10e18;
        for (uint256 i = 1; i <= 3; i++) {
            // Step 3a: Give alice voting power
            deal(address(xShadow), alice, depositAmount);
            vm.startPrank(alice);
            xShadow.approve(address(voteModule), depositAmount);
            voteModule.deposit(depositAmount);
            voter.vote(alice, pools, weights);
            vm.stopPrank();

            // Step 3b: Move to next period and add rewards
            ts += 1 weeks;
            vm.warp(ts);
            deal(address(shadow), address(mockMinter), rewardAmount * i); // I do * i because of the `left` calculation
            vm.startPrank(address(mockMinter));
            shadow.approve(address(voter), rewardAmount * i);
            voter.notifyRewardAmount(rewardAmount * i);
            vm.stopPrank();
        }

        // Step 4: Move forward one more period
        vm.warp(ts + 1 weeks);

        // Step 5: Distribute rewards
        voter.distribute(gauge);

        // Step 6: Verify all periods were distributed
        for (uint256 i = voter.getPeriod() - 3; i < voter.getPeriod(); i++) {
            assertTrue(
                voter.gaugePeriodDistributed(gauge, i),
                string.concat("Gauge should be distributed for period ", vm.toString(i))
            );
        }

        // Step 7: Verify rewards were distributed correctly
        assertEq(
            shadow.balanceOf(gauge),
            0, // Everything was converted to xShadow
            "Incorrect emissions token balance"
        );
        assertApproxEqAbs(
            xShadow.balanceOf(gauge),
            rewardAmount * 6, // 3 periods worth, it's 6 because rewardAmount is multiplied by i and i is 1, 2, 3 so(1+2+3)= 6 * rewardAmount
            1e9, // Allow small rounding difference
            "Incorrect xShadow balance"
        );
    }

    function test_distributeMultiplePeriodsDoesNotDistributeIfLeftIsLessThanClaimable() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        uint256 ts = block.timestamp;
        // Step 3: Add rewards for multiple periods
        uint256 rewardAmount = 1000e18;
        uint256 depositAmount = 10e18;
        for (uint256 i = 1; i <= 3; i++) {
            // Step 3a: Give alice voting power
            deal(address(xShadow), alice, depositAmount);
            vm.startPrank(alice);
            xShadow.approve(address(voteModule), depositAmount);
            voteModule.deposit(depositAmount);
            voter.vote(alice, pools, weights);
            vm.stopPrank();

            // Step 3b: Move to next period and add rewards
            ts += 1 weeks;
            vm.warp(ts);
            deal(address(shadow), address(mockMinter), rewardAmount); // I do * i because of the `left` calculation
            vm.startPrank(address(mockMinter));
            shadow.approve(address(voter), rewardAmount);
            voter.notifyRewardAmount(rewardAmount);
            vm.stopPrank();
        }

        // Step 4: Move forward one more period
        vm.warp(ts + 1 weeks);

        // Step 5: Distribute rewards
        voter.distribute(gauge);

        // Step 6: Verify distribution status for each period
        assertTrue(voter.gaugePeriodDistributed(gauge, 101), "Gauge should be distributed for period 101");
        assertTrue(voter.gaugePeriodDistributed(gauge, 102), "Gauge should be distributed for period 102");
        assertFalse(voter.gaugePeriodDistributed(gauge, 103), "Gauge should not be distributed for period 103");

        // Step 7: Verify rewards were distributed correctly
        assertEq(
            shadow.balanceOf(address(voter)),
            rewardAmount, // Last period was not distributed
            "One round of emissions was not distributed"
        );
        assertApproxEqAbs(
            xShadow.balanceOf(gauge),
            rewardAmount * 2, // 2 periods worth, last period was not distributed
            1e9, // Allow small rounding difference
            "Two rounds of emissions was not converted to xShadow and distributed"
        );
    }

    function test_distributeHandles100PercentXShadowRatio() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));

        // Step 2: Set xRatio to 100%
        vm.prank(address(accessHub));
        voter.setGlobalRatio(1_000_000); // 100%

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Step 6: Distribute rewards
        voter.distribute(gauge);

        // Step 7: Verify distribution
        uint256 period = voter.getPeriod();
        assertTrue(voter.gaugePeriodDistributed(gauge, period), "Gauge should be distributed for period");
        assertEq(xShadow.balanceOf(gauge), rewardAmount, "XShadow balance should be correct");
        assertEq(shadow.balanceOf(gauge), 0, "Emissions token balance should be 0");
    }

    function test_distributeForPeriodRevertsForFuturePeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);

        // Step 4: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Step 5: Try to distribute for future period
        uint256 futurePeriod = voter.getPeriod() + 10;
        voter.distributeForPeriod(gauge, futurePeriod);

        // Step 6: Verify no distribution occurred
        assertFalse(
            voter.gaugePeriodDistributed(gauge, futurePeriod), "Gauge should not be distributed for future period"
        );
        assertEq(shadow.balanceOf(address(voter)), rewardAmount, "Rewards should still be in voter");
        assertEq(shadow.balanceOf(gauge), 0, "No rewards should be in gauge");
    }

    function test_distributeForPeriodHandlesAlreadyDistributedPeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 4: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        uint256 period = voter.getPeriod();

        // Step 5: Distribute first time
        voter.distributeForPeriod(gauge, period);
        uint256 balanceAfterFirst = shadow.balanceOf(gauge);

        // Step 6: Try to distribute again
        voter.distributeForPeriod(gauge, period);
        uint256 balanceAfterSecond = shadow.balanceOf(gauge);

        // Step 7: Verify no additional tokens were distributed
        assertEq(balanceAfterFirst, balanceAfterSecond, "No additional tokens should be distributed");
    }

    function test_distributeAllHandlesEmptyGaugeList() public {
        // Step 1: Call distributeAll with empty gauge list
        voter.distributeAll();
        // No assertions needed - test passes if it doesn't revert
    }

    function test_distributeAllHandlesMultipleGauges() public {
        // Step 1: Create multiple pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        address gauge1 = voter.createGauge(pool1);
        address gauge2 = voter.createGauge(pool2);

        // Step 2: Whitelist gauge rewards
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge1, address(xShadow));
        voter.whitelistGaugeRewards(gauge2, address(xShadow));
        vm.stopPrank();

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = 50;

        // Step 4: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 6: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Step 7: Distribute to all gauges
        voter.distributeAll();

        // Step 8: Verify distribution
        uint256 period = voter.getPeriod();
        assertTrue(voter.gaugePeriodDistributed(gauge1, period), "Gauge1 should be distributed for period");
        assertTrue(voter.gaugePeriodDistributed(gauge2, period), "Gauge2 should be distributed for period");
    }

    function test_distributeHandlesDifferentWeights() public {
        // Step 1: Create two pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        address gauge1 = voter.createGauge(pool1);
        address gauge2 = voter.createGauge(pool2);
        vm.label(gauge1, "gauge1");
        vm.label(gauge2, "gauge2");

        // Step 2: Whitelist rewards for both gauges
        vm.startPrank(address(accessHub));
        voter.whitelistGaugeRewards(gauge1, address(xShadow));
        voter.whitelistGaugeRewards(gauge2, address(xShadow));
        vm.stopPrank();

        // Step 3: Setup voting parameters - 70/30 split
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 70; // 70% to pool1
        weights[1] = 30; // 30% to pool2

        // Step 4: Give alice and bob voting power and vote
        deal(address(xShadow), alice, 1000e18);
        deal(address(xShadow), bob, 1000e18);

        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        vm.startPrank(bob);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(bob, pools, weights);
        vm.stopPrank();

        // Step 5: Setup LP tokens and deposit into gauges at different ratios
        deal(address(pool1), alice, 1000e18);
        deal(address(pool1), bob, 500e18);
        deal(address(pool2), alice, 300e18);
        deal(address(pool2), bob, 700e18);

        // Alice deposits
        vm.startPrank(alice);
        IERC20(pool1).approve(gauge1, 1000e18);
        IERC20(pool2).approve(gauge2, 300e18);
        IGauge(gauge1).deposit(1000e18);
        IGauge(gauge2).deposit(300e18);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        IERC20(pool1).approve(gauge1, 500e18);
        IERC20(pool2).approve(gauge2, 700e18);
        IGauge(gauge1).deposit(500e18);
        IGauge(gauge2).deposit(700e18);
        vm.stopPrank();

        // Step 6: Move to next period and notify rewards
        vm.warp(block.timestamp + 1 weeks);
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();
        uint256 period = voter.getPeriod();

        // Step 7: Distribute to both gauges
        voter.distribute(gauge1);
        voter.distribute(gauge2);

        // Step 8: Move forward to allow rewards to accumulate
        vm.warp(block.timestamp + 2 weeks);

        // Step 9: Calculate and verify rewards distribution
        uint256 xShadowRewards = rewardAmount;

        // Gauge1 gets 70% of total rewards
        // Alice has 2/3 of gauge1 deposits, Bob has 1/3
        uint256 gauge1XShadow = xShadowRewards * 70 / 100;

        assertApproxEqAbs(
            IGauge(gauge1).earned(address(xShadow), alice),
            gauge1XShadow * 2 / 3,
            1000,
            "Alice's gauge1 xShadow rewards incorrect"
        );
        assertApproxEqAbs(
            IGauge(gauge1).earned(address(xShadow), bob),
            gauge1XShadow * 1 / 3,
            1000,
            "Bob's gauge1 xShadow rewards incorrect"
        );

        // Gauge2 gets 30% of total rewards
        // Alice has 30% of gauge2 deposits, Bob has 70%
        uint256 gauge2XShadow = xShadowRewards * 30 / 100;

        assertApproxEqAbs(
            IGauge(gauge2).earned(address(xShadow), alice),
            gauge2XShadow * 30 / 100,
            1000,
            "Alice's gauge2 xShadow rewards incorrect"
        );
        assertApproxEqAbs(
            IGauge(gauge2).earned(address(xShadow), bob),
            gauge2XShadow * 70 / 100,
            1000,
            "Bob's gauge2 xShadow rewards incorrect"
        );

        // Step 10: Verify periods were distributed
        assertTrue(voter.gaugePeriodDistributed(gauge1, period), "Gauge1 period should be distributed");
        assertTrue(voter.gaugePeriodDistributed(gauge2, period), "Gauge2 period should be distributed");
    }

    // Tests for batchDistributeByIndex()
    function test_batchDistributeByIndexHandlesInvalidRange() public {
        // Step 1: Test invalid ranges
        voter.batchDistributeByIndex(10, 5);
        voter.batchDistributeByIndex(0, 1000);
    }

    function test_batchDistributeByIndexDistributesCorrectRange() public {
        // Step 1: Create multiple pools and gauges
        address[] memory pools = new address[](5);
        address[] memory gauges = new address[](5);

        for (uint256 i = 0; i < 5; i++) {
            // Create new tokens for each iteration
            MockERC20 newToken0 = new MockERC20();
            MockERC20 newToken1 = new MockERC20();
            // Whitelist the new tokens
            vm.startPrank(address(accessHub));
            voter.whitelist(address(newToken0));
            voter.whitelist(address(newToken1));
            vm.stopPrank();
            pools[i] = pairFactory.createPair(address(newToken0), address(newToken1), false);
            gauges[i] = voter.createGauge(pools[i]);
            vm.prank(address(accessHub));
            voter.whitelistGaugeRewards(gauges[i], address(xShadow));
        }

        // Step 2: Setup voting parameters
        uint256[] memory weights = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            weights[i] = 20; // Equal weights
        }

        // Step 3: Setup alice's voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Add rewards
        uint256 rewardAmount = 1000e18;
        deal(address(shadow), address(mockMinter), rewardAmount);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), rewardAmount);
        voter.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Step 6: Distribute to subset of gauges
        voter.batchDistributeByIndex(1, 4); // Should distribute to gauges[1], gauges[2], gauges[3]

        // Step 7: Verify distribution
        uint256 period = voter.getPeriod();
        assertFalse(voter.gaugePeriodDistributed(gauges[0], period), "First gauge should not be distributed");
        assertTrue(voter.gaugePeriodDistributed(gauges[1], period), "Second gauge should be distributed");
        assertTrue(voter.gaugePeriodDistributed(gauges[2], period), "Third gauge should be distributed");
        assertTrue(voter.gaugePeriodDistributed(gauges[3], period), "Fourth gauge should be distributed");
        assertFalse(voter.gaugePeriodDistributed(gauges[4], period), "Last gauge should not be distributed");
    }

    function test_getVotesReturnsEmptyArraysForNoVotes() public view {
        // Step 1: Get votes for a user who hasn't voted
        (address[] memory votes, uint256[] memory weights) = voter.getVotes(alice, 1);

        // Step 2: Verify arrays are empty
        assertEq(votes.length, 0, "Votes array should be empty");
        assertEq(weights.length, 0, "Weights array should be empty");
    }

    function test_getVotesReturnsSingleVote() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory voteWeights = new uint256[](1);
        voteWeights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, voteWeights);
        vm.stopPrank();

        // Step 4: Get votes and verify
        uint256 nextPeriod = voter.getPeriod() + 1;
        (address[] memory votes, uint256[] memory weights) = voter.getVotes(alice, nextPeriod);

        // Step 5: Verify returned arrays
        assertEq(votes.length, 1, "Should return one vote");
        assertEq(weights.length, 1, "Should return one weight");
        assertEq(votes[0], pool, "Vote should be for the correct pool");
        assertEq(weights[0], 1000e18, "Weight should be full voting power");
    }

    function test_getVotesReturnsMultipleVotes() public {
        // Step 1: Create multiple pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory voteWeights = new uint256[](2);
        voteWeights[0] = 60; // 60% weight
        voteWeights[1] = 40; // 40% weight

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, voteWeights);
        vm.stopPrank();

        // Step 4: Get votes and verify
        uint256 nextPeriod = voter.getPeriod() + 1;
        (address[] memory votes, uint256[] memory weights) = voter.getVotes(alice, nextPeriod);

        // Step 5: Verify returned arrays
        assertEq(votes.length, 2, "Should return two votes");
        assertEq(weights.length, 2, "Should return two weights");
        assertEq(votes[0], pool1, "First vote should be for pool1");
        assertEq(votes[1], pool2, "Second vote should be for pool2");
        assertEq(weights[0], 600e18, "First weight should be 60% of voting power");
        assertEq(weights[1], 400e18, "Second weight should be 40% of voting power");
    }

    function test_getVotesReturnsCorrectValuesAfterReset() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory voteWeights = new uint256[](1);
        voteWeights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, voteWeights);

        // Step 4: Reset votes
        voter.reset(alice);
        vm.stopPrank();

        // Step 5: Get votes and verify
        uint256 nextPeriod = voter.getPeriod() + 1;
        (address[] memory votes, uint256[] memory weights) = voter.getVotes(alice, nextPeriod);

        // Step 6: Verify arrays are empty after reset
        assertEq(votes.length, 0, "Votes array should be empty after reset");
        assertEq(weights.length, 0, "Weights array should be empty after reset");
    }

    function test_getVotesReturnsCorrectValuesAcrossMultiplePeriods() public {
        // Step 1: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory voteWeights = new uint256[](1);
        voteWeights[0] = 100;

        // Step 3: Give alice initial voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: Vote in first period
        voter.vote(alice, pools, voteWeights);
        uint256 firstPeriod = voter.getPeriod() + 1;

        // Step 5: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 6: Vote with different amount in second period
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18); // Increase voting power
        voter.vote(alice, pools, voteWeights);
        uint256 secondPeriod = voter.getPeriod() + 1;
        vm.stopPrank();

        // Step 7: Check votes from first period
        (address[] memory votes1, uint256[] memory weights1) = voter.getVotes(alice, firstPeriod);
        assertEq(votes1.length, 1, "Should have one vote in first period");
        assertEq(votes1[0], pool, "Vote should be for correct pool in first period");
        assertEq(weights1[0], 1000e18, "Weight should be correct in first period");

        // Step 8: Check votes from second period
        (address[] memory votes2, uint256[] memory weights2) = voter.getVotes(alice, secondPeriod);
        assertEq(votes2.length, 1, "Should have one vote in second period");
        assertEq(votes2[0], pool, "Vote should be for correct pool in second period");
        assertEq(weights2[0], 2000e18, "Weight should be correct in second period");
    }

    function test_pokeRevertsWhenCallerNotAuthorized() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Try to poke for another user without being authorized
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", bob));
        voter.poke(alice);
    }

    function test_pokeSucceedsWhenCallerIsUser() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Verify poke succeeds when called by user
        vm.expectEmit(true, false, false, false);
        emit Poke(alice);
        voter.poke(alice);
        vm.stopPrank();
    }

    function test_pokeSucceedsWhenCallerIsDelegate() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Setup bob as delegate
        voteModule.delegate(bob);
        vm.stopPrank();

        // Step 5: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 6: Verify poke succeeds when called by delegate
        vm.prank(bob);
        vm.expectEmit(true, false, false, false);
        emit Poke(alice);
        voter.poke(alice);
    }

    function test_pokeSucceedsWhenCallerIsVoteModule() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Verify poke succeeds when called by vote module
        vm.prank(address(voteModule));
        vm.expectEmit(true, false, false, false);
        emit Poke(alice);
        voter.poke(alice);
    }

    function test_pokeTerminatesEarlyWhenNoLastVoted() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Poke without any prior votes
        vm.prank(alice);
        voter.poke(alice);

        // Step 3: Verify no changes occurred
        uint256 period = voter.getPeriod();
        assertEq(voter.lastVoted(alice), 0, "lastVoted should remain 0");
        assertEq(voter.userVotingPowerPerPeriod(alice, period + 1), 0, "No voting power should be recorded");
    }

    function test_pokeTerminatesEarlyWhenNoVotingPower() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters with zero voting power
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Vote with zero voting power
        vm.prank(alice);
        voter.vote(alice, pools, weights);

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Step 5: Poke and verify no changes
        vm.prank(alice);
        voter.poke(alice);

        uint256 period = voter.getPeriod();
        assertEq(voter.userVotingPowerPerPeriod(alice, period + 1), 0, "No voting power should be recorded");
    }

    function test_pokeResetsAndRecastsVotesInSamePeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice initial voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Record initial state
        uint256 period = voter.getPeriod();
        uint256 initialVotePower = voter.userVotingPowerPerPeriod(alice, period + 1);

        // Step 5: Increase voting power
        deal(address(xShadow), alice, 2000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 6: Poke in same period and verify votes were reset and recast
        voter.poke(alice);
        vm.stopPrank();

        assertGt(
            voter.userVotingPowerPerPeriod(alice, period + 1),
            initialVotePower,
            "Voting power should increase after poke"
        );
    }

    function test_pokeRecastsVotesInNewPeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Move to next period
        vm.warp(block.timestamp + 1 weeks);
        uint256 newPeriod = voter.getPeriod();

        // Step 5: Poke in new period
        voter.poke(alice);
        vm.stopPrank();

        // Step 6: Verify votes were recast in new period
        assertEq(voter.userVotingPowerPerPeriod(alice, newPeriod + 1), 1000e18, "Votes should be recast in new period");
    }

    function test_pokeMaintainsVoteWeightsAndPools() public {
        // Step 1: Setup multiple pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Setup initial votes with different weights
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60; // 60% weight
        weights[1] = 40; // 40% weight

        // Step 3: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Record initial vote distribution
        uint256 period = voter.getPeriod();
        uint256 initialVote1 = voter.userVotesForPoolPerPeriod(alice, period + 1, pool1);
        uint256 initialVote2 = voter.userVotesForPoolPerPeriod(alice, period + 1, pool2);

        // Step 5: Move to next period and poke
        vm.warp(block.timestamp + 1 weeks);
        voter.poke(alice);
        vm.stopPrank();

        // Step 6: Verify vote weights are maintained proportionally
        uint256 newPeriod = voter.getPeriod();
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, newPeriod + 1, pool1),
            initialVote1,
            "Pool1 vote weight should be maintained"
        );
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, newPeriod + 1, pool2),
            initialVote2,
            "Pool2 vote weight should be maintained"
        );
    }

    function test_pokeHandlesVotingPowerDecrease() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice initial voting power and vote
        deal(address(xShadow), alice, 2000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 2000e18);
        voteModule.deposit(2000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Record initial vote amount
        uint256 period = voter.getPeriod();
        uint256 initialVoteAmount = voter.userVotesForPoolPerPeriod(alice, period + 1, pool);

        // Step 5: Decrease voting power
        voteModule.withdraw(1000e18);

        // Step 6: Move to next period and poke
        vm.warp(block.timestamp + 1 weeks);
        voter.poke(alice);
        vm.stopPrank();

        // Step 7: Verify votes decreased proportionally
        uint256 newPeriod = voter.getPeriod();
        assertLt(
            voter.userVotesForPoolPerPeriod(alice, newPeriod + 1, pool),
            initialVoteAmount,
            "Vote amount should decrease after voting power reduction"
        );
    }

    function test_pokeHandlesZeroVotingPower() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup initial vote parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Give alice initial voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Remove all voting power
        voteModule.withdraw(1000e18);

        // Step 5: Move to next period and poke
        vm.warp(block.timestamp + 1 weeks);
        voter.poke(alice);
        vm.stopPrank();

        // Step 6: Verify no votes were cast
        uint256 newPeriod = voter.getPeriod();
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, newPeriod + 1, pool),
            0,
            "No votes should be cast with zero voting power"
        );
    }

    function test_pokeAfterVoteInSamePeriodUpdatesVotingPower() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Initial vote with 1000 voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Add more voting power
        deal(address(xShadow), alice, 1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 5: Poke in same period
        voter.poke(alice);
        vm.stopPrank();

        // Step 6: Verify voting power was updated
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(
            voter.userVotingPowerPerPeriod(alice, nextPeriod), 2000e18, "Voting power should be updated after poke"
        );
    }

    function test_pokeAfterVoteWithMultiplePoolsUpdatesProportionally() public {
        // Step 1: Setup multiple pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Setup voting with 60/40 split
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60;
        weights[1] = 40;

        // Step 3: Initial vote with 1000 voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Record initial votes
        uint256 nextPeriod = voter.getPeriod() + 1;
        uint256 initialVote1 = voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool1);
        uint256 initialVote2 = voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool2);

        // Step 5: Add more voting power
        deal(address(xShadow), alice, 1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 6: Poke
        voter.poke(alice);
        vm.stopPrank();

        // Step 7: Verify proportions maintained with increased voting power
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool1), initialVote1 * 2, "Pool1 votes should double"
        );
        assertEq(
            voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool2), initialVote2 * 2, "Pool2 votes should double"
        );
    }

    function test_pokeAfterVoteWithDeadGaugeRemovesVotes() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Initial vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Kill the gauge
        vm.stopPrank();
        vm.prank(address(accessHub));
        voter.killGauge(gauge);

        // Step 5: Poke should reset votes since gauge is dead
        vm.prank(alice);
        voter.poke(alice);

        // Step 6: Verify votes were removed
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool), 0, "Votes should be removed for dead gauge");
    }

    function test_consecutiveVotesInSamePeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters for first vote
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: First vote with initial voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Setup second pool and gauge
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool2);

        // Step 5: Setup voting parameters for second vote
        address[] memory newPools = new address[](2);
        newPools[0] = pool;
        newPools[1] = pool2;
        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 60;
        newWeights[1] = 40;

        // Step 6: Second vote with additional voting power
        deal(address(xShadow), alice, 1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, newPools, newWeights);
        vm.stopPrank();

        // Step 7: Verify vote distribution
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool), 1200e18, "Should have 60% weight for pool1");
        assertEq(voter.userVotesForPoolPerPeriod(alice, nextPeriod, pool2), 800e18, "Should have 40% weight for pool2");
        assertEq(
            voter.userVotingPowerPerPeriod(alice, nextPeriod), 2000e18, "Should have total voting power of 2000e18"
        );
    }

    function test_voteAfterPokeInSamePeriod() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Initial vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Poke
        voter.poke(alice);

        // Step 5: Vote again in same period
        deal(address(xShadow), alice, 1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 6: Verify final vote state
        uint256 nextPeriod = voter.getPeriod() + 1;
        assertEq(
            voter.userVotingPowerPerPeriod(alice, nextPeriod), 2000e18, "Should have final voting power after vote"
        );
    }

    function test_pokeResetsVotesBeforeRecasting() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        voter.createGauge(pool);

        // Step 2: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 3: Initial vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);

        // Step 4: Record initial state
        uint256 nextPeriod = voter.getPeriod() + 1;
        uint256 initialTotalVotes = voter.totalVotesPerPeriod(nextPeriod);

        // Step 5: Add more voting power and poke
        deal(address(xShadow), alice, 1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.poke(alice);
        vm.stopPrank();

        // Step 6: Verify votes were properly reset and recast
        assertGt(
            voter.totalVotesPerPeriod(nextPeriod),
            initialTotalVotes,
            "Total votes should increase after reset and recast"
        );
    }

    function test_setGovernorSucceedsWhenCallerIsGovernance() public {
        // Step 1: Setup new governor address
        address newGovernor = address(0x123);

        // Step 2: Set new governor and verify event
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, false);
        emit NewGovernor(address(accessHub), newGovernor);
        voter.setGovernor(newGovernor);

        // Step 3: Verify governor was updated
        assertEq(voter.governor(), newGovernor, "Governor should be updated");
    }

    function test_setGovernorDoesNotEmitWhenSameGovernor() public {
        // Step 1: Get current governor
        address currentGovernor = voter.governor();

        // Step 2: Attempt to set same governor
        vm.prank(address(accessHub));
        voter.setGovernor(currentGovernor);

        // Step 3: Verify governor remains unchanged
        assertEq(voter.governor(), currentGovernor, "Governor should remain unchanged");
    }

    function test_setGovernorRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup new governor address
        address newGovernor = address(0x123);

        // Step 2: Attempt to set governor from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.setGovernor(newGovernor);
    }

    function test_whitelistSucceedsWhenCallerIsGovernance() public {
        // Step 1: Setup token to whitelist
        address token = address(0x123);

        // Step 2: Whitelist token and verify event
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, false);
        emit Whitelisted(address(accessHub), token);
        voter.whitelist(token);

        // Step 3: Verify token is whitelisted
        assertTrue(voter.isWhitelisted(token), "Token should be whitelisted");
    }

    function test_whitelistRevertsWhenTokenAlreadyWhitelisted() public {
        // Step 1: Setup token to whitelist
        address token = address(0x123);

        // Step 2: Whitelist token first time
        vm.startPrank(address(accessHub));
        voter.whitelist(token);

        // Step 3: Attempt to whitelist again
        vm.expectRevert(abi.encodeWithSignature("ALREADY_WHITELISTED(address)", token));
        voter.whitelist(token);
        vm.stopPrank();
    }

    function test_whitelistRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup token to whitelist
        address token = address(0x123);

        // Step 2: Attempt to whitelist from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.whitelist(token);
    }

    function test_revokeWhitelistSucceedsWhenCallerIsGovernance() public {
        // Step 1: Setup and whitelist token
        address token = address(0x123);

        vm.startPrank(address(accessHub));
        voter.whitelist(token);

        // Step 2: Revoke whitelist and verify event
        vm.expectEmit(true, true, false, true);
        emit WhitelistRevoked(address(accessHub), token, true);
        voter.revokeWhitelist(token);
        vm.stopPrank();

        // Step 3: Verify token is not whitelisted
        assertFalse(voter.isWhitelisted(token), "Token should not be whitelisted");
    }

    function test_revokeWhitelistRevertsWhenTokenNotWhitelisted() public {
        // Step 1: Setup token
        address token = address(0x123);

        // Step 2: Attempt to revoke non-whitelisted token
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_WHITELISTED()"));
        voter.revokeWhitelist(token);
    }

    function test_revokeWhitelistRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup and whitelist token
        address token = address(0x123);

        vm.startPrank(address(accessHub));
        voter.whitelist(token);
        vm.stopPrank();

        // Step 2: Attempt to revoke whitelist from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.revokeWhitelist(token);
    }

    function test_whitelistAndRevokeWhitelistIntegration() public {
        // Step 1: Setup token
        address token = address(0x123);

        // Step 2: Whitelist token and verify
        vm.startPrank(address(accessHub));
        voter.whitelist(token);
        assertTrue(voter.isWhitelisted(token), "Token should be whitelisted");

        // Step 3: Revoke whitelist and verify
        voter.revokeWhitelist(token);
        assertFalse(voter.isWhitelisted(token), "Token should not be whitelisted");

        // Step 4: Whitelist again and verify
        voter.whitelist(token);
        assertTrue(voter.isWhitelisted(token), "Token should be whitelisted again");
        vm.stopPrank();
    }

    function test_whitelistGaugeRewardsRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup pool, gauge and reward token
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address reward = address(0x123);

        // Step 2: Attempt to whitelist reward from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.whitelistGaugeRewards(gauge, reward);
    }

    function test_whitelistGaugeRewardsRevertsWhenRewardNotWhitelisted() public {
        // Step 1: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address reward = address(0x123); // Non-whitelisted token

        // Step 2: Try to whitelist non-whitelisted reward
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_WHITELISTED()"));
        voter.whitelistGaugeRewards(gauge, reward);
    }

    function test_whitelistGaugeRewardsSucceedsForLegacyGauge() public {
        // Step 1: Setup pool, gauge and reward token
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address reward = address(token6Decimals); // Already whitelisted in setup

        // Step 2: Whitelist reward
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, reward);

        // Step 3: Verify reward is whitelisted in gauge
        assertTrue(IGauge(gauge).isWhitelisted(reward), "Reward should be whitelisted in gauge");
    }

    function test_removeGaugeRewardWhitelistRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup pool, gauge and reward token
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address reward = address(token6Decimals);

        // Step 2: Try to remove reward whitelist from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.removeGaugeRewardWhitelist(gauge, reward);
    }

    function test_removeGaugeRewardWhitelistSucceedsForLegacyGauge() public {
        // Step 1: Setup pool, gauge and reward token
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address reward = address(token6Decimals);

        // Step 2: First whitelist the reward
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, reward);

        // Step 3: Remove reward whitelist
        vm.prank(address(accessHub));
        voter.removeGaugeRewardWhitelist(gauge, reward);

        // Step 4: Verify reward is not whitelisted
        assertFalse(IGauge(gauge).isWhitelisted(reward), "Reward should not be whitelisted");
    }

    function test_removeFeeDistributorRewardRevertsWhenCallerNotGovernance() public {
        // Step 1: Setup pool, gauge and fee distributor
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address feeDistributor = voter.feeDistributorForGauge(gauge);
        address reward = address(token6Decimals);

        // Step 2: Try to remove reward from unauthorized account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
        voter.removeFeeDistributorReward(feeDistributor, reward);
    }

    function test_removeFeeDistributorRewardSucceeds() public {
        // Step 1: Setup pool, gauge and fee distributor
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address feeDistributor = voter.feeDistributorForGauge(gauge);
        address reward = address(token6Decimals);

        // Step 2: First whitelist the reward token
        vm.prank(address(accessHub));

        // Step 3: Incentivize with some rewards
        deal(reward, address(this), 1e18);
        IERC20(reward).approve(feeDistributor, 1e18);
        IFeeDistributor(feeDistributor).incentivize(reward, 1e18);

        // Step 4: Verify mock was called and remove reward
        vm.expectCall(feeDistributor, abi.encodeWithSelector(IFeeDistributor.removeReward.selector, reward));
        vm.prank(address(accessHub));
        voter.removeFeeDistributorReward(feeDistributor, reward);
    }

    function test_whitelistGaugeRewardsSucceedsForCLGauge() public {
        // Step 1: Setup CL gauge
        mockClGaugeCalls(address(token0), address(token1), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token1), 60);
        address reward = address(token6Decimals); // Already whitelisted in setup

        // Step 2: Mock and verify addRewards call
        vm.mockCall(clGauge, abi.encodeWithSelector(IGaugeV3.addRewards.selector, reward), abi.encode());
        vm.expectCall(clGauge, abi.encodeWithSelector(IGaugeV3.addRewards.selector, reward));

        // Step 3: Whitelist reward
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(clGauge, reward);
    }

    function test_removeGaugeRewardWhitelistSucceedsForCLGauge() public {
        // Step 1: Setup CL gauge
        mockClGaugeCalls(address(token0), address(token1), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token1), 60);
        address reward = address(token6Decimals);

        // Step 2: Mock removeRewards call
        vm.mockCall(clGauge, abi.encodeWithSelector(IGaugeV3.removeRewards.selector, reward), abi.encode());

        // Step 3: Verify mock was called and remove reward
        vm.expectCall(clGauge, abi.encodeWithSelector(IGaugeV3.removeRewards.selector, reward));
        vm.prank(address(accessHub));
        voter.removeGaugeRewardWhitelist(clGauge, reward);
    }

    function test_getAllGaugesReturnsEmptyArrayWhenNoGauges() public view {
        // Step 1: Call getAllGauges and verify empty array
        address[] memory gauges = voter.getAllGauges();
        assertEq(gauges.length, 0, "Should return empty array when no gauges");
    }

    function test_getAllGaugesReturnsAllTypes() public {
        // Step 1: Create legacy gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address legacyGauge = voter.createGauge(pool);

        // Step 2: Create CL gauge
        mockClGaugeCalls(address(token0), address(token6Decimals), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token6Decimals), 60);

        // Step 3: Create arbitrary gauge
        address customPool = address(new MockERC20());
        vm.prank(address(accessHub));
        voter.whitelist(customPool);
        vm.prank(address(accessHub));
        // Step 4: Get all gauges
        address[] memory gauges = voter.getAllGauges();

        // Step 5: Verify results
        assertEq(gauges.length, 2, "Should return all gauge types");
        assertTrue(gauges[0] == legacyGauge || gauges[1] == legacyGauge, "Should contain legacy gauge");
        assertTrue(gauges[0] == clGauge || gauges[1] == clGauge, "Should contain CL gauge");
    }

    function test_getAllFeeDistributorsReturnsEmptyArrayWhenNoDistributors() public view {
        // Step 1: Call getAllFeeDistributors and verify empty array
        address[] memory distributors = voter.getAllFeeDistributors();
        assertEq(distributors.length, 0, "Should return empty array when no fee distributors");
    }

    function test_getAllFeeDistributorsReturnsCorrectDistributors() public {
        // Step 1: Create two pools/gauges to generate fee distributors
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Get all fee distributors
        address[] memory distributors = voter.getAllFeeDistributors();

        // Step 3: Verify results
        assertEq(distributors.length, 2, "Should return correct number of fee distributors");
        assertTrue(
            voter.isFeeDistributor(distributors[0]) && voter.isFeeDistributor(distributors[1]),
            "All returned addresses should be fee distributors"
        );
    }

    function test_isGaugeReturnsTrueForValidGauges() public {
        // Step 1: Create different types of gauges
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address legacyGauge = voter.createGauge(pool);

        mockClGaugeCalls(address(token0), address(token6Decimals), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token6Decimals), 60);

        address customPool = address(new MockERC20());
        vm.startPrank(address(accessHub));
        voter.whitelist(customPool);
        vm.stopPrank();

        // Step 2: Verify all are recognized as gauges
        assertTrue(voter.isGauge(legacyGauge), "Legacy gauge should be recognized");
        assertTrue(voter.isGauge(clGauge), "CL gauge should be recognized");
    }

    function test_isGaugeReturnsFalseForInvalidGauge() public view {
        // Step 1: Verify non-gauge address returns false
        assertFalse(voter.isGauge(address(0x123)), "Should return false for non-gauge address");
    }

    function test_isFeeDistributorReturnsTrueForValidDistributor() public {
        // Step 1: Create pool and gauge to generate fee distributor
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);
        address feeDistributor = voter.feeDistributorForGauge(gauge);

        // Step 2: Verify fee distributor is recognized
        assertTrue(voter.isFeeDistributor(feeDistributor), "Should return true for valid fee distributor");
    }

    function test_isFeeDistributorReturnsFalseForInvalidDistributor() public view {
        // Step 1: Verify non-distributor address returns false
        assertFalse(voter.isFeeDistributor(address(0x123)), "Should return false for non-fee distributor address");
    }

    function test_tickSpacingsForPairReturnsEmptyForNonexistentPair() public view {
        // Step 1: Get tick spacings for nonexistent pair
        int24[] memory spacings = voter.tickSpacingsForPair(address(token0), address(token1));

        // Step 2: Verify empty array is returned
        assertEq(spacings.length, 0, "Should return empty array for nonexistent pair");
    }

    function test_tickSpacingsForPairReturnsCorrectSpacings() public {
        // Step 1: Create CL gauges with different tick spacings
        mockClGaugeCalls(address(token0), address(token1), 60);
        voter.createCLGauge(address(token0), address(token1), 60);

        mockClGaugeCalls(address(token0), address(token1), 200);
        vm.prank(address(TREASURY));
        voter.createCLGauge(address(token0), address(token1), 200);

        // Step 2: Get tick spacings
        int24[] memory spacings = voter.tickSpacingsForPair(address(token0), address(token1));

        // Step 3: Verify results
        assertEq(spacings.length, 2, "Should return correct number of tick spacings");
        assertTrue(
            (spacings[0] == 60 && spacings[1] == 200) || (spacings[0] == 200 && spacings[1] == 60),
            "Should contain both tick spacings"
        );
    }

    function test_mainTickSpacingForPairReturnsZeroForNonexistentPair() public view {
        // Step 1: Get main tick spacing for nonexistent pair
        int24 spacing = voter.mainTickSpacingForPair(address(token0), address(token1));

        // Step 2: Verify zero is returned
        assertEq(spacing, 0, "Should return 0 for nonexistent pair");
    }

    function test_mainTickSpacingForPairReturnsFirstSpacing() public {
        // Step 1: Create first CL gauge - this becomes the main tick spacing
        mockClGaugeCalls(address(token0), address(token1), 60);
        voter.createCLGauge(address(token0), address(token1), 60);

        // Step 2: Create second CL gauge
        mockClGaugeCalls(address(token0), address(token1), 200);
        vm.prank(address(TREASURY));
        voter.createCLGauge(address(token0), address(token1), 200);

        // Step 3: Verify main tick spacing is from first gauge
        assertEq(
            voter.mainTickSpacingForPair(address(token0), address(token1)),
            60,
            "Should return first tick spacing as main"
        );
    }

    function test_gaugeForClPoolReturnsZeroForNonexistentPool() public view {
        // Step 1: Get gauge for nonexistent pool
        address gauge = voter.gaugeForClPool(address(token0), address(token1), 60);

        // Step 2: Verify zero address is returned
        assertEq(gauge, address(0), "Should return zero address for nonexistent pool");
    }

    function test_gaugeForClPoolReturnsCorrectGauge() public {
        // Step 1: Create CL gauge
        mockClGaugeCalls(address(token0), address(token1), 60);
        address clGauge = voter.createCLGauge(address(token0), address(token1), 60);

        // Step 2: Verify gauge lookup
        assertEq(
            voter.gaugeForClPool(address(token0), address(token1), 60), clGauge, "Should return correct gauge address"
        );
    }

    function test_gaugeForClPoolHandlesTokenOrder() public {
        // Step 1: Create CL gauge
        mockClGaugeCalls(address(token0), address(token1), 60);
        voter.createCLGauge(address(token0), address(token1), 60);

        // Step 2: Verify gauge lookup works with tokens in either order
        assertEq(
            voter.gaugeForClPool(address(token0), address(token1), 60),
            voter.gaugeForClPool(address(token1), address(token0), 60),
            "Should return same gauge regardless of token order"
        );
    }

    function test_distributeWithZeroXRatio() public {
        // Step 1: Set xRatio to 0 (100% emissions to shadow)
        vm.prank(address(accessHub));
        voter.setGlobalRatio(0);

        // Step 2: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        IERC20(pool).approve(address(gauge), type(uint256).max);
        deal(address(pool), alice, 1000e18);
        IGauge(gauge).deposit(1000e18);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Move to next epoch and notify rewards
        vm.warp(block.timestamp + 1 weeks);
        uint256 amount = 1000e18;
        deal(address(shadow), address(mockMinter), amount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);
        voter.notifyRewardAmount(amount);
        vm.stopPrank();

        // Step 6: Move forward and distribute
        vm.warp(block.timestamp + 2 weeks);
        voter.distribute(gauge);

        vm.warp(block.timestamp + 3 weeks);

        // Step 7: Verify reward distribution
        assertApproxEqAbs(
            IGauge(gauge).earned(address(shadow), alice),
            amount,
            1000,
            "All rewards should go to shadow"
        );
        assertEq(IGauge(gauge).earned(address(xShadow), alice), 0, "No rewards should go to xShadow");
    }

    function test_createGaugeWithUnwhitelistedTokens() public {
        // Step 1: Create pair with unwhitelisted tokens
        address unwhitelistedToken = address(new MockERC20());
        address pool = pairFactory.createPair(address(unwhitelistedToken), address(token1), false);

        // Step 2: Attempt to create gauge and verify revert
        vm.expectRevert(abi.encodeWithSignature("NOT_WHITELISTED()"));
        voter.createGauge(pool);
    }

    function test_createGaugeWithInvalidPair() public {
        // Step 1: Deploy a random ERC20 token that isn't a valid LP token
        address notAPair = address(new MockERC20());

        // Step 2: Attempt to create gauge and verify revert
        vm.expectRevert(abi.encodeWithSignature("NOT_POOL()"));
        voter.createGauge(notAPair);
    }

    function test_xRatioChangesMidPeriod() public {
        // Step 1: Initial setup with 50% ratio
        vm.prank(address(accessHub));
        voter.setGlobalRatio(500_000); // 50%

        // Step 2: Create pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        // Step 4: Give alice voting power and vote
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);
        voter.vote(alice, pools, weights);
        vm.stopPrank();

        // Step 5: Give alice LP tokens and stake them
        deal(pool, alice, 100e18);
        vm.startPrank(alice);
        uint256 lpBalance = IERC20(pool).balanceOf(alice);
        IERC20(pool).approve(gauge, lpBalance);
        IGauge(gauge).deposit(lpBalance);
        vm.stopPrank();

        // Step 6: Move to next epoch and notify rewards
        vm.warp(block.timestamp + 1 weeks);
        uint256 amount = 1000e18;
        deal(address(shadow), address(mockMinter), amount);

        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), amount);
        voter.notifyRewardAmount(amount);
        vm.stopPrank();

        // Step 7: Change ratio mid-period to 80%
        vm.prank(address(accessHub));
        voter.setGlobalRatio(800_000); // 80%

        // Step 8: Move forward and distribute
        vm.warp(block.timestamp + 2 weeks);
        voter.distribute(gauge);

        vm.warp(block.timestamp + 3 weeks);

        // Step 9: Verify distribution used the new ratio
        assertApproxEqAbs(
            IGauge(gauge).earned(address(shadow), alice),
            amount * 20 / 100, // 20% to emissions (100% - 80%)
            1000,
            "Emissions should reflect new ratio"
        );
        assertApproxEqAbs(
            IGauge(gauge).earned(address(xShadow), alice),
            amount * 80 / 100, // 80% to xShadow
            1000,
            "xShadow should reflect new ratio"
        );
    }

    function test_reviveNeverKilledGauge() public {
        // Step 1: Create gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 2: Try to revive an already alive gauge
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ACTIVE_GAUGE(address)", gauge));
        voter.reviveGauge(gauge);
    }

    function test_voteWithZeroWeightPool() public {
        // Step 1: Create two pools and gauges
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address pool2 = pairFactory.createPair(address(token0), address(token6Decimals), false);
        voter.createGauge(pool1);
        voter.createGauge(pool2);

        // Step 2: Setup voting with one zero weight
        address[] memory pools = new address[](2);
        pools[0] = pool1;
        pools[1] = pool2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 100;
        weights[1] = 0; // Zero weight for second pool

        // Step 3: Give alice voting power
        deal(address(xShadow), alice, 1000e18);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), 1000e18);
        voteModule.deposit(1000e18);

        // Step 4: Try to vote with zero weight pool
        vm.expectRevert(abi.encodeWithSignature("VOTE_UNSUCCESSFUL()"));
        voter.vote(alice, pools, weights);
        vm.stopPrank();
    }

    function mockClGaugeCalls(address tokenA, address tokenB, int24 tickSpacing) internal returns (address pool) {
        // Step 1: Mock CL pool call
        pool = address(new MockRamsesV3Pool());
        vm.mockCall(
            CL_FACTORY,
            abi.encodeWithSelector(IRamsesV3Factory.getPool.selector, address(tokenA), address(tokenB), tickSpacing),
            abi.encode(pool)
        );

        // Step 2: Mock slot0 call to indicate pool is initialized
        vm.mockCall(pool, abi.encodeWithSelector(RamsesV3Pool.slot0.selector), abi.encode(0, 0, 0, 0, 0, 0, true));

        // Step 3: Mock getFeeCollector call
        vm.mockCall(
            CL_FACTORY,
            abi.encodeWithSelector(IRamsesV3Factory.feeCollector.selector),
            abi.encode(address(FEE_COLLECTOR))
        );

        // Step 4: Mock collectProtocolFees call
        vm.mockCall(
            FEE_COLLECTOR, abi.encodeWithSelector(IFeeCollector.collectProtocolFees.selector, pool), abi.encode()
        );

        address mockClGauge = makeAddr(string(abi.encode(tokenA, tokenB, tickSpacing)));

        // Step 5: Mock createGauge call
        vm.mockCall(
            CL_GAUGE_FACTORY,
            abi.encodeWithSelector(IClGaugeFactory.createGauge.selector, pool),
            abi.encode(mockClGauge)
        );

        // Step 6: Mock CL Factory gaugeFeeSplitEnable
        vm.mockCall(
            CL_FACTORY, abi.encodeWithSelector(IRamsesV3Factory.gaugeFeeSplitEnable.selector, pool), abi.encode()
        );
    }

    function testFuzz_competitiveVotingAndDistribution(
        uint256[20] memory deposits,
        uint256[20] memory gaugeDeposits,
        uint256[20] memory weights,
        uint256 rewardAmount
    ) public {
        // Step 1: Bound inputs
        uint256 boundedReward = bound(rewardAmount, 1000e18, 1000000e18);

        // Step 2: Setup pool and gauge
        address pool = pairFactory.createPair(address(token0), address(token1), false);
        address gauge = voter.createGauge(pool);

        // Step 3: Setup voting parameters
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory voteWeights = new uint256[](1);

        address[3] memory voters = [alice, bob, carol];
        uint256 totalVotingPower;
        uint256 totalGaugeDeposit;
        uint256[] memory boundedGaugeDeposits = new uint256[](gaugeDeposits.length);

        // Step 4: Setup initial votes and gauge deposits for all participants
        for (uint256 i = 0; i < 3; i++) {
            uint256 boundedDeposit = bound(deposits[i], 0.001e18, 1000000e18);
            uint256 boundedGaugeDeposit = bound(gaugeDeposits[i], 0.001e18, 1000000e18);
            uint256 boundedWeight = bound(weights[i], 1, 100);

            // Setup voting power
            deal(address(xShadow), voters[i], boundedDeposit);
            vm.startPrank(voters[i]);
            xShadow.approve(address(voteModule), boundedDeposit);
            voteModule.deposit(boundedDeposit);

            voteWeights[0] = boundedWeight;
            voter.vote(voters[i], pools, voteWeights);

            // Setup gauge deposits
            deal(address(pool), voters[i], boundedGaugeDeposit);
            IERC20(pool).approve(gauge, boundedGaugeDeposit);
            IGauge(gauge).deposit(boundedGaugeDeposit);
            vm.stopPrank();

            totalVotingPower += boundedDeposit;
            totalGaugeDeposit += boundedGaugeDeposit;
            boundedGaugeDeposits[i] = boundedGaugeDeposit;
        }

        // Step 5: Whitelist gauge rewards and advance time
        vm.prank(address(accessHub));
        voter.whitelistGaugeRewards(gauge, address(xShadow));
        vm.warp(block.timestamp + 1 weeks);

        // Step 6: Setup and notify rewards
        deal(address(shadow), address(mockMinter), boundedReward);
        vm.startPrank(address(mockMinter));
        shadow.approve(address(voter), boundedReward);
        voter.notifyRewardAmount(boundedReward);
        vm.stopPrank();

        // Step 7: Distribute rewards
        voter.distribute(gauge);

        // Step 8: Allow rewards to accumulate
        vm.warp(block.timestamp + 2 weeks);

        // Step 9: Verify rewards for each participant
        uint256 totalEarned;
        for (uint256 i = 0; i < 3; i++) {
            uint256 earned = IGauge(gauge).earned(address(xShadow), voters[i]);
            totalEarned += earned;
            // Verify earned amount is proportional to stake
            uint256 expectedShare = (boundedReward * boundedGaugeDeposits[i]) / totalGaugeDeposit;
            assertApproxEqRel(
                earned,
                expectedShare,
                1e16,
                string.concat("Earned rewards not proportional to stake for voter ", vm.toString(i))
            );
        }

        // Step 10: Verify total rewards tracking
        assertLe(totalEarned, boundedReward, "Total earned should not exceed rewards");
    }

    function test_createDuplicateGaugesForSameTokensFails() public {
        // Step 1: Create first gauge with token0/token1
        address pool1 = pairFactory.createPair(address(token0), address(token1), false);
        address gauge1 = voter.createGauge(pool1);

        // Step 2: Try to create another gauge with same pool
        vm.expectRevert(abi.encodeWithSignature("ACTIVE_GAUGE(address)", gauge1));
        voter.createGauge(pool1);

        // Step 3: Verify only first gauge exists
        assertTrue(voter.isGauge(gauge1), "First gauge should exist");
        assertEq(voter.gaugeForPool(pool1), gauge1, "First gauge should be mapped to pool1");
    }
}

contract MockVoterWithSetAlive is Voter {
    constructor(address _governor) Voter(_governor) {}

    function setAlive(address gauge, bool alive) external {
        isAlive[gauge] = alive;
    }
}

contract MockRamsesV3Pool {
    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint16, bool) {
        return (0, 0, 0, 0, 0, 0, true);
    }
}
