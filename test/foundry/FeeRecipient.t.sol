// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {FeeRecipient} from "../../contracts/FeeRecipient.sol";
import {IFeeRecipient} from "../../contracts/interfaces/IFeeRecipient.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Pair} from "../../contracts/Pair.sol";
import {IFeeDistributor} from "../../contracts/interfaces/IFeeDistributor.sol";
import {FeeDistributor} from "../../contracts/FeeDistributor.sol";
import {console} from "forge-std/console.sol";

contract FeeRecipientTest is TestBase {
    address public newTreasury = makeAddr("newTreasury");
    Pair public pair;

    function setUp() public override {
        super.setUp();
        pair = new Pair();
        pair.initialize(address(token0), address(token1), false);
        feeRecipient = new FeeRecipient(address(pair), address(mockVoter), address(feeRecipientFactory));
    }

    function test_constructor() public view {
        assertEq(feeRecipient.pair(), address(pair), "Pair address mismatch");
        assertEq(feeRecipient.voter(), address(mockVoter), "Voter address mismatch");
        assertEq(
            feeRecipient.feeRecipientFactory(), address(feeRecipientFactory), "Fee recipient factory address mismatch"
        );
    }

    function test_initialize() public {
        address feeDistributor = makeAddr("feeDistributor");

        vm.prank(address(mockVoter));
        feeRecipient.initialize(feeDistributor);

        assertEq(feeRecipient.feeDistributor(), feeDistributor, "Fee distributor address mismatch");
        assertEq(
            IERC20(address(pair)).allowance(address(feeRecipient), feeDistributor),
            type(uint256).max,
            "Allowance not set correctly"
        );
    }

    function test_initializeRevertsForUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeRecipient.initialize(alice);
    }

    function testFuzz_notifyFees(uint256 amount, uint256 feeToTreasury) public {
        vm.assume(amount > 0 && amount <= type(uint112).max); // Reasonable bounds, we have a special test for 0
        vm.assume(feeToTreasury <= 10_000); // Between 0% and 100%

        address feeDistributor = makeAddr("feeDistributor");

        // Initialize first
        vm.prank(address(mockVoter));
        feeRecipient.initialize(feeDistributor);

        // Mock feeToTreasury call
        vm.mockCall(address(feeRecipientFactory), abi.encodeWithSignature("feeToTreasury()"), abi.encode(feeToTreasury));

        // Mock treasury call
        vm.mockCall(address(feeRecipientFactory), abi.encodeWithSignature("treasury()"), abi.encode(TREASURY));

        // Send LP tokens to fee recipient
        deal(address(pair), address(feeRecipient), amount);

        // Calculate expected amounts
        uint256 treasuryAmount = (amount * feeToTreasury) / 10_000;
        uint256 feeDistAmount = amount - treasuryAmount;

        // Mock fee distributor call
        vm.mockCall(
            address(feeDistributor),
            abi.encodeWithSignature("notifyRewardAmount(address,uint256)", pair, feeDistAmount),
            abi.encode()
        );

        vm.prank(address(mockVoter));
        feeRecipient.notifyFees();

        assertEq(IERC20(pair).balanceOf(TREASURY), treasuryAmount, "Treasury balance mismatch"); // Treasury should receive correct percentage
        assertEq(
            IERC20(address(pair)).balanceOf(address(feeRecipient)), feeDistAmount, "Fee recipient balance mismatch"
        ); // Balance should be feeDistAmount because the notifyRewardAmount call is mocked
    }

    function test_notifyFeesRevertsForUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
        feeRecipient.notifyFees();
    }

    function test_notifyFeesWithZeroBalance() public {
        FeeDistributor feeDistributor = new FeeDistributor(address(mockVoter), address(feeRecipient));

        // Initialize first
        vm.prank(address(mockVoter));
        feeRecipient.initialize(address(feeDistributor));

        vm.prank(address(mockVoter));
        feeRecipient.notifyFees(); // Should not revert
        assertEq(IERC20(address(pair)).balanceOf(address(feeRecipient)), 0, "Fee recipient balance should be zero"); // no balance
        assertEq(
            IFeeDistributor(feeDistributor).earned(address(pair), address(feeRecipient)),
            0,
            "Fee recipient earned should be zero"
        ); // no earned
    }
}
