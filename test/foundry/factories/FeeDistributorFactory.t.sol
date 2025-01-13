// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "../TestBase.sol";
import {FeeDistributorFactory} from "../../../contracts/factories/FeeDistributorFactory.sol";
import {FeeDistributor} from "../../../contracts/FeeDistributor.sol";
import {IVoter} from "../../../contracts/interfaces/IVoter.sol";
import {MockVoter} from "../TestBase.sol";

contract FeeDistributorFactoryTest is TestBase {
    FeeDistributorFactory public factory;

    function setUp() public override {
        super.setUp();

        // Deploy the factory
        factory = new FeeDistributorFactory();
    }

    function test_createFeeDistributor() public {
        // Set block timestamp to a known value for testing
        uint256 testTimestamp = 1000 weeks;
        vm.warp(testTimestamp);

        // Create a new FeeDistributor from voter address
        vm.prank(address(mockVoter));
        address newDistributor = factory.createFeeDistributor(address(feeRecipient));

        // Verify the lastFeeDistributor was updated
        assertEq(factory.lastFeeDistributor(), newDistributor, "Last fee distributor not updated correctly");

        // Verify the FeeDistributor was initialized correctly
        FeeDistributor distributor = FeeDistributor(newDistributor);

        // Check all constructor-initialized variables
        assertEq(distributor.voter(), address(mockVoter), "Voter not set correctly");
        assertEq(distributor.feeRecipient(), address(feeRecipient), "Fee recipient not set correctly");
        assertEq(distributor.voteModule(), mockVoter.voteModule(), "Vote module not set correctly");
        assertEq(address(distributor.plugin()), mockVoter.launcherPlugin(), "Plugin not set correctly");

        // Verify period calculation
        assertEq(distributor.getPeriod(), testTimestamp / 1 weeks, "Period calculation incorrect");
        assertEq(distributor.firstPeriod(), testTimestamp / 1 weeks, "First period not matching current period");
    }

    function test_createMultipleFeeDistributors() public {
        // Set initial timestamp
        uint256 firstTimestamp = 1000 weeks;
        vm.warp(firstTimestamp);

        // Create first FeeDistributor
        vm.prank(address(mockVoter));
        address firstDistributor = factory.createFeeDistributor(address(feeRecipient));

        // Advance time by 2 weeks
        vm.warp(firstTimestamp + 2 weeks);

        // Create second FeeDistributor with different recipient
        address secondRecipient = makeAddr("secondRecipient");
        vm.prank(address(mockVoter));
        address secondDistributor = factory.createFeeDistributor(secondRecipient);

        // Verify they are different addresses
        assertTrue(firstDistributor != secondDistributor, "Distributors should have different addresses");

        // Verify lastFeeDistributor points to the most recent creation
        assertEq(factory.lastFeeDistributor(), secondDistributor, "Last fee distributor should be the second one");

        // Verify both distributors were initialized with correct values
        FeeDistributor distributor1 = FeeDistributor(firstDistributor);
        FeeDistributor distributor2 = FeeDistributor(secondDistributor);

        // Check first distributor
        assertEq(distributor1.voter(), address(mockVoter), "First distributor voter not set correctly");
        assertEq(
            distributor1.feeRecipient(), address(feeRecipient), "First distributor fee recipient not set correctly"
        );
        assertEq(distributor1.voteModule(), mockVoter.voteModule(), "First distributor vote module not set correctly");
        assertEq(
            address(distributor1.plugin()), mockVoter.launcherPlugin(), "First distributor plugin not set correctly"
        );
        assertEq(distributor1.firstPeriod(), firstTimestamp / 1 weeks, "First distributor period not set correctly");
        assertEq(distributor1.getPeriod(), (firstTimestamp + 2 weeks) / 1 weeks, "Current period calculation incorrect");

        // Check second distributor
        assertEq(distributor2.voter(), address(mockVoter), "Second distributor voter not set correctly");
        assertEq(distributor2.feeRecipient(), secondRecipient, "Second distributor fee recipient not set correctly");
        assertEq(distributor2.voteModule(), mockVoter.voteModule(), "Second distributor vote module not set correctly");
        assertEq(
            address(distributor2.plugin()), mockVoter.launcherPlugin(), "Second distributor plugin not set correctly"
        );
        assertEq(
            distributor2.firstPeriod(),
            (firstTimestamp + 2 weeks) / 1 weeks,
            "Second distributor period not set correctly"
        );
        assertEq(distributor2.getPeriod(), (firstTimestamp + 2 weeks) / 1 weeks, "Current period calculation incorrect");
    }

    function test_periodCalculation(uint256 timestamp) public {
        // Bound timestamp to reasonable values to avoid overflow
        timestamp = bound(timestamp, 0, type(uint32).max);

        // Set timestamp
        vm.warp(timestamp);

        // Create new distributor
        vm.prank(address(mockVoter));
        FeeDistributor distributor = FeeDistributor(factory.createFeeDistributor(address(feeRecipient)));

        // Verify period calculation
        assertEq(distributor.getPeriod(), timestamp / 1 weeks, "Period calculation incorrect");
        assertEq(distributor.firstPeriod(), timestamp / 1 weeks, "First period not matching current period");
    }

    function test_createFeeDistributorFromNonVoter() public {
        // Should revert since caller is not a Voter
        vm.expectRevert();
        factory.createFeeDistributor(address(feeRecipient));
    }
}
