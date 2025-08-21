// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FeeRecipientFactory} from "contracts/legacy/factories/FeeRecipientFactory.sol";
import {FeeRecipient} from "contracts/legacy/FeeRecipient.sol";
import {IFeeRecipientFactory} from "contracts/interfaces/IFeeRecipientFactory.sol";
import "test/Base.t.sol";

library Events {
    event SetFeeToTreasury(uint256 indexed feeToTreasury);
}

contract FeeRecipientFactoryTest is TheTestBase {
    FeeRecipientFactory public factory;
    address public mockPair;

    function setUp() public override {
        super.setUp();

        // Deploy mock voter and pair
        mockPair = makeAddr("mockPair");

        // Deploy factory
        factory = new FeeRecipientFactory(TREASURY, address(mockVoter), ACCESS_MANAGER);
    }

    function test_constructorInitialization() public view {
        assertEq(factory.treasury(), TREASURY, "Treasury address mismatch");
        assertEq(factory.VOTER(), address(mockVoter), "Voter address mismatch");
        assertEq(factory.accessHub(), ACCESS_MANAGER, "AccessHub address mismatch");
    }

    function test_createFeeRecipientSuccess() public {
        vm.prank(address(mockVoter));
        address newFeeRecipient = factory.createFeeRecipient(mockPair);

        assertEq(factory.lastFeeRecipient(), newFeeRecipient, "Last fee recipient not set correctly");
        assertEq(factory.feeRecipientForPair(mockPair), newFeeRecipient, "Fee recipient not mapped to pair correctly");

        // Verify the FeeRecipient was initialized correctly
        FeeRecipient feeRecipient = FeeRecipient(newFeeRecipient);
        assertEq(feeRecipient.PAIR(), mockPair, "Pair address mismatch");
        assertEq(feeRecipient.VOTER(), address(mockVoter), "Voter address mismatch");
        assertEq(feeRecipient.FEE_RECIPIENT_FACTORY(), address(factory), "Factory address mismatch");
    }

    function test_createFeeRecipientRevertIfNotVoter() public {
        vm.expectRevert();
        factory.createFeeRecipient(mockPair);
    }

    function test_setFeeToTreasurySuccess() public {
        uint256 newFee = 5000; // 50%

        vm.prank(ACCESS_MANAGER);
        factory.setFeeToTreasury(newFee);

        assertEq(factory.feeToTreasury(), newFee, "Fee to treasury not set correctly");
    }

    function test_setFeeToTreasuryRevertIfNotGovernance() public {
        vm.expectRevert();
        factory.setFeeToTreasury(5000);
    }

    function test_setFeeToTreasuryRevertIfTooHigh() public {
        vm.prank(ACCESS_MANAGER);
        vm.expectRevert(IFeeRecipientFactory.INVALID_TREASURY_FEE.selector);
        factory.setFeeToTreasury(10001);
    }

    function test_setTreasurySuccess() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(ACCESS_MANAGER);
        factory.setTreasury(newTreasury);

        assertEq(factory.treasury(), newTreasury, "Treasury address not updated correctly");
    }

    function test_setTreasuryRevertIfNotGovernance() public {
        vm.expectRevert();
        factory.setTreasury(makeAddr("newTreasury"));
    }

    function test_setFeeToTreasuryEmitsEvent() public {
        uint256 newFee = 5000;

        vm.prank(ACCESS_MANAGER);
        vm.expectEmit(true, false, false, true);
        emit Events.SetFeeToTreasury(newFee);
        factory.setFeeToTreasury(newFee);
    }
}
