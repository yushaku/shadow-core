// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {VoteModule} from "../../contracts/VoteModule.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {XShadow} from "../../contracts/xShadow/XShadow.sol";
import {Voter} from "../../contracts/Voter.sol";
import {IVoter} from "../../contracts/interfaces/IVoter.sol";
import {IVoteModule} from "../../contracts/interfaces/IVoteModule.sol";
import {console} from "forge-std/console.sol";

contract VoteModuleTest is TestBase {
    VoteModule public voteModule;
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 public constant PRECISION = 1e18;
    XShadow public xShadow;
    Voter public voter;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event NotifyReward(address indexed from, uint256 reward);
    event ClaimRewards(address indexed user, uint256 reward);
    event Delegate(address indexed owner, address indexed delegatee, bool isAdded);
    event SetAdmin(address indexed owner, address indexed admin, bool isAdded);
    event ExemptedFromCooldown(address indexed user, bool exempt);
    event NewDuration(uint256 oldDuration, uint256 newDuration);
    event NewCooldown(uint256 oldCooldown, uint256 newCooldown);

    function setUp() public override {
        super.setUp();

        voter = new Voter(address(accessHub));

        // Deploy VoteModule
        voteModule = new VoteModule();

        // Deploy XShadow
        xShadow = new XShadow(
            address(shadow),
            address(voter),
            address(TREASURY),
            address(accessHub),
            address(voteModule),
            address(mockMinter)
        );

        vm.prank(address(accessHub));
        voter.initialize(
            address(shadow),
            address(0),
            address(0),
            address(0),
            address(mockMinter),
            address(0),
            address(xShadow),
            address(0),
            address(0),
            address(0),
            address(feeRecipientFactory),
            address(voteModule),
            address(0)
        );

        voteModule.initialize(address(xShadow), address(voter), address(accessHub));

        // Setup initial token balances
        deal(address(xShadow), alice, INITIAL_SUPPLY);
        deal(address(xShadow), bob, INITIAL_SUPPLY);
        deal(address(xShadow), carol, INITIAL_SUPPLY);

        // Approve VoteModule to spend xShadow
        vm.prank(alice);
        xShadow.approve(address(voteModule), type(uint256).max);
        vm.prank(bob);
        xShadow.approve(address(voteModule), type(uint256).max);
        vm.prank(carol);
        xShadow.approve(address(voteModule), type(uint256).max);
    }

    function test_initialization() public view {
        assertEq(address(voteModule.xShadow()), address(xShadow), "xShadow address mismatch");
        assertEq(address(voteModule.voter()), address(voter), "voter address mismatch");
        assertEq(address(voteModule.accessHub()), address(accessHub), "accessHub address mismatch");
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        deal(address(xShadow), alice, amount);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, amount);

        vm.prank(alice);
        voteModule.deposit(amount);

        assertEq(voteModule.balanceOf(alice), amount, "Incorrect balance after deposit");
        assertEq(voteModule.totalSupply(), amount, "Incorrect total supply after deposit");
    }

    function test_depositZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ZERO_AMOUNT()")); // Actual error message from contract
        voteModule.deposit(0);
    }

    function test_depositDuringCooldown() public {
        // First deposit to trigger cooldown
        vm.prank(alice);
        voteModule.deposit(1e18);

        // Mock xShadow notifying rewards to start cooldown
        vm.startPrank(address(xShadow));
        deal(address(shadow), address(xShadow), 100e18);
        shadow.approve(address(voteModule), 100e18);

        // Test NotifyReward event emission
        vm.expectEmit(true, false, false, true);
        emit NotifyReward(address(xShadow), 100e18);
        voteModule.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Try to deposit during cooldown
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("COOLDOWN_ACTIVE()"));
        voteModule.deposit(1e18);
    }

    function test_depositAll() public {
        uint256 balance = xShadow.balanceOf(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, balance);
        vm.prank(alice);
        voteModule.depositAll();

        assertEq(voteModule.balanceOf(alice), balance, "Incorrect balance after depositAll");
        assertEq(voteModule.totalSupply(), balance, "Incorrect total supply after depositAll");
        assertEq(xShadow.balanceOf(address(alice)), 0, "User balance not zero after depositAll");
    }

    function test_withdraw() public {
        // First deposit
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        voteModule.deposit(depositAmount);

        // Wait for cooldown to pass
        vm.warp(block.timestamp + 13 hours);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, depositAmount);

        vm.prank(alice);
        voteModule.withdraw(depositAmount);

        assertEq(voteModule.balanceOf(alice), 0, "Balance not zero after withdraw");
        assertEq(voteModule.totalSupply(), 0, "Total supply not zero after withdraw");
    }

    function test_withdrawAll() public {
        // First deposit
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        voteModule.deposit(depositAmount);

        // Wait for cooldown to pass
        vm.warp(block.timestamp + 13 hours);

        vm.prank(alice);
        voteModule.withdrawAll();

        assertEq(voteModule.balanceOf(alice), 0, "Balance not zero after withdrawAll");
        assertEq(voteModule.totalSupply(), 0, "Total supply not zero after withdrawAll");
    }

    function testFuzz_depositAndWithdraw(uint256 amount) public {
        // Bound amount to reasonable values and ensure non-zero
        amount = bound(amount, 1, type(uint128).max);

        // Give alice enough xShadow
        deal(address(xShadow), alice, amount);

        vm.startPrank(alice);
        xShadow.approve(address(voteModule), amount);

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, amount);
        voteModule.deposit(amount);
        vm.stopPrank();

        assertEq(voteModule.balanceOf(alice), amount, "Incorrect balance after deposit");
        assertEq(voteModule.totalSupply(), amount, "Incorrect total supply after deposit");
        assertEq(xShadow.balanceOf(alice), 0, "User balance not zero after deposit");

        // Test that we can withdraw the deposited amount
        vm.warp(block.timestamp + 13 hours); // Wait for cooldown

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, amount);
        voteModule.withdraw(amount);

        assertEq(voteModule.balanceOf(alice), 0, "Balance not zero after withdraw");
        assertEq(voteModule.totalSupply(), 0, "Total supply not zero after withdraw");
        assertEq(xShadow.balanceOf(alice), amount, "Incorrect balance after withdraw");
    }

    function test_delegation() public {
        vm.startPrank(alice);

        // Test adding delegate
        voteModule.delegate(bob);
        assertTrue(voteModule.isDelegateFor(bob, alice), "Bob should be delegate for Alice");

        // Test removing delegate
        voteModule.delegate(address(0));
        assertFalse(voteModule.isDelegateFor(bob, alice), "Bob should no longer be delegate for Alice");

        vm.stopPrank();
    }

    function test_adminManagement() public {
        vm.startPrank(alice);

        // Test adding admin
        voteModule.setAdmin(bob);
        assertTrue(voteModule.isAdminFor(bob, alice), "Bob should be admin for Alice");

        // Test removing admin
        voteModule.setAdmin(address(0));
        assertFalse(voteModule.isAdminFor(bob, alice), "Bob should no longer be admin for Alice");

        vm.stopPrank();
    }

    function test_cooldownExemption() public {
        // Test ExemptedFromCooldown event emission
        vm.startPrank(address(accessHub));
        vm.expectEmit(true, false, false, true);
        emit ExemptedFromCooldown(alice, true);
        voteModule.setCooldownExemption(alice, true);
        vm.stopPrank();

        // Should be able to deposit during cooldown
        deal(address(shadow), address(xShadow), 100e18);

        vm.startPrank(address(xShadow));
        shadow.approve(address(voteModule), 100e18);
        vm.expectEmit(true, true, true, true);
        emit IVoteModule.NotifyReward(address(xShadow), 100e18);
        voteModule.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Test Deposit event emission
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1e18);
        voteModule.deposit(1e18); // Should not revert
    }

    function test_rewardDistribution() public {
        // Setup initial deposit
        vm.prank(alice);
        voteModule.deposit(100e18);

        // Notify rewards
        vm.startPrank(address(xShadow));
        deal(address(shadow), address(xShadow), 1000e18);
        shadow.approve(address(voteModule), 1000e18);
        voteModule.notifyRewardAmount(1000e18);
        vm.stopPrank();

        // Wait for rewards to accrue
        vm.warp(block.timestamp + 15 minutes);

        // Calculate expected rewards
        uint256 timeElapsed = 15 minutes;
        uint256 rewardRate = voteModule.rewardRate();
        uint256 expectedRewards = (timeElapsed * rewardRate);

        // Check earned rewards
        uint256 earned = voteModule.earned(alice);
        assertApproxEqRel(earned, expectedRewards, 0.01e18, "Earned rewards do not match expected amount");

        // Test ClaimRewards event emission
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ClaimRewards(alice, earned);
        voteModule.getReward();
    }

    function test_durationAndCooldownUpdates() public {
        // Test duration bounds
        vm.startPrank(address(accessHub));

        // Duration should be > 0
        vm.expectRevert();
        voteModule.setNewDuration(0);

        // Duration should be <= 7 days
        vm.expectRevert();
        voteModule.setNewDuration(8 days);

        // Valid duration should work
        uint256 oldDuration = voteModule.duration();
        uint256 newDuration = 1 hours;
        vm.expectEmit(false, false, false, true);
        emit NewDuration(oldDuration, newDuration);
        voteModule.setNewDuration(newDuration);
        assertEq(voteModule.duration(), newDuration, "Duration not updated correctly");

        // Test cooldown bounds
        // Cooldown should be <= 7 days
        vm.expectRevert();
        voteModule.setNewCooldown(8 days);

        // Valid cooldown should work
        uint256 oldCooldown = voteModule.cooldown();
        uint256 newCooldown = 24 hours;
        vm.expectEmit(false, false, false, true);
        emit NewCooldown(oldCooldown, newCooldown);
        voteModule.setNewCooldown(newCooldown);
        assertEq(voteModule.cooldown(), newCooldown, "Cooldown not updated correctly");

        vm.stopPrank();
    }

    function test_onlyAccessHubCanSetCooldownExemption() public {
        // Try to call setCooldownExemption from non-accessHub address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB()"));
        voteModule.setCooldownExemption(bob, true);

        // Should work when called by accessHub
        vm.prank(address(accessHub));
        voteModule.setCooldownExemption(bob, true);
        assertTrue(voteModule.cooldownExempt(bob), "Bob should be cooldown exempt");
    }

    function test_onlyAccessHubCanSetNewDuration() public {
        uint256 newDuration = 1 hours;

        // Try to call setNewDuration from non-accessHub address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB()"));
        voteModule.setNewDuration(newDuration);

        // Should work when called by accessHub
        vm.prank(address(accessHub));
        voteModule.setNewDuration(newDuration);
        assertEq(voteModule.duration(), newDuration, "Duration not updated correctly");
    }

    function test_onlyAccessHubCanSetNewCooldown() public {
        uint256 newCooldown = 24 hours;

        // Try to call setNewCooldown from non-accessHub address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB()"));
        voteModule.setNewCooldown(newCooldown);

        // Should work when called by accessHub
        vm.prank(address(accessHub));
        voteModule.setNewCooldown(newCooldown);
        assertEq(voteModule.cooldown(), newCooldown, "Cooldown not updated correctly");
    }

    function testFuzz_notifyRewardOverTime(uint256 depositAmount, uint256 rewardAmount, uint256 timeElapsed) public {
        vm.warp(1734823964);
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1e18, type(uint112).max);
        rewardAmount = bound(rewardAmount, 1e18, type(uint112).max);
        timeElapsed = bound(timeElapsed, 1 minutes, 14 days);

        // Setup initial deposit for alice
        deal(address(xShadow), alice, depositAmount);
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), depositAmount);
        voteModule.deposit(depositAmount);
        vm.stopPrank();

        // Notify rewards
        vm.startPrank(address(xShadow));
        deal(address(shadow), address(xShadow), rewardAmount);
        shadow.approve(address(voteModule), rewardAmount);

        vm.expectEmit(true, true, true, true);
        emit NotifyReward(address(xShadow), rewardAmount);
        voteModule.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Record initial state
        uint256 rewardRate = voteModule.rewardRate();
        uint256 periodFinish = voteModule.periodFinish();
        // Advance time
        vm.warp(block.timestamp + timeElapsed);

        // Calculate expected rewards
        uint256 expectedReward;
        if (block.timestamp >= periodFinish) {
            // If we're past periodFinish, all rewards should be available
            timeElapsed = 1800;
        }

        expectedReward = (timeElapsed * rewardRate);
        // Check earned rewards
        uint256 actualEarned = voteModule.earned(alice);

        // Allow for small rounding differences (1 wei per token)
        assertApproxEqRel(
            actualEarned,
            expectedReward,
            0.001e18, // 1% tolerance
            "Earned rewards do not match expected rewards within tolerance"
        );

        // Claim rewards
        uint256 preBalance = xShadow.balanceOf(alice);

        vm.prank(alice);
        voteModule.getReward();

        uint256 postBalance = xShadow.balanceOf(alice);
        uint256 actualReward = postBalance - preBalance;

        // Verify claimed amount matches earned amount (within rounding)
        assertApproxEqRel(
            actualReward,
            actualEarned,
            0.000001e18, // 0.0001% tolerance
            "Claimed rewards do not match earned rewards within tolerance"
        );
    }

    function testFuzz_notifyRewardWithMultipleDepositors(
        uint256 deposit1,
        uint256 deposit2,
        uint256 deposit3,
        uint256 rewardAmount,
        uint256 timeElapsed
    ) public {
        vm.warp(1734823964);

        // Bound inputs to reasonable values
        deposit1 = bound(deposit1, 1e18, type(uint112).max / 3);
        deposit2 = bound(deposit2, 1e18, type(uint112).max / 3);
        deposit3 = bound(deposit3, 1e18, type(uint112).max / 3);
        rewardAmount = bound(rewardAmount, 1e18, type(uint112).max);
        timeElapsed = bound(timeElapsed, 1 minutes, 14 days);

        // Setup deposits for alice, bob, and carol
        deal(address(xShadow), alice, deposit1);
        deal(address(xShadow), bob, deposit2);
        deal(address(xShadow), carol, deposit3);

        // Alice deposits
        vm.startPrank(alice);
        xShadow.approve(address(voteModule), deposit1);
        voteModule.deposit(deposit1);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        xShadow.approve(address(voteModule), deposit2);
        voteModule.deposit(deposit2);
        vm.stopPrank();

        // Carol deposits
        vm.startPrank(carol);
        xShadow.approve(address(voteModule), deposit3);
        voteModule.deposit(deposit3);
        vm.stopPrank();

        uint256 totalDeposits = deposit1 + deposit2 + deposit3;

        // Notify rewards
        vm.startPrank(address(xShadow));
        deal(address(shadow), address(xShadow), rewardAmount);
        shadow.approve(address(voteModule), rewardAmount);
        voteModule.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Record initial state
        uint256 rewardRate = voteModule.rewardRate();
        uint256 periodFinish = voteModule.periodFinish();

        // Advance time
        vm.warp(block.timestamp + timeElapsed);

        // Calculate expected rewards
        uint256 timeForRewards = timeElapsed;
        if (block.timestamp >= periodFinish) {
            timeForRewards = 1800; // 30 minutes in seconds
        }

        uint256 totalExpectedRewards = timeForRewards * rewardRate;

        // Calculate expected rewards for each user based on their proportion of total deposits
        uint256 expectedRewardAlice = (totalExpectedRewards * deposit1) / totalDeposits;
        uint256 expectedRewardBob = (totalExpectedRewards * deposit2) / totalDeposits;
        uint256 expectedRewardCarol = (totalExpectedRewards * deposit3) / totalDeposits;

        // Check earned rewards
        uint256 actualEarnedAlice = voteModule.earned(alice);
        uint256 actualEarnedBob = voteModule.earned(bob);
        uint256 actualEarnedCarol = voteModule.earned(carol);

        // Verify rewards with 1% tolerance
        assertApproxEqRel(
            actualEarnedAlice, expectedRewardAlice, 0.01e18, "Alice's earned rewards do not match expected"
        );
        assertApproxEqRel(actualEarnedBob, expectedRewardBob, 0.01e18, "Bob's earned rewards do not match expected");
        assertApproxEqRel(
            actualEarnedCarol, expectedRewardCarol, 0.01e18, "Carol's earned rewards do not match expected"
        );

        // Claim rewards for all users and verify
        vm.prank(alice);
        voteModule.getReward();
        vm.prank(bob);
        voteModule.getReward();
        vm.prank(carol);
        voteModule.getReward();

        // Verify final balances
        assertApproxEqRel(
            xShadow.balanceOf(alice),
            actualEarnedAlice,
            0.000001e18,
            "Alice's claimed rewards do not match earned amount"
        );
        assertApproxEqRel(
            xShadow.balanceOf(bob), actualEarnedBob, 0.000001e18, "Bob's claimed rewards do not match earned amount"
        );
        assertApproxEqRel(
            xShadow.balanceOf(carol),
            actualEarnedCarol,
            0.000001e18,
            "Carol's claimed rewards do not match earned amount"
        );
    }
}
