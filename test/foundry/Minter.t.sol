// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {Minter} from "../../contracts/Minter.sol";
import {XShadow} from "../../contracts/xShadow/XShadow.sol";
import {Shadow} from "../../contracts/Shadow.sol";
import {IMinter} from "../../contracts/interfaces/IMinter.sol";
import {MockVoter} from "./TestBase.sol";
import {IVoter} from "../../contracts/interfaces/IVoter.sol";
import {console} from "forge-std/console.sol";

contract MockXShadowRevertRebase {
    function rebase() external pure {
        revert("Rebase failed");
    }
}

contract MinterTest is TestBase {
    Minter public realMinter;
    XShadow public xshadow;
    uint256 constant INITIAL_WEEKLY_EMISSIONS = 100_000 * 1e18;
    uint256 constant INITIAL_MULTIPLIER = 10_000; // 100%

    function setUp() public override {
        super.setUp();
        vm.warp(100 weeks);

        // Deploy real minter and xshadow
        realMinter = new Minter(address(accessHub), alice);
        shadow = new Shadow(address(realMinter));
        mockVoter =
            new MockVoter(makeAddr("launcherPlugin"), makeAddr("voteModule"), address(shadow), address(realMinter));

        xshadow = new XShadow(
            address(shadow),
            address(mockVoter),
            TREASURY,
            address(accessHub),
            address(mockVoteModule),
            address(realMinter)
        );

        // Setup permissions
        vm.startPrank(alice);
        realMinter.kickoff(
            address(shadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );
        vm.stopPrank();

        vm.label(address(realMinter), "realMinter");
        vm.label(address(shadow), "shadow");
        vm.label(address(xshadow), "xshadow");
    }

    function test_kickoff() public {
        Minter newMinter = new Minter(address(accessHub), alice);
        Shadow newShadow = new Shadow(address(newMinter));
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit IMinter.SetVoter(address(mockVoter));
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );
        vm.stopPrank();

        assertEq(newMinter.weeklyEmissions(), INITIAL_WEEKLY_EMISSIONS, "Weekly emissions should match initial value");
        assertEq(newMinter.emissionsMultiplier(), INITIAL_MULTIPLIER, "Emissions multiplier should match initial value");
        assertEq(address(newMinter.shadow()), address(newShadow), "Shadow token address should match");
        assertEq(newMinter.xShadow(), address(xshadow), "xShadow address should match");
        assertEq(newMinter.voter(), address(mockVoter), "Voter address should match");
        assertEq(newShadow.balanceOf(alice), realMinter.INITIAL_SUPPLY(), "Initial supply should be minted to alice");
    }

    function test_kickoffRevert() public {
        Minter newMinter = new Minter(address(accessHub), alice);
        Shadow newShadow = new Shadow(address(newMinter));
        // Test unauthorized
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );

        // Test already started
        vm.startPrank(alice);
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );

        vm.expectRevert(IMinter.STARTED.selector);
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );
        vm.stopPrank();
    }

    function test_startEmissions() public {
        vm.prank(alice);
        realMinter.startEmissions();

        assertEq(realMinter.firstPeriod(), realMinter.getPeriod(), "First period should match current period");
        assertEq(realMinter.activePeriod(), realMinter.getPeriod(), "Active period should match current period");
        assertEq(
            realMinter.lastMultiplierUpdate(),
            realMinter.getPeriod() - 1,
            "Last multiplier update should be previous period"
        );
        assertEq(
            shadow.balanceOf(alice),
            realMinter.INITIAL_SUPPLY() + INITIAL_WEEKLY_EMISSIONS,
            "Balance should include initial supply and emissions"
        );
    }

    function test_updatePeriod() public {
        // Start emissions
        vm.prank(alice);
        realMinter.startEmissions();

        // Warp to next period
        vm.warp(block.timestamp + 1 weeks);

        uint256 balanceBefore = shadow.balanceOf(address(mockVoter));
        realMinter.updatePeriod();

        assertEq(realMinter.activePeriod(), realMinter.getPeriod(), "Active period should match current period");
        assertGt(shadow.balanceOf(address(mockVoter)), balanceBefore, "Balance should increase after update");
    }

    function test_updateEmissionsMultiplier() public {
        // Start emissions
        vm.prank(alice);
        realMinter.startEmissions();

        uint256 newMultiplier = 11_000; // 110%

        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IMinter.EmissionsMultiplierUpdated(newMultiplier);
        realMinter.updateEmissionsMultiplier(newMultiplier);

        assertEq(realMinter.emissionsMultiplier(), newMultiplier, "Emissions multiplier should be updated");
    }

    function test_updateEmissionsMultiplierRevert() public {
        // Start emissions
        vm.prank(alice);
        realMinter.startEmissions();

        // Test unauthorized
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        realMinter.updateEmissionsMultiplier(11_000);

        // Test same period
        vm.startPrank(address(accessHub));
        realMinter.updateEmissionsMultiplier(11_000);

        vm.expectRevert(IMinter.SAME_PERIOD.selector);
        realMinter.updateEmissionsMultiplier(12_000);
        vm.stopPrank();

        // Test too high deviation
        vm.warp(block.timestamp + 1 weeks);
        realMinter.updatePeriod();
        vm.prank(address(accessHub));
        vm.expectRevert(IMinter.TOO_HIGH.selector);
        realMinter.updateEmissionsMultiplier(14_000); // 40% change
    }

    function test_calculateWeeklyEmissions() public {
        vm.prank(alice);
        realMinter.startEmissions();
        // Test normal case - should match initial weekly emissions
        uint256 emissions = realMinter.calculateWeeklyEmissions();
        assertEq(emissions, INITIAL_WEEKLY_EMISSIONS, "Emissions should match initial weekly emissions");

        // Test with multiplier increase
        vm.startPrank(address(accessHub));
        vm.warp(block.timestamp + 1 weeks); // Move to next period
        realMinter.updateEmissionsMultiplier(11_000); // 110%
        vm.stopPrank();

        emissions = realMinter.calculateWeeklyEmissions();
        assertEq(
            emissions, (INITIAL_WEEKLY_EMISSIONS * 11_000) / 10_000, "Emissions should reflect multiplier increase"
        );

        // Test max supply cap
        vm.startPrank(address(realMinter));
        shadow.mint(address(this), realMinter.MAX_SUPPLY() - shadow.totalSupply() - 100e18); // Leave room for only 100 tokens
        vm.stopPrank();

        emissions = realMinter.calculateWeeklyEmissions();
        assertEq(emissions, 100e18, "Emissions should be capped at remaining supply");
    }

    function test_calculateWeeklyEmissionsOverMaxSupply() public {
        vm.prank(alice);
        realMinter.startEmissions();

        // Mint up to just below max supply
        uint256 remainingToMax = realMinter.MAX_SUPPLY() - shadow.totalSupply();
        uint256 mintUpTo = remainingToMax - (INITIAL_WEEKLY_EMISSIONS / 2); // Leave less than weekly emissions remaining

        vm.startPrank(address(realMinter));
        shadow.mint(address(this), mintUpTo);
        vm.stopPrank();

        // Calculate next emissions
        uint256 emissions = realMinter.calculateWeeklyEmissions();

        // Should only mint remaining amount to max supply
        assertEq(
            emissions, realMinter.MAX_SUPPLY() - shadow.totalSupply(), "Emissions should be limited to remaining supply"
        );
        assertEq(emissions, INITIAL_WEEKLY_EMISSIONS / 2, "Emissions should be half of weekly emissions");
    }

    function test_getEpoch() public {
        // Test epoch 0
        vm.prank(alice);
        realMinter.startEmissions();
        assertEq(realMinter.getEpoch(), 0, "Initial epoch should be 0");

        // Test epoch 1
        vm.warp(block.timestamp + 1 weeks);
        assertEq(realMinter.getEpoch(), 1, "Epoch should increment after one week");
    }

    function test_kickoffZeroAddressChecks() public {
        Minter newMinter = new Minter(address(accessHub), alice);
        Shadow newShadow = new Shadow(address(newMinter));

        vm.startPrank(alice);

        // Test zero address voter
        vm.expectRevert(IMinter.INVALID_CONTRACT.selector);
        newMinter.kickoff(
            address(newShadow), address(0), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );

        // Test zero address emissions token
        vm.expectRevert(IMinter.INVALID_CONTRACT.selector);
        newMinter.kickoff(
            address(0), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );

        // Test zero address xShadow
        vm.expectRevert(IMinter.INVALID_CONTRACT.selector);
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(0)
        );

        vm.stopPrank();
    }

    function test_startEmissionsRevert() public {
        // Test unauthorized
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        realMinter.startEmissions();

        // Test already started
        vm.startPrank(alice);
        realMinter.startEmissions();

        vm.expectRevert(IMinter.STARTED.selector);
        realMinter.startEmissions();
        vm.stopPrank();
    }

    function test_updatePeriodRevertNotStarted() public {
        vm.expectRevert(IMinter.EMISSIONS_NOT_STARTED.selector);
        realMinter.updatePeriod();
    }

    function test_updatePeriodWithFailedRebase() public {
        vm.startPrank(alice);
        realMinter.startEmissions();
        vm.stopPrank();

        // Warp to next period
        vm.warp(block.timestamp + 1 weeks);

        // Mock xShadow to revert on rebase() call
        vm.mockCallRevert(address(xshadow), abi.encodeWithSignature("rebase()"), "rebase failed");
        // Update period should emit RebaseUnsuccessful but not revert
        vm.expectEmit(true, true, true, true);
        emit IMinter.RebaseUnsuccessful(block.timestamp, realMinter.getPeriod());
        realMinter.updatePeriod();
    }

    function test_updatePeriodWithZeroEmissions() public {
        vm.startPrank(alice);
        realMinter.startEmissions();
        vm.stopPrank();

        uint256 multiplier = INITIAL_MULTIPLIER;

        uint256 i = 1;
        while (multiplier > 0) {
            // Calculate next multiplier with 20% reduction
            uint256 nextMultiplier = multiplier * 8000 / realMinter.BASIS(); // Reduce by 20%
            vm.warp(block.timestamp + (i * 1 weeks));
            realMinter.updatePeriod();
            // Update to new multiplier
            vm.prank(address(accessHub));
            realMinter.updateEmissionsMultiplier(nextMultiplier);

            // Increment for next period warp
            i++;

            multiplier = nextMultiplier;
        }

        // Verify final emissions are 0
        uint256 balanceBefore = shadow.balanceOf(address(mockVoter));
        realMinter.updatePeriod();
        assertEq(shadow.balanceOf(address(mockVoter)), balanceBefore, "Balance should not change when emissions are 0");
    }

    function test_updateEmissionsMultiplierNoChange() public {
        vm.prank(alice);
        realMinter.startEmissions();

        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(address(accessHub));
        vm.expectRevert(IMinter.NO_CHANGE.selector);
        realMinter.updateEmissionsMultiplier(INITIAL_MULTIPLIER);
        vm.stopPrank();
    }

    function test_emitMintOnUpdatePeriod() public {
        vm.prank(alice);
        realMinter.startEmissions();

        vm.warp(block.timestamp + 1 weeks);

        vm.expectEmit(true, true, true, true);
        emit IMinter.Mint(address(this), INITIAL_WEEKLY_EMISSIONS);
        realMinter.updatePeriod();
    }

    function test_onlyGovernanceCanUpdateMultiplier() public {
        vm.prank(alice);
        realMinter.startEmissions();

        vm.warp(block.timestamp + 1 weeks);
        realMinter.updatePeriod();

        // Test that non-governance address cannot update multiplier
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        realMinter.updateEmissionsMultiplier(11_000);

        // Test that governance can update multiplier
        vm.prank(address(accessHub));
        realMinter.updateEmissionsMultiplier(11_000);
        assertEq(realMinter.emissionsMultiplier(), 11_000, "Multiplier should be updated by governance");
    }

    function test_onlyOperatorCanStartEmissions() public {
        // Test that non-operator cannot start emissions
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        realMinter.startEmissions();

        // Test that operator can start emissions
        vm.prank(alice);
        realMinter.startEmissions();
        assertEq(realMinter.firstPeriod(), realMinter.getPeriod(), "First period should be set by operator");
    }

    function test_onlyOperatorCanKickoff() public {
        Minter newMinter = new Minter(address(accessHub), alice);
        Shadow newShadow = new Shadow(address(newMinter));

        // Test that non-operator cannot kickoff
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVoter.NOT_AUTHORIZED.selector, bob));
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );

        // Test that operator can kickoff
        vm.prank(alice);
        newMinter.kickoff(
            address(newShadow), address(mockVoter), INITIAL_WEEKLY_EMISSIONS, INITIAL_MULTIPLIER, address(xshadow)
        );
        assertEq(address(newMinter.shadow()), address(newShadow), "Shadow token should be set by operator");
    }

    function test_maxSupplyBoundary() public {
        vm.prank(alice);
        realMinter.startEmissions();

        // Mint up to exactly MAX_SUPPLY - weeklyEmissions
        uint256 remainingToMax = realMinter.MAX_SUPPLY() - shadow.totalSupply();
        uint256 mintUpTo = remainingToMax - INITIAL_WEEKLY_EMISSIONS;

        vm.startPrank(address(realMinter));
        shadow.mint(address(this), mintUpTo);
        vm.stopPrank();

        // Verify next emissions are exactly weeklyEmissions
        uint256 emissions = realMinter.calculateWeeklyEmissions();
        assertEq(emissions, INITIAL_WEEKLY_EMISSIONS, "Should emit full weekly emissions when just under max supply");

        // Mint 1 more token
        vm.prank(address(realMinter));
        shadow.mint(address(this), 1);

        // Verify emissions are reduced accordingly
        emissions = realMinter.calculateWeeklyEmissions();
        assertEq(emissions, INITIAL_WEEKLY_EMISSIONS - 1, "Should reduce emissions to respect max supply");
    }

    function test_emissionsMultiplierBoundaries() public {
        vm.prank(alice);
        realMinter.startEmissions();

        vm.warp(block.timestamp + 1 weeks);
        realMinter.updatePeriod();

        // Test maximum allowed decrease (20%)
        vm.prank(address(accessHub));
        realMinter.updateEmissionsMultiplier(8_000); // 80% of initial

        vm.warp(block.timestamp + 2 weeks);
        realMinter.updatePeriod();

        // Test maximum allowed increase (20%)
        vm.prank(address(accessHub));
        realMinter.updateEmissionsMultiplier(9_600); // 120% of 8_000

        vm.warp(block.timestamp + 3 weeks);
        realMinter.updatePeriod();

        // Verify both changes were successful
        assertEq(realMinter.emissionsMultiplier(), 9_600, "Should allow maximum permitted changes");
    }
}
