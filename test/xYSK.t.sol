// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {XYSK} from "contracts/x/XYSK.sol";
import {IXYSK} from "contracts/interfaces/IXYSK.sol";
import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";

import "test/mocks/MockERC20.sol";
import "test/Base.t.sol";

contract XShadowTest is TheTestBase {
	XYSK public xYSK;
	address public mockOperator;

	function setUp() public override {
		super.setUp();
		mockOperator = makeAddr("operator");

		// Mock voter's voteModule call
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("voteModule()"),
			abi.encode(address(mockVoteModule))
		);

		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("minter()"),
			abi.encode(address(mockMinter))
		);

		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("getPeriod()"),
			abi.encode(block.timestamp / 1 weeks)
		);

		xYSK = new XYSK(
			address(ysk),
			address(mockVoter),
			mockOperator,
			address(accessHub),
			address(mockVoteModule),
			address(mockMinter)
		);
	}

	function test_constructor() public view {
		assertEq(address(xYSK.YSK()), address(ysk), "Shadow token address mismatch");
		assertEq(address(xYSK.VOTER()), address(mockVoter), "Voter address mismatch");
		assertEq(xYSK.operator(), mockOperator, "Operator address mismatch");
		assertEq(address(xYSK.ACCESS_HUB()), address(accessHub), "AccessHub address mismatch");
		assertEq(
			address(xYSK.VOTE_MODULE()),
			address(mockVoteModule),
			"VoteModule address mismatch"
		);
	}

	function test_pauseAndUnpause() public {
		// Test pause functionality
		vm.prank(address(accessHub));
		xYSK.pause();
		assertTrue(xYSK.paused(), "Contract should be paused");

		// Try to convert emissions token while paused
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
		xYSK.convertEmissionsToken(100e18);

		// Try to exit while paused
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
		xYSK.exit(100e18);

		// Try to rebase while paused
		vm.prank(address(mockVoter));
		vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
		xYSK.rebase();

		// Try to create vest while paused
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
		xYSK.createVest(100e18);

		// Test unpause functionality
		vm.prank(address(accessHub));
		xYSK.unpause();
		assertFalse(xYSK.paused(), "Contract should be unpaused");

		// Verify functions work after unpause
		vm.startPrank(alice);
		deal(address(ysk), alice, 100e18);
		ysk.approve(address(xYSK), 100e18);
		xYSK.convertEmissionsToken(100e18); // Should not revert
		xYSK.createVest(100e18); // Should not revert
		xYSK.exitVest(0); // Should not revert

		vm.stopPrank();
	}

	function test_createAndExitVestEarly() public {
		uint256 amount = 100e18;

		// Setup
		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);

		// Create vest
		xYSK.createVest(amount);

		// Verify vest creation
		(uint256 vestAmount, uint256 start, uint256 maxEnd, uint256 vestId) = xYSK.vestInfo(
			alice,
			0
		);
		assertEq(vestAmount, amount, "Vest amount mismatch");
		assertEq(start, block.timestamp, "Vest start time mismatch");
		assertEq(maxEnd, block.timestamp + xYSK.MAX_VEST(), "Vest max end time mismatch");
		assertEq(vestId, 0, "Vest ID mismatch");

		// Test early exit (before MIN_VEST)
		xYSK.exitVest(0);
		assertEq(xYSK.balanceOf(alice), amount, "xSHADOW balance mismatch after early exit");
		assertEq(ysk.balanceOf(alice), 0, "Emissions token balance should be 0 after early exit");

		// Vest is the same because exit was cancelled
		(vestAmount, start, maxEnd, vestId) = xYSK.vestInfo(alice, 0);
		assertEq(vestAmount, 0, "Vest amount should be 0 after exit");
		assertEq(start, block.timestamp, "Vest start time incorrect after exit");
		assertEq(
			maxEnd,
			block.timestamp + xYSK.MAX_VEST(),
			"Vest max end time incorrect after exit"
		);
		assertEq(vestId, 0, "Vest ID incorrect after exit");
		vm.stopPrank();
	}

	function testFuzz_exit(uint256 amount, uint256 exitTime) public {
		// Bound inputs to reasonable ranges
		vm.assume(amount > xYSK.BASIS() && amount <= type(uint128).max);
		vm.assume(exitTime >= xYSK.MIN_VEST() && exitTime <= type(uint32).max);

		// Setup initial state
		vm.startPrank(alice);

		// Give alice xSHADOW tokens and setup xSHADOW contract with emissions tokens
		deal(address(xYSK), alice, amount);
		deal(address(ysk), address(xYSK), amount);

		// Create vest starting at timestamp 1
		uint256 start = 1;
		xYSK.createVest(amount);

		// Move time forward to test exit
		vm.warp(block.timestamp + exitTime);

		// Get vest end time for calculations
		(, , uint256 maxEnd, ) = xYSK.vestInfo(alice, 0);

		uint256 expectedReturn;
		uint256 penalty;

		// Calculate expected return amount based on vesting period
		if (block.timestamp >= maxEnd) {
			// If past max vest time, get full amount
			expectedReturn = amount;
		} else {
			// Otherwise calculate partial vest amount
			uint256 SLASHING_PENALTY = xYSK.SLASHING_PENALTY();
			uint256 BASIS = xYSK.BASIS();
			uint256 MAX_VEST = xYSK.MAX_VEST();

			// Get base amount (50% of total)
			uint256 base = (amount * SLASHING_PENALTY) / BASIS;

			// Calculate additional amount earned through linear vesting
			uint256 vestEarned = ((amount *
				(BASIS - SLASHING_PENALTY) *
				(block.timestamp - start)) / MAX_VEST) / BASIS;

			expectedReturn = base + vestEarned;
			penalty = amount - expectedReturn;
		}

		// Exit vest and verify results
		xYSK.exitVest(0);
		vm.stopPrank();

		// Verify balances after exit
		assertEq(xYSK.balanceOf(alice), 0, "xSHADOW balance should be 0 after exit");
		assertEq(ysk.balanceOf(alice), expectedReturn, "Incorrect emissions token return amount");
		assertEq(xYSK.pendingRebase(), penalty, "Incorrect pending rebase amount");

		// Verify vest was deleted
		(uint256 vestAmount, , , ) = xYSK.vestInfo(alice, 0);
		assertEq(vestAmount, 0, "Vest amount should be 0 after exit");
	}

	function testFuzz_rebaseWithMultipleVestings(
		uint256[] memory amounts,
		uint256[] memory exitTimesSeed
	) public {
		// Bound number of vestings between 1 and 32
		bound(amounts.length, 1, 32);

		uint256[] memory exitTimes = new uint256[](amounts.length);
		// Bound amounts and exit times
		for (uint256 i = 0; i < amounts.length; i++) {
			vm.assume(amounts[i] > 0 && amounts[i] <= type(uint128).max);
			if (exitTimesSeed.length <= i) {
				exitTimes[i] = bound(
					uint256(keccak256(abi.encode(amounts[i]))),
					0,
					type(uint32).max
				);
			} else {
				exitTimes[i] = exitTimesSeed[i];
			}
		}

		uint256 totalPendingRebase;
		uint256 totalUserBalance;

		vm.startPrank(alice);

		// Create multiple vestings
		for (uint256 i = 0; i < amounts.length; i++) {
			deal(address(ysk), alice, amounts[i]);
			ysk.approve(address(xYSK), amounts[i]);
			xYSK.convertEmissionsToken(amounts[i]);
			xYSK.createVest(amounts[i]);
		}

		// Exit vestings at different times and accumulate penalties
		for (uint256 i = 0; i < amounts.length; i++) {
			vm.warp(exitTimes[i]);

			uint256 preBalance = ysk.balanceOf(alice);
			xYSK.exitVest(i);
			uint256 postBalance = ysk.balanceOf(alice);

			// Track total emissions received by user
			totalUserBalance += (postBalance - preBalance);

			// Track expected penalties that should go to pending rebase
			uint256 expectedPenalty;
			(, uint256 start, uint256 maxEnd, ) = xYSK.vestInfo(alice, i);

			if (block.timestamp < start + xYSK.MIN_VEST()) {
				// No penalty if exited before MIN_VEST
				expectedPenalty = 0;
			} else if (block.timestamp >= maxEnd) {
				// No penalty if fully vested
				expectedPenalty = 0;
			} else {
				// Calculate linear vesting penalty
				uint256 base = (amounts[i] * xYSK.SLASHING_PENALTY()) / xYSK.BASIS();
				uint256 vestEarned = ((amounts[i] *
					(xYSK.BASIS() - xYSK.SLASHING_PENALTY()) *
					(block.timestamp - start)) / xYSK.MAX_VEST()) / xYSK.BASIS();
				expectedPenalty = amounts[i] - (base + vestEarned);
			}

			totalPendingRebase += expectedPenalty;
		}

		vm.stopPrank();

		// Verify accumulated pending rebase
		assertEq(xYSK.pendingRebase(), totalPendingRebase, "Incorrect total pending rebase");

		// Mock voter period to enable rebase
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("getPeriod()"),
			abi.encode(xYSK.lastDistributedPeriod() + 1)
		);

		// Execute rebase
		vm.prank(xYSK.MINTER());
		xYSK.rebase();

		// Verify rebase distribution based on BASIS threshold
		if (totalPendingRebase >= xYSK.BASIS()) {
			// If above BASIS, should distribute all pending rewards
			assertEq(xYSK.pendingRebase(), 0, "Pending rebase should be 0 after distribution");

			// Verify rebased amount was sent to vote module
			assertEq(
				ysk.balanceOf(address(mockVoteModule)),
				totalPendingRebase,
				"Vote module should have received full rebase amount"
			);
		} else {
			// If below BASIS, pending rebase should remain unchanged
			assertEq(
				xYSK.pendingRebase(),
				totalPendingRebase,
				"Pending rebase should remain unchanged"
			);

			// Vote module should not receive any tokens
			assertEq(
				ysk.balanceOf(address(mockVoteModule)),
				0,
				"Vote module should not receive rebase below BASIS"
			);
		}

		// Verify user received correct amount across all exits
		assertEq(
			ysk.balanceOf(alice),
			totalUserBalance,
			"User should have received correct total amount from all exits"
		);
	}

	function test_exitVestAfterMinVest() public {
		uint256 amount = 100e18;

		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);

		xYSK.createVest(amount);

		// Fast forward past MIN_VEST but before full vest
		vm.warp(block.timestamp + xYSK.MIN_VEST() + 1);

		uint256 preBalance = ysk.balanceOf(alice);
		xYSK.exitVest(0);
		uint256 postBalance = ysk.balanceOf(alice);

		// Should get partial amount based on time elapsed
		uint256 base = (amount * xYSK.SLASHING_PENALTY()) / xYSK.BASIS();
		uint256 vestEarned = ((amount *
			(xYSK.BASIS() - xYSK.SLASHING_PENALTY()) *
			(block.timestamp - (block.timestamp - xYSK.MIN_VEST() - 1))) / xYSK.MAX_VEST()) /
			xYSK.BASIS();
		uint256 expectedAmount = base + vestEarned;
		assertEq(
			postBalance - preBalance,
			expectedAmount,
			"Incorrect partial vest amount received"
		);
		vm.stopPrank();
	}

	function test_revertOnInvalidVestClaim() public {
		uint256 amount = 100e18;

		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);

		xYSK.createVest(amount);

		vm.expectRevert();
		xYSK.exitVest(1); // Invalid vest ID

		vm.stopPrank();
	}

	function test_revertOnExitOtherUsersVest() public {
		uint256 amount = 100e18;

		// Setup Alice's vest
		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);
		xYSK.createVest(amount);
		vm.stopPrank();

		// Bob tries to exit Alice's vest
		vm.prank(bob);
		vm.expectRevert(stdError.indexOOBError);
		xYSK.exitVest(0);
	}

	function test_revertOnZeroAmountConvert() public {
		vm.startPrank(alice);
		vm.expectRevert(abi.encodeWithSignature("ZERO()"));
		xYSK.convertEmissionsToken(0);
		vm.stopPrank();
	}

	function test_revertOnZeroAmountExit() public {
		vm.startPrank(alice);
		vm.expectRevert(abi.encodeWithSignature("ZERO()"));
		xYSK.exit(0);
		vm.stopPrank();
	}

	function test_revertOnExitMoreThanBalance() public {
		uint256 amount = 100e18;

		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);

		// Try to exit more than balance
		vm.expectRevert(
			abi.encodeWithSignature(
				"ERC20InsufficientBalance(address,uint256,uint256)",
				alice,
				amount,
				amount * 2
			)
		);
		xYSK.exit(amount * 2);

		vm.stopPrank();
	}

	function test_revertOnZeroAmountVest() public {
		vm.startPrank(alice);
		vm.expectRevert(abi.encodeWithSignature("ZERO()"));
		xYSK.createVest(0);
		vm.stopPrank();
	}

	function test_exitVestAfterFullVest() public {
		uint256 amount = 100e18;

		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);

		xYSK.createVest(amount);

		// Fast forward past MAX_VEST
		vm.warp(block.timestamp + xYSK.MAX_VEST() + 1);

		uint256 preBalance = ysk.balanceOf(alice);
		xYSK.exitVest(0);
		uint256 postBalance = ysk.balanceOf(alice);

		// Should get full amount
		assertEq(
			postBalance - preBalance,
			amount,
			"Should receive full amount after max vest period"
		);
		vm.stopPrank();
	}

	function testFuzz_convertEmissionsToken(uint256 amount) public {
		vm.assume(amount > 0 && amount <= type(uint128).max);

		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);

		xYSK.convertEmissionsToken(amount);
		vm.stopPrank();

		assertEq(xYSK.balanceOf(alice), amount, "Incorrect xSHADOW balance after conversion");
		assertEq(
			ysk.balanceOf(address(xYSK)),
			amount,
			"Incorrect emissions token balance after conversion"
		);
	}

	function test_multipleVestsPerUser(uint8 numVests, uint256 seed) public {
		uint256 amount = 100e18;
		vm.assume(numVests > 0 && numVests <= 32);
		vm.startPrank(alice);
		deal(address(ysk), alice, amount * numVests);
		ysk.approve(address(xYSK), amount * numVests);
		xYSK.convertEmissionsToken(amount * numVests);
		uint256 startTime = 1;
		// Create multiple vests
		for (uint256 i = 0; i < numVests; i++) {
			xYSK.createVest(amount);
			(uint256 vestAmount, , , uint256 vestId) = xYSK.vestInfo(alice, i);
			assertEq(
				vestAmount,
				amount,
				string.concat("Vest ", vm.toString(i), " amount incorrect")
			);
			assertEq(vestId, i, string.concat("Vest ", vm.toString(i), " ID incorrect"));
		}

		// Randomly select vest to exit and random time
		uint256 vestToExit = uint256(keccak256(abi.encodePacked(seed))) % numVests;
		uint256 randomTime = uint256(keccak256(abi.encodePacked(seed, vestToExit))) %
			xYSK.MAX_VEST();

		// Store initial vest info
		(uint256 exitVestAmount, uint256 exitVestStart, uint256 exitVestMaxEnd, ) = xYSK.vestInfo(
			alice,
			vestToExit
		);
		uint256 preBalance = ysk.balanceOf(alice);

		// Warp to random time and exit vest
		vm.warp(block.timestamp + randomTime);
		xYSK.exitVest(vestToExit);

		// Calculate expected amount based on vesting time
		uint256 expectedAmount;
		uint256 penalty;
		if (block.timestamp < startTime + xYSK.MIN_VEST()) {
			// If before MIN_VEST, should get xYSK back
			expectedAmount = 0;
		} else if (exitVestMaxEnd <= block.timestamp) {
			// If after MAX_VEST, should get full amount
			expectedAmount = exitVestAmount;
		} else {
			// If in between, calculate linear amount
			uint256 base = (exitVestAmount * xYSK.SLASHING_PENALTY()) / xYSK.BASIS();
			uint256 vestEarned = ((exitVestAmount *
				(xYSK.BASIS() - xYSK.SLASHING_PENALTY()) *
				(block.timestamp - exitVestStart)) / xYSK.MAX_VEST()) / xYSK.BASIS();
			expectedAmount = base + vestEarned;
			// Calculate penalty amount that should go to pending rebase
			penalty = exitVestAmount - expectedAmount;
		}

		// Verify exited vest is zeroed
		(uint256 exitVestAmountAfter, , , ) = xYSK.vestInfo(alice, vestToExit);
		assertEq(exitVestAmountAfter, 0, "Exited vest should be zeroed");

		// Verify received correct amount
		uint256 postBalance = ysk.balanceOf(alice);
		if (randomTime < xYSK.MIN_VEST()) {
			assertEq(
				xYSK.balanceOf(alice),
				exitVestAmount,
				"Should receive xYSK back if before MIN_VEST"
			);
		} else {
			assertEq(postBalance - preBalance, expectedAmount, "Incorrect exit amount received");
		}

		// Verify other vests still intact
		for (uint256 i = 0; i < numVests; i++) {
			if (i != vestToExit) {
				(uint256 vestAmount, , , ) = xYSK.vestInfo(alice, i);
				assertEq(
					vestAmount,
					amount,
					string.concat("Vest ", vm.toString(i), " amount changed")
				);
			}
		}

		// Verify pending rebase amount
		assertEq(xYSK.pendingRebase(), penalty, "Incorrect pending rebase amount");
	}

	function test_rebaseAlreadyExecutedInPeriod() public {
		uint256 amount = 100e18;

		// Setup initial vest and exit to generate pending rebase
		vm.startPrank(alice);
		deal(address(ysk), alice, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);
		xYSK.createVest(amount);

		uint256 vestId = 0;
		// uint256 vestStart = xYSK.getVestInfo(alice, vestId).start;

		// Fast forward past MIN_VEST to generate penalty
		console.log("start timestamp", block.timestamp);
		vm.warp(block.timestamp + xYSK.MIN_VEST() + 1 weeks);
		console.log("end timestamp", block.timestamp);
		xYSK.exitVest(vestId);
		vm.stopPrank();

		// Verify we have pending rebase
		uint256 pendingRebase = xYSK.pendingRebase();
		assertTrue(pendingRebase > 0, "Should have pending rebase");

		// Mock voter period
		uint256 currentPeriod = block.timestamp / 1 weeks;
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("getPeriod()"),
			abi.encode(currentPeriod)
		);

		// First rebase should succeed
		vm.startPrank(xYSK.MINTER());
		vm.expectEmit(true, true, false, false);
		emit IXYSK.Rebase(address(xYSK.MINTER()), pendingRebase);
		xYSK.rebase();

		// Create more pending rebase by having another user vest and exit
		vm.startPrank(bob);
		deal(address(ysk), bob, amount);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);
		xYSK.createVest(amount);
		vm.warp(block.timestamp + xYSK.MIN_VEST() + 2 weeks);
		xYSK.exitVest(0);
		vm.stopPrank();
		vm.startPrank(xYSK.MINTER());

		// Verify no Rebase event is emitted on second rebase in same period
		// Start recording logs
		vm.recordLogs();
		xYSK.rebase();

		// Get the recorded logs
		Vm.Log[] memory logs = vm.getRecordedLogs();

		// Check if the Rebase(address,uint256) event was not emitted
		bool testEventEmitted = false;
		for (uint256 i = 0; i < logs.length; i++) {
			// Compare the event signature
			if (logs[i].topics[0] == keccak256("Rebase(address,uint256)")) {
				testEventEmitted = true;
				break;
			}
		}
		assertEq(
			testEventEmitted,
			false,
			"Rebase event should not be emitted on second rebase in same period"
		);

		// Move to next period
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("getPeriod()"),
			abi.encode(currentPeriod + 1)
		);

		// Verify the Rebase event is emitted on the next period
		vm.expectEmit(true, true, false, false);
		emit IXYSK.Rebase(address(xYSK.MINTER()), pendingRebase);
		xYSK.rebase();
	}

	function test_operatorRedeem() public {
		uint256 amount = 100e18;

		// Setup operator balance
		deal(address(ysk), mockOperator, amount);
		vm.startPrank(mockOperator);
		ysk.approve(address(xYSK), amount);
		xYSK.convertEmissionsToken(amount);
		vm.stopPrank();

		uint256 preBalance = ysk.balanceOf(mockOperator);

		// Call operatorRedeem through accessHub
		vm.prank(address(accessHub));
		xYSK.operatorRedeem(amount);

		uint256 postBalance = ysk.balanceOf(mockOperator);
		assertEq(postBalance - preBalance, amount, "Incorrect redemption amount");
		assertEq(
			xYSK.balanceOf(mockOperator),
			0,
			"Operator should have 0 xSHADOW after redemption"
		);
	}

	function test_revertOperatorRedeemUnauthorized() public {
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		xYSK.operatorRedeem(100e18);
	}

	function test_rescueTrappedTokens() public {
		// Create a mock token that gets trapped
		MockERC20 trapped = new MockERC20("Trapped", "TRAP", 18);
		uint256 amount = 1000e18;
		deal(address(trapped), address(xYSK), amount);

		address[] memory tokens = new address[](1);
		tokens[0] = address(trapped);
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = amount;

		uint256 preBalance = trapped.balanceOf(mockOperator);

		vm.prank(address(accessHub));
		xYSK.rescueTrappedTokens(tokens, amounts);

		uint256 postBalance = trapped.balanceOf(mockOperator);
		assertEq(postBalance - preBalance, amount, "Incorrect amount of trapped tokens rescued");
	}

	function test_revertRescueEmissionsToken() public {
		address[] memory tokens = new address[](1);
		tokens[0] = address(ysk);
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 100e18;

		// Test unauthorized access
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		xYSK.rescueTrappedTokens(tokens, amounts);

		// Test can't rescue emissions token
		vm.prank(address(accessHub));
		vm.expectRevert(abi.encodeWithSignature("CANT_RESCUE()"));
		xYSK.rescueTrappedTokens(tokens, amounts);
	}

	function test_migrateOperator() public {
		address newOperator = makeAddr("newOperator");

		vm.prank(address(accessHub));
		xYSK.migrateOperator(newOperator);

		assertEq(xYSK.operator(), newOperator, "Operator not correctly migrated");
	}

	function test_revertMigrateOperatorToSame() public {
		vm.prank(address(accessHub));
		vm.expectRevert(abi.encodeWithSignature("NO_CHANGE()"));
		xYSK.migrateOperator(mockOperator);
	}

	function test_revertMigrateOperatorUnauthorized() public {
		address newOperator = makeAddr("newOperator");

		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		xYSK.migrateOperator(newOperator);
	}

	function test_getBalanceResiding() public {
		uint256 amount = 100e18;
		deal(address(ysk), address(xYSK), amount);

		assertEq(xYSK.getBalanceResiding(), amount, "Incorrect residing balance");
	}

	function test_usersTotalVests() public {
		uint256 amount = 100e18;

		vm.startPrank(alice);
		deal(address(ysk), alice, amount * 2);
		ysk.approve(address(xYSK), amount * 2);
		xYSK.convertEmissionsToken(amount * 2);

		assertEq(xYSK.usersTotalVests(alice), 0, "Initial vest count should be 0");

		xYSK.createVest(amount);
		assertEq(xYSK.usersTotalVests(alice), 1, "Should have 1 vest after creation");

		xYSK.createVest(amount);
		assertEq(xYSK.usersTotalVests(alice), 2, "Should have 2 vests after second creation");
		vm.stopPrank();
	}

	function test_setExemption() public {
		address[] memory exemptees = new address[](2);
		exemptees[0] = alice;
		exemptees[1] = bob;
		bool[] memory statuses = new bool[](2);
		statuses[0] = true;
		statuses[1] = true;

		// Set exemptions
		vm.prank(address(accessHub));
		xYSK.setExemption(exemptees, statuses);

		// Verify exemption status
		assertTrue(xYSK.isExempt(alice), "Alice should be exempt");
		assertTrue(xYSK.isExempt(bob), "Bob should be exempt");

		// Test removing exemption
		statuses[0] = false;
		statuses[1] = false;

		vm.prank(address(accessHub));
		xYSK.setExemption(exemptees, statuses);

		assertFalse(xYSK.isExempt(alice), "Alice should no longer be exempt");
		assertFalse(xYSK.isExempt(bob), "Bob should no longer be exempt");
	}

	function test_setExemptionReverts() public {
		address[] memory exemptees = new address[](2);
		exemptees[0] = alice;
		exemptees[1] = bob;
		bool[] memory statuses = new bool[](1); // Different length than exemptees
		statuses[0] = true;

		// Test revert when arrays have different lengths
		vm.prank(address(accessHub));
		vm.expectRevert(abi.encodeWithSignature("ARRAY_LENGTHS()"));
		xYSK.setExemption(exemptees, statuses);

		// Test revert when not called by governance
		statuses = new bool[](2); // Fix array length
		statuses[0] = true;
		statuses[1] = true;

		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		xYSK.setExemption(exemptees, statuses);
	}

	function test_transferBurning() public {
		uint256 amount = 100e18;

		// Setup
		deal(address(ysk), address(xYSK), amount);
		deal(address(xYSK), alice, amount);

		// Test "burning" through exit
		vm.prank(alice);
		xYSK.exit(amount / 2);

		assertEq(xYSK.balanceOf(alice), amount / 2, "Burn should succeed");
		// Verify penalty went to pendingRebase
		assertEq(
			xYSK.pendingRebase(),
			((amount / 2) * xYSK.SLASHING_PENALTY()) / xYSK.BASIS(),
			"Incorrect pending rebase"
		);
	}

	function test_transferVoteModule() public {
		uint256 amount = 100e18;

		// Setup
		deal(address(xYSK), alice, amount);

		// Test transfer to VOTE_MODULE
		vm.prank(alice);
		xYSK.transfer(address(mockVoteModule), amount / 2);

		assertEq(
			xYSK.balanceOf(address(mockVoteModule)),
			amount / 2,
			"Transfer to VOTE_MODULE should succeed"
		);

		// Test transfer from VOTE_MODULE
		vm.prank(address(mockVoteModule));
		xYSK.transfer(alice, amount / 4);

		assertEq(
			xYSK.balanceOf(alice),
			(amount * 3) / 4,
			"Transfer from VOTE_MODULE should succeed"
		);
	}

	function test_transferFromExempt() public {
		uint256 amount = 100e18;

		// Setup
		deal(address(xYSK), alice, amount);

		// Set alice as exempt
		address[] memory exemptees = new address[](1);
		exemptees[0] = alice;
		bool[] memory statuses = new bool[](1);
		statuses[0] = true;

		vm.prank(address(accessHub));
		xYSK.setExemption(exemptees, statuses);

		// Mock voter returns false
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isGauge(address)"),
			abi.encode(false)
		);
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isFeeDistributor(address)"),
			abi.encode(false)
		);

		// Test exempt transfer
		vm.prank(alice);
		xYSK.transfer(bob, amount / 2);

		assertEq(xYSK.balanceOf(bob), amount / 2, "Transfer from exempt address should succeed");
	}

	function test_transferFromNonExempt() public {
		uint256 amount = 100e18;

		// Setup
		deal(address(xYSK), alice, amount);

		// Mock voter returns false
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isGauge(address)"),
			abi.encode(false)
		);
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isFeeDistributor(address)"),
			abi.encode(false)
		);

		// Test non-exempt transfer (should fail)
		vm.prank(bob);
		vm.expectRevert(abi.encodeWithSignature("NOT_WHITELISTED(address)", bob));
		xYSK.transfer(alice, amount / 4);
	}

	function test_transfer_fromGauge() public {
		uint256 amount = 100e18;
		address fakeGauge = makeAddr("fakeGauge");

		// Setup
		deal(address(xYSK), fakeGauge, amount);

		// Mock voter to recognize gauge
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isGauge(address)"),
			abi.encode(true)
		);

		// Test gauge transfer
		vm.prank(fakeGauge);
		xYSK.transfer(alice, amount);

		assertTrue(xYSK.isExempt(fakeGauge), "Gauge should be auto-added to exempt");
		assertEq(xYSK.balanceOf(alice), amount, "Transfer from gauge should succeed");
	}

	function test_transfer_fromFeeDistributor() public {
		uint256 amount = 100e18;
		address fakeFeeDistributor = makeAddr("fakeFeeDistributor");
		vm.label(fakeFeeDistributor, "fakeFeeDistributor");

		// Setup
		deal(address(xYSK), fakeFeeDistributor, amount);

		// Mock voter to recognize fee distributor
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isGauge(address)"),
			abi.encode(false)
		);
		vm.mockCall(
			address(mockVoter),
			abi.encodeWithSignature("isFeeDistributor(address)"),
			abi.encode(true)
		);

		// Test fee distributor transfer
		vm.prank(fakeFeeDistributor);
		xYSK.transfer(alice, amount);

		assertTrue(
			xYSK.isExempt(fakeFeeDistributor),
			"Fee distributor should be auto-added to exempt"
		);
		assertEq(xYSK.balanceOf(alice), amount, "Transfer from fee distributor should succeed");
	}
}
