// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Timelock} from "contracts/Timelock.sol";
import {YSK} from "contracts/YSK.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract TimelockV5Test is Test {
	Timelock public timelock;
	YSK public ysk;

	address public admin;
	address public proposer;
	address public canceller;
	address public executor;
	address public otherUser;
	address public minter;

	uint256 public minDelay = 1 days;

	function setUp() public {
		admin = makeAddr("admin");
		proposer = makeAddr("proposer");
		canceller = makeAddr("canceller");
		executor = makeAddr("executor");
		otherUser = makeAddr("otherUser");
		minter = makeAddr("minter");

		// Deploy YSK with timelock as minter initially
		ysk = new YSK(address(this));

		address[] memory proposers = new address[](1);
		proposers[0] = proposer;

		address[] memory cancellers = new address[](1);
		cancellers[0] = canceller;

		// address(0) means anyone can execute
		address[] memory executors = new address[](1);
		executors[0] = address(0);

		// In OZ v5, the TimelockController constructor takes an admin address.
		// We grant the DEFAULT_ADMIN_ROLE to the admin address after deployment.
		timelock = new Timelock(minDelay, proposers, executors, address(this));
		timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), admin);
		timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

		// Set timelock as minter of YSK
		ysk.setMinter(address(timelock));
	}

	// ============ Constructor & Role Tests ============

	function test_InitialRoles() public view {
		assertEq(timelock.getMinDelay(), minDelay);
		assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
		assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
		assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
		// By default, proposers are also cancellers in the OZ contract, but we set it up explicitly.
		assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), proposer));
	}

	// ============ Schedule, Execute, Cancel Tests ============

	function test_ScheduleAndExecuteMint() public {
		bytes memory data = abi.encodeWithSelector(YSK.mint.selector, otherUser, 1000e18);
		bytes32 salt = keccak256("mint_salt");
		bytes32 predecessor = bytes32(0);

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, predecessor, salt, minDelay);

		bytes32 opId = timelock.hashOperation(address(ysk), 0, data, predecessor, salt);
		assertTrue(timelock.isOperationPending(opId));

		vm.warp(block.timestamp + minDelay);

		timelock.execute(address(ysk), 0, data, predecessor, salt);

		assertTrue(timelock.isOperationDone(opId));
		assertEq(ysk.balanceOf(otherUser), 1000e18);
	}

	function test_ScheduleAndExecuteSetMinter() public {
		bytes memory data = abi.encodeWithSelector(YSK.setMinter.selector, minter);
		bytes32 salt = keccak256("set_minter_salt");
		bytes32 predecessor = bytes32(0);

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, predecessor, salt, minDelay);

		bytes32 opId = timelock.hashOperation(address(ysk), 0, data, predecessor, salt);
		assertTrue(timelock.isOperationPending(opId));

		vm.warp(block.timestamp + minDelay);

		timelock.execute(address(ysk), 0, data, predecessor, salt);

		assertTrue(timelock.isOperationDone(opId));
		assertEq(ysk.minter(), minter);
	}

	function test_ScheduleAndExecuteMintAfterSetMinter() public {
		// First, set minter as minter
		bytes memory setMinterData = abi.encodeWithSelector(YSK.setMinter.selector, minter);
		bytes32 setMinterSalt = keccak256("set_minter_first");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, setMinterData, bytes32(0), setMinterSalt, minDelay);

		vm.warp(block.timestamp + minDelay);
		timelock.execute(address(ysk), 0, setMinterData, bytes32(0), setMinterSalt);

		// Now schedule a mint operation (this will fail because minter is not timelock anymore)
		bytes memory mintData = abi.encodeWithSelector(YSK.mint.selector, otherUser, 500e18);
		bytes32 mintSalt = keccak256("mint_after_set_minter");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, mintData, bytes32(0), mintSalt, minDelay);

		vm.warp(block.timestamp + minDelay);

		// This should fail because timelock is no longer the minter
		vm.expectRevert(YSK.NOT_MINTER.selector);
		timelock.execute(address(ysk), 0, mintData, bytes32(0), mintSalt);
	}

	function test_CancelMintOperation() public {
		bytes memory data = abi.encodeWithSelector(YSK.mint.selector, otherUser, 1000e18);
		bytes32 salt = keccak256("cancel_mint_salt");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, bytes32(0), salt, minDelay);

		bytes32 opId = timelock.hashOperation(address(ysk), 0, data, bytes32(0), salt);
		assertTrue(timelock.isOperationPending(opId));

		// Proposer has canceller role by default in OZ setup
		vm.prank(proposer);
		timelock.cancel(opId);

		assertFalse(timelock.isOperationPending(opId));

		// Verify the mint didn't happen
		assertEq(ysk.balanceOf(otherUser), 0);
	}

	function test_Fail_CancelWithoutRole() public {
		bytes memory data = abi.encodeWithSelector(YSK.mint.selector, otherUser, 1000e18);
		bytes32 salt = keccak256("fail_cancel_mint_salt");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, bytes32(0), salt, minDelay);

		bytes32 opId = timelock.hashOperation(address(ysk), 0, data, bytes32(0), salt);

		vm.prank(otherUser); // User without canceller role
		vm.expectRevert();
		timelock.cancel(opId);
	}

	function test_Fail_ExecuteBeforeDelay() public {
		bytes memory data = abi.encodeWithSelector(YSK.mint.selector, otherUser, 1000e18);
		bytes32 salt = keccak256("delay_mint_salt");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, bytes32(0), salt, minDelay);

		// Use the correct error format for the newer version
		vm.expectRevert();
		timelock.execute(address(ysk), 0, data, bytes32(0), salt);
	}

	function test_Fail_MintWithoutBeingMinter() public {
		// First set minter to someone else
		bytes memory setMinterData = abi.encodeWithSelector(YSK.setMinter.selector, minter);
		bytes32 setMinterSalt = keccak256("set_minter_for_fail_test");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, setMinterData, bytes32(0), setMinterSalt, minDelay);

		vm.warp(block.timestamp + minDelay);
		timelock.execute(address(ysk), 0, setMinterData, bytes32(0), setMinterSalt);

		// Now try to mint - this should fail because timelock is not the minter
		bytes memory data = abi.encodeWithSelector(YSK.mint.selector, otherUser, 1000e18);
		bytes32 salt = keccak256("fail_mint_salt");

		vm.prank(proposer);
		timelock.schedule(address(ysk), 0, data, bytes32(0), salt, minDelay);

		vm.warp(block.timestamp + minDelay);

		// This should fail because timelock is not the minter
		vm.expectRevert(YSK.NOT_MINTER.selector);
		timelock.execute(address(ysk), 0, data, bytes32(0), salt);
	}

	// ============ Admin Tests ============

	function test_UpdateMinDelay() public {
		uint256 newDelay = 2 days;

		// Schedule the update delay operation
		bytes memory data = abi.encodeWithSelector(
			TimelockController.updateDelay.selector,
			newDelay
		);
		bytes32 salt = keccak256("update_delay_salt");

		vm.prank(proposer);
		timelock.schedule(address(timelock), 0, data, bytes32(0), salt, minDelay);

		vm.warp(block.timestamp + minDelay);
		timelock.execute(address(timelock), 0, data, bytes32(0), salt);

		assertEq(timelock.getMinDelay(), newDelay);
	}

	function test_Fail_UpdateMinDelayAsNonAdmin() public {
		vm.prank(otherUser);
		vm.expectRevert();
		timelock.updateDelay(2 days);
	}
}
