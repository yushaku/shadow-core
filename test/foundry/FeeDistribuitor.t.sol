// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {FeeDistributor} from "../../contracts/FeeDistributor.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract FeeDistributorTest is TestBase {
    FeeDistributor public feeDistributor;
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    event Deposit(address indexed owner, uint256 amount);
    event Withdraw(address indexed owner, uint256 amount);
    event NotifyReward(address indexed from, address indexed token, uint256 amount, uint256 period);
    event VotesIncentivized(address indexed from, address indexed token, uint256 amount, uint256 period);
    event ClaimRewards(
        uint256 indexed period, address indexed owner, address indexed receiver, address token, uint256 amount
    );
    event RewardsRemoved(address indexed token);

    function setUp() public override {
        super.setUp();

        vm.warp(100 weeks);
        // Deploy FeeDistributor
        vm.prank(address(mockVoter));
        // Mock launcherPlugin call on mockVoter to return mock address
        vm.mockCall(address(mockVoter), abi.encodeWithSignature("launcherPlugin()"), abi.encode(mockLauncherPlugin));
        feeDistributor = new FeeDistributor(address(mockVoter), address(feeRecipient));

        // Setup initial token balances
        deal(address(token0), alice, INITIAL_SUPPLY);
        deal(address(token0), bob, INITIAL_SUPPLY);
        deal(address(token0), carol, INITIAL_SUPPLY);

        // Whitelist token0 in voter
        vm.prank(address(mockVoter));
        mockVoter.whitelist(address(token0));
        vm.label(address(feeDistributor), "feeDistributor");
        vm.label(address(mockLauncherPlugin), "mockLauncherPlugin");
    }

    function test_initialization() public view {
        assertEq(address(feeDistributor.voter()), address(mockVoter), "voter address mismatch");
        assertEq(address(feeDistributor.feeRecipient()), address(feeRecipient), "feeRecipient address mismatch");
        assertEq(feeDistributor.firstPeriod(), feeDistributor.getPeriod(), "firstPeriod mismatch");
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        vm.startPrank(address(mockVoter));
        feeDistributor._deposit(amount, alice);
        vm.stopPrank();

        assertEq(feeDistributor.balanceOf(alice), amount, "Incorrect balance after deposit");
        assertEq(feeDistributor.votes(feeDistributor.getPeriod() + 1), amount, "Incorrect votes after deposit");
    }

    function test_onlyVoterCanDeposit() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeDistributor._deposit(100e18, alice);
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        // First deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(amount, alice);

        // Then withdraw
        vm.startPrank(address(mockVoter));
        feeDistributor._withdraw(amount, alice);
        vm.stopPrank();

        // Check that alice's token balance is restored after withdrawal
        assertEq(feeDistributor.balanceOf(alice), 0, "Balance not zero after withdraw");
        assertEq(feeDistributor.votes(feeDistributor.getPeriod() + 1), 0, "Votes not zero after withdraw");
    }

    function test_onlyVoterCanWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeDistributor._withdraw(100e18, alice);
    }

    function test_notifyRewardAmount() public {
        uint256 amount = 100e18;
        uint256 nextPeriod = feeDistributor.getPeriod() + 1;

        // Setup approval and balance
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), amount);
        IERC20(address(token0)).approve(address(feeDistributor), amount);

        // Need to add launcher plugin mocks here
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        vm.expectEmit(true, true, false, true);
        emit NotifyReward(address(feeRecipient), address(token0), amount, nextPeriod);
        feeDistributor.notifyRewardAmount(address(token0), amount);
        vm.stopPrank();

        assertEq(
            feeDistributor.rewardSupply(nextPeriod, address(token0)),
            amount,
            "Incorrect reward supply after notification"
        );
    }

    function test_onlyFeeRecipientCanNotifyReward() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeDistributor.notifyRewardAmount(address(token0), 100e18);
    }

    function test_incentivize() public {
        uint256 amount = 100e18;
        uint256 nextPeriod = feeDistributor.getPeriod() + 1;

        // Setup approval and balance
        vm.startPrank(alice);
        deal(address(token0), alice, amount);
        IERC20(address(token0)).approve(address(feeDistributor), amount);

        vm.expectEmit(true, true, false, true);
        emit VotesIncentivized(alice, address(token0), amount, nextPeriod);
        feeDistributor.incentivize(address(token0), amount);
        vm.stopPrank();

        assertEq(
            feeDistributor.rewardSupply(nextPeriod, address(token0)),
            amount,
            "Incorrect reward supply after incentivize"
        );
    }

    function test_getPeriodReward() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 period = feeDistributor.getPeriod();
        vm.prank(alice);
        feeDistributor.getPeriodReward(period, alice, address(token0));

        assertEq(
            feeDistributor.lastClaimByToken(address(token0), alice),
            period - 1,
            "Last claim period not updated correctly"
        );
    }

    function test_getReward() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);

        uint256 balanceBefore = IERC20(address(token0)).balanceOf(alice);
        vm.startPrank(alice);
        feeDistributor.getReward(alice, tokens);
        uint256 balanceAfter = IERC20(address(token0)).balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, rewardAmount, "Incorrect balance after claim");
        assertEq(feeDistributor.earned(address(token0), alice), 0, "Incorrect earned after claim");
    }

    function test_getRewardForOwner() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);

        vm.prank(address(mockVoter));
        feeDistributor.getRewardForOwner(alice, tokens);
    }

    function test_removeRewardWithUnclaimedRewards() public {
        // Setup initial deposit and reward
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Remove reward token
        vm.prank(address(mockVoter));
        feeDistributor.removeReward(address(token0));

        // Check earned amount is still correct
        uint256 earned = feeDistributor.earned(address(token0), alice);
        assertEq(earned, rewardAmount, "Should still show correct earned amount after token removed");

        // Mock vote module call to allow alice to claim
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        // Claim rewards
        uint256 balanceBefore = IERC20(address(token0)).balanceOf(alice);
        vm.prank(alice);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token0);
        feeDistributor.getReward(alice, tokens);
        uint256 balanceAfter = IERC20(address(token0)).balanceOf(alice);

        // Verify rewards were received
        assertEq(
            balanceAfter - balanceBefore, rewardAmount, "Should still be able to claim rewards after token removed"
        );
    }

    function test_onlyVoterCanRemoveReward() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeDistributor.removeReward(address(token0));
    }

    function test_earnedNoLauncherPlugin() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );
        vm.expectEmit(true, true, false, true);
        emit NotifyReward(address(feeRecipient), address(token0), rewardAmount, feeDistributor.getPeriod() + 1);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(token0), alice);
        // Calculate expected rewards
        // Since there is only one user with all votes, they should receive all rewards
        uint256 expectedReward = rewardAmount;
        assertEq(earned, expectedReward, "Earned rewards should equal total reward amount");
    }

    function test_earnedWithLauncherPlugin() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;
        address treasury = makeAddr("treasury");
        uint256 take = 2000; // 20% = 2000 basis points

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);

        // Mock launcher plugin to return true and set values
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(true)
        );
        vm.mockCall(address(mockLauncherPlugin), abi.encodeWithSignature("values(address)"), abi.encode(take, treasury));

        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(token0), alice);

        // Calculate expected rewards
        // 20% goes to treasury, so user gets 80% of rewards
        uint256 treasuryAmount = (rewardAmount * take) / 10_000; // 20% to treasury
        uint256 expectedReward = rewardAmount - treasuryAmount; // Remaining 80% to user

        assertEq(earned, expectedReward, "Earned rewards should equal 80% of total reward amount");
        // Verify treasury received its share
        uint256 treasuryBalance = IERC20(address(token0)).balanceOf(treasury);
        assertEq(treasuryBalance, treasuryAmount, "Treasury should have received 20% of rewards");
    }

    function test_notifyRewardWithZeroTake() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;
        address treasury = makeAddr("treasury");
        uint256 take = 0; // 0% take

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);

        // Mock launcher plugin to return true and set values
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(true)
        );
        vm.mockCall(address(mockLauncherPlugin), abi.encodeWithSignature("values(address)"), abi.encode(take, treasury));

        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(token0), alice);

        // With 0% take, user should get 100% of rewards
        assertEq(earned, rewardAmount, "Earned rewards should equal 100% of total reward amount");
        // Verify treasury received nothing
        uint256 treasuryBalance = IERC20(address(token0)).balanceOf(treasury);
        assertEq(treasuryBalance, 0, "Treasury should have received 0% of rewards");
    }

    function test_notifyRewardWithFullTake() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;
        address treasury = makeAddr("treasury");
        uint256 take = 10_000; // 100% = 10000 basis points

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);

        // Mock launcher plugin to return true and set values
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(true)
        );
        vm.mockCall(address(mockLauncherPlugin), abi.encodeWithSignature("values(address)"), abi.encode(take, treasury));

        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(token0), alice);

        // With 100% take, user should get 0% of rewards
        assertEq(earned, 0, "Earned rewards should equal 0% of total reward amount");
        // Verify treasury received everything
        uint256 treasuryBalance = IERC20(address(token0)).balanceOf(treasury);
        assertEq(treasuryBalance, rewardAmount, "Treasury should have received 100% of rewards");
    }

    function test_notifyRewardWithTransferTaxToken() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;
        uint256 initialPeriod = feeDistributor.getPeriod();

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Create mock tax token
        TaxToken taxToken = new TaxToken();
        taxToken.initialize("Tax Token", "TAX", 18);

        // Mock voter whitelist call for tax token
        vm.mockCall(address(mockVoter), abi.encodeWithSignature("isWhitelisted(address)"), abi.encode(true));

        // Setup reward with tax token
        vm.startPrank(address(feeRecipient));
        deal(address(taxToken), address(feeRecipient), rewardAmount);
        taxToken.approve(address(feeDistributor), rewardAmount);

        // Mock plugin calls, will skip it
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );

        feeDistributor.notifyRewardAmount(address(taxToken), rewardAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(taxToken), alice);
        uint256 afterTaxAmount = rewardAmount - (rewardAmount * 100) / 10000; // 1% tax

        // User should get the after-tax amount since that's what actually arrived
        assertEq(earned, afterTaxAmount, "Earned rewards should equal post-tax amount");
        // Verify we're looking at the next period's rewards
        assertEq(
            feeDistributor.rewardSupply(initialPeriod + 1, address(taxToken)),
            afterTaxAmount,
            "Reward supply should be in next period"
        );

        // Verify the rewardSupply tracks the actual received amount
        assertEq(
            feeDistributor.rewardSupply(feeDistributor.getPeriod(), address(taxToken)),
            afterTaxAmount,
            "Reward supply should equal post-tax amount"
        );
    }

    function testFuzz_multipleUsersRewards(uint256 deposit1, uint256 deposit2, uint256 rewardAmount) public {
        // Bound inputs to reasonable values
        deposit1 = bound(deposit1, 0.5e18, type(uint112).max / 2);
        deposit2 = bound(deposit2, 0.5e18, type(uint112).max / 2);
        rewardAmount = bound(rewardAmount, 1, type(uint112).max);

        // Setup deposits
        vm.startPrank(address(mockVoter));
        feeDistributor._deposit(deposit1, alice);
        feeDistributor._deposit(deposit2, bob);
        vm.stopPrank();

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), rewardAmount);
        IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
        vm.stopPrank();

        // Move forward by 1 week
        vm.warp(block.timestamp + 1 weeks);

        uint256 totalDeposits = deposit1 + deposit2;
        uint256 expectedRewardAlice = (rewardAmount * deposit1) / totalDeposits;
        uint256 expectedRewardBob = (rewardAmount * deposit2) / totalDeposits;

        uint256 earnedAlice = feeDistributor.earned(address(token0), alice);
        uint256 earnedBob = feeDistributor.earned(address(token0), bob);

        // We do this because the fuzzer sometimes generates values that are too small to be compared with assertApproxEqRel and 1% relative error
        if (earnedAlice < 1e5) {
            assertApproxEqAbs(earnedAlice, expectedRewardAlice, 1000, "Alice's earned rewards do not match expected");
        } else {
            assertApproxEqRel(earnedAlice, expectedRewardAlice, 0.01e18, "Alice's earned rewards do not match expected");
        }

        if (earnedBob < 1e5) {
            assertApproxEqAbs(earnedBob, expectedRewardBob, 1000, "Bob's earned rewards do not match expected");
        } else {
            assertApproxEqRel(earnedBob, expectedRewardBob, 0.01e18, "Bob's earned rewards do not match expected");
        }

        // Test actual reward claims
        uint256 period = feeDistributor.getPeriod();
        uint256 aliceBalanceBefore = IERC20(address(token0)).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(address(token0)).balanceOf(bob);

        // Mock vote module calls to allow alice and bob to claim their own rewards
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockVoteModule), abi.encodeWithSignature("isAdminFor(address,address)", bob, bob), abi.encode(true)
        );

        vm.prank(alice);
        feeDistributor.getPeriodReward(period, alice, address(token0));

        vm.prank(bob);
        feeDistributor.getPeriodReward(period, bob, address(token0));

        uint256 aliceBalanceAfter = IERC20(address(token0)).balanceOf(alice);
        uint256 bobBalanceAfter = IERC20(address(token0)).balanceOf(bob);

        // Verify actual received amounts match earned amounts
        assertEq(aliceBalanceAfter - aliceBalanceBefore, earnedAlice, "Alice did not receive correct reward amount");
        assertEq(bobBalanceAfter - bobBalanceBefore, earnedBob, "Bob did not receive correct reward amount");
    }

    function test_revertFutureClaimPeriod() public {
        // Setup initial deposits
        uint256 deposit = 1e18;
        _dealAndApprove(address(shadow), alice, deposit, address(feeDistributor));
        vm.prank(address(mockVoter));
        feeDistributor._deposit(deposit, alice);

        // Get current period
        uint256 currentPeriod = feeDistributor.getPeriod();

        // Try to claim for a future period
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_FINALIZED()"));
        feeDistributor.getPeriodReward(currentPeriod + 1, alice, address(token0));
    }

    function testFuzz_rewardsWithSixDecimals(uint256 deposit, uint256 rewardAmount) public {
        vm.assume(deposit > 0 && deposit < 1_000_000e18);
        vm.assume(rewardAmount > 0 && rewardAmount < 1_000_000e18);

        // Whitelist token6Decimals in voter
        mockVoter.whitelist(address(token6Decimals));

        // Setup initial deposits
        _dealAndApprove(address(shadow), alice, deposit, address(feeDistributor));
        vm.prank(address(mockVoter));
        feeDistributor._deposit(deposit, alice);

        // Get current period
        uint256 period = feeDistributor.getPeriod();

        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup reward
        vm.startPrank(address(feeRecipient));
        deal(address(token6Decimals), address(feeRecipient), rewardAmount);
        IERC20(address(token6Decimals)).approve(address(feeDistributor), rewardAmount);
        feeDistributor.notifyRewardAmount(address(token6Decimals), rewardAmount);
        vm.stopPrank();

        // Move forward by 1 week
        vm.warp(block.timestamp + 1 weeks);

        // Calculate expected rewards
        uint256 expectedReward = rewardAmount; // Since alice is the only depositor, she gets all rewards
        uint256 earned = feeDistributor.earned(address(token6Decimals), alice);

        assertApproxEqRel(earned, expectedReward, 0.01e18, "Alice's earned rewards do not match expected");

        // Store balance before claiming
        uint256 aliceBalanceBefore = IERC20(address(token6Decimals)).balanceOf(alice);
        period = feeDistributor.getPeriod();
        // Mock vote module call to allow alice to claim
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        // Claim rewards
        vm.prank(alice);
        feeDistributor.getPeriodReward(period, alice, address(token6Decimals));

        uint256 aliceBalanceAfter = IERC20(address(token6Decimals)).balanceOf(alice);

        // Verify actual received amount matches earned amount
        assertEq(aliceBalanceAfter - aliceBalanceBefore, earned, "Alice did not receive correct reward amount");
    }

    function testFuzz_combineNotifyAndIncentivize(uint256 deposit, uint256 notifyAmount, uint256 incentiveAmount)
        public
    {
        // Bound inputs to reasonable values
        deposit = bound(deposit, 1e18, type(uint112).max);
        notifyAmount = bound(notifyAmount, 1e18, type(uint112).max);
        incentiveAmount = bound(incentiveAmount, 1e18, type(uint112).max);

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(deposit, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup notify reward
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), notifyAmount);
        IERC20(address(token0)).approve(address(feeDistributor), notifyAmount);
        feeDistributor.notifyRewardAmount(address(token0), notifyAmount);
        vm.stopPrank();

        // Setup incentive
        vm.startPrank(alice);
        deal(address(token0), alice, incentiveAmount);
        IERC20(address(token0)).approve(address(feeDistributor), incentiveAmount);
        feeDistributor.incentivize(address(token0), incentiveAmount);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        // Calculate total expected rewards
        uint256 totalExpectedReward = notifyAmount + incentiveAmount;
        uint256 earned = feeDistributor.earned(address(token0), alice);

        // Since alice is the only depositor, she should get all rewards
        assertEq(earned, totalExpectedReward, "Earned rewards should equal combined rewards");

        // Test actual reward claim
        uint256 period = feeDistributor.getPeriod();
        uint256 balanceBefore = IERC20(address(token0)).balanceOf(alice);

        // Mock vote module call to allow alice to claim
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        // Claim rewards
        vm.prank(alice);
        feeDistributor.getPeriodReward(period, alice, address(token0));

        uint256 balanceAfter = IERC20(address(token0)).balanceOf(alice);
        uint256 actualReward = balanceAfter - balanceBefore;

        // Verify actual received amount matches earned amount
        assertEq(actualReward, earned, "Claimed amount should match earned amount");

        // Verify reward supply was correctly tracked
        assertEq(
            feeDistributor.rewardSupply(period, address(token0)),
            totalExpectedReward,
            "Reward supply should equal combined rewards"
        );
    }

    function test_incentivizeMidPeriod() public {
        uint256 depositAmount = 100e18;
        uint256 initialReward = 1000e18;
        uint256 midPeriodIncentive = 500e18;

        // Setup initial deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );

        // Setup initial reward at start of period
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), initialReward);
        IERC20(address(token0)).approve(address(feeDistributor), initialReward);
        feeDistributor.notifyRewardAmount(address(token0), initialReward);
        vm.stopPrank();

        // Move halfway through the period
        vm.warp(block.timestamp + 3 days);

        // Add incentive in middle of period
        vm.startPrank(alice);
        deal(address(token0), alice, midPeriodIncentive);
        IERC20(address(token0)).approve(address(feeDistributor), midPeriodIncentive);
        feeDistributor.incentivize(address(token0), midPeriodIncentive);
        vm.stopPrank();

        // Move to end of period
        vm.warp(block.timestamp + 4 days);

        // Calculate total expected rewards
        uint256 totalExpectedReward = initialReward + midPeriodIncentive;
        uint256 earned = feeDistributor.earned(address(token0), alice);

        // Since alice is the only depositor, she should get all rewards
        assertEq(earned, totalExpectedReward, "Earned rewards should equal combined rewards");

        // Test actual reward claim
        uint256 period = feeDistributor.getPeriod();
        uint256 balanceBefore = IERC20(address(token0)).balanceOf(alice);

        // Mock vote module call to allow alice to claim
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        // Claim rewards
        vm.prank(alice);
        feeDistributor.getPeriodReward(period, alice, address(token0));

        uint256 balanceAfter = IERC20(address(token0)).balanceOf(alice);
        uint256 actualReward = balanceAfter - balanceBefore;

        // Verify actual received amount matches earned amount
        assertEq(actualReward, earned, "Claimed amount should match earned amount");

        // Verify reward supply was correctly tracked
        assertEq(
            feeDistributor.rewardSupply(period, address(token0)),
            totalExpectedReward,
            "Reward supply should equal combined rewards"
        );

        // Verify that rewards for next period are zero
        assertEq(feeDistributor.rewardSupply(period + 1, address(token0)), 0, "Next period should have no rewards");
    }

    function test_concrete() public {
        testFuzz_rewardsWithSixDecimals(664096508764443603, 5061844258394711);
    }

    function test_tripleStutterIncentivize() public {
        uint256 depositAmount = 100e18;
        uint256 incentive1 = 300e18;
        uint256 incentive2 = 200e18;
        uint256 incentive3 = 100e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // First incentive at 1/3 through period
        vm.warp(block.timestamp + 2.33 days);
        vm.startPrank(alice);
        deal(address(token0), alice, incentive1);
        IERC20(address(token0)).approve(address(feeDistributor), incentive1);
        feeDistributor.incentivize(address(token0), incentive1);
        vm.stopPrank();

        // Second incentive at 2/3 through period
        vm.warp(block.timestamp + 2.33 days);
        vm.startPrank(alice);
        deal(address(token0), alice, incentive2);
        IERC20(address(token0)).approve(address(feeDistributor), incentive2);
        feeDistributor.incentivize(address(token0), incentive2);
        vm.stopPrank();

        // Third incentive near end of period
        vm.warp(block.timestamp + 2.33 days);
        vm.startPrank(alice);
        deal(address(token0), alice, incentive3);
        IERC20(address(token0)).approve(address(feeDistributor), incentive3);
        feeDistributor.incentivize(address(token0), incentive3);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 5 days);

        uint256 earned = feeDistributor.earned(address(token0), alice);
        assertEq(earned, incentive1 + incentive2 + incentive3, "Should earn all incentives regardless of timing");
    }

    function test_claimMultipleSkippedPeriods() public {
        uint256 depositAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        uint256 nextTimestamp = block.timestamp + 1 weeks;

        // Setup rewards for 5 periods
        for (uint256 i = 0; i < 5; i++) {
            // Setup initial deposit
            vm.prank(address(mockVoter));
            feeDistributor._deposit(depositAmount, alice);

            // Mock launcher plugin calls to disable launcher functionality
            vm.mockCall(
                address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
            );
            vm.mockCall(
                address(mockLauncherPlugin),
                abi.encodeWithSignature("launcherPluginEnabled(address)"),
                abi.encode(false)
            );

            vm.startPrank(address(feeRecipient));
            deal(address(token0), address(feeRecipient), rewardAmount);
            IERC20(address(token0)).approve(address(feeDistributor), rewardAmount);
            feeDistributor.notifyRewardAmount(address(token0), rewardAmount);
            vm.stopPrank();
            // Move to next period
            vm.warp(nextTimestamp);
            nextTimestamp += 1 weeks;
        }

        // Mock vote module call to allow alice to claim
        vm.mockCall(
            address(mockVoteModule),
            abi.encodeWithSignature("isAdminFor(address,address)", alice, alice),
            abi.encode(true)
        );

        // Claim rewards for each period individually
        uint256 startPeriod = feeDistributor.firstPeriod();
        for (uint256 i = startPeriod + 1; i < startPeriod + 5; i++) {
            uint256 balanceBefore = IERC20(address(token0)).balanceOf(alice);

            vm.prank(alice);
            feeDistributor.getPeriodReward(i, alice, address(token0));

            uint256 balanceAfter = IERC20(address(token0)).balanceOf(alice);
            assertEq(balanceAfter - balanceBefore, rewardAmount, "Should receive full reward amount for period");
        }
    }

    function test_removeNonexistentReward() public {
        vm.prank(address(mockVoter));
        feeDistributor.removeReward(address(token1)); // EnumerableSet does not revert on removing non-existent item
    }

    function test_multipleRewardNotificationsInPeriod() public {
        uint256 depositAmount = 100e18;
        uint256 reward1 = 1000e18;
        uint256 reward2 = 500e18;

        // Setup deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(depositAmount, alice);

        // Multiple notifications in same period
        vm.startPrank(address(feeRecipient));
        deal(address(token0), address(feeRecipient), reward1 + reward2);
        IERC20(address(token0)).approve(address(feeDistributor), reward1 + reward2);

        // Mock launcher plugin calls to disable launcher functionality
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("feeDistToPool(address)"), abi.encode(address(0))
        );
        vm.mockCall(
            address(mockLauncherPlugin), abi.encodeWithSignature("launcherPluginEnabled(address)"), abi.encode(false)
        );
        feeDistributor.notifyRewardAmount(address(token0), reward1);
        feeDistributor.notifyRewardAmount(address(token0), reward2);
        vm.stopPrank();

        // Move to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = feeDistributor.earned(address(token0), alice);
        assertEq(earned, reward1 + reward2, "Should earn combined rewards from multiple notifications");
    }

    function test_multipleDepositsInSamePeriod() public {
        uint256 deposit1 = 100e18;
        uint256 deposit2 = 200e18;

        vm.startPrank(address(mockVoter));
        feeDistributor._deposit(deposit1, alice);
        feeDistributor._deposit(deposit2, alice);
        vm.stopPrank();

        uint256 nextPeriod = feeDistributor.getPeriod() + 1;
        assertEq(
            feeDistributor.userVotes(nextPeriod, alice),
            deposit1 + deposit2,
            "Combined deposits should be reflected in next period"
        );
    }

    function test_multipleWithdrawalsInSamePeriod() public {
        uint256 initialDeposit = 300e18;

        // First deposit
        vm.prank(address(mockVoter));
        feeDistributor._deposit(initialDeposit, alice);

        // Multiple withdrawals
        vm.startPrank(address(mockVoter));
        feeDistributor._withdraw(100e18, alice);
        feeDistributor._withdraw(50e18, alice);
        vm.stopPrank();

        uint256 nextPeriod = feeDistributor.getPeriod() + 1;
        assertEq(feeDistributor.userVotes(nextPeriod, alice), 150e18, "Votes should reflect multiple withdrawals");
    }
}

contract TaxToken is MockERC20 {
    uint256 public constant TAX_RATE = 100; // 1% tax
    uint256 public constant TAX_DENOMINATOR = 10_000;

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * TAX_RATE) / TAX_DENOMINATOR;
        uint256 amountAfterTax = amount - tax;
        super.transfer(address(this), tax);
        return super.transfer(to, amountAfterTax);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * TAX_RATE) / TAX_DENOMINATOR;
        uint256 amountAfterTax = amount - tax;
        super.transferFrom(from, address(this), tax);
        return super.transferFrom(from, to, amountAfterTax);
    }
}
