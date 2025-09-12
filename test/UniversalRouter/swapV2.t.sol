// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Fixture.t.sol";

import "contracts/universalRouter/libraries/Commands.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {ActionConstants} from "lib/v4-periphery/src/libraries/ActionConstants.sol";
import "contracts/interfaces/IPair.sol";
import "contracts/universalRouter/libraries/SwapRoute.sol";

contract SwapV2Test is Fixture {
	uint256 constant BALANCE = 10 ether;
	bool constant STABLE = true;

	function setUp() public override {
		super.setUp();

		address pair = pairFactory.createPair(address(token0), address(token1), STABLE);
		deal(address(token0), pair, 10000 ether);
		deal(address(token1), pair, 10000 ether);
		IPair(pair).sync();

		IPair(pair).fee();

		// vm.startPrank(ACCESS_HUB);
		// pairFactory.setPairFee(pair, 3000);

		vm.startPrank(alice);
		deal(alice, BALANCE);
		deal(address(token0), alice, BALANCE);
		deal(address(token1), alice, BALANCE);

		token0.approve(address(permit2), type(uint256).max);
		token1.approve(address(permit2), type(uint256).max);

		permit2.approve(
			address(token0),
			address(universalRouter),
			type(uint160).max,
			type(uint48).max
		);
		permit2.approve(
			address(token1),
			address(universalRouter),
			type(uint160).max,
			type(uint48).max
		);
		vm.stopPrank();
	}

	// ======================== SWAP EXACT IN ========================

	function testExactInput0For1(uint160 amountIn) public {
		vm.assume(amountIn > 1e18 && amountIn < BALANCE);
		bool payerIsUser = true;

		SwapRoute.Route[] memory path = new SwapRoute.Route[](1);
		path[0] = SwapRoute.Route({from: address(token0), to: address(token1), stable: STABLE});

		bytes[] memory inputs = new bytes[](1);
		inputs[0] = abi.encode(alice, amountIn, 0, abi.encode(path), payerIsUser);

		uint256 balance0Before = token0.balanceOf(alice);
		uint256 balance1Before = token1.balanceOf(alice);

		vm.prank(alice);
		bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V2_SWAP_EXACT_IN)));
		universalRouter.execute(commands, inputs, block.timestamp);

		assertEq(token0.balanceOf(alice), balance0Before - amountIn);
		assertGt(token1.balanceOf(alice), balance1Before);
	}

	// ======================== SWAP EXACT OUT ========================

	function testExactOutput0For1(uint160 amountOut) public {
		vm.assume(amountOut > 0 && amountOut < BALANCE);

		bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V2_SWAP_EXACT_OUT)));
		SwapRoute.Route[] memory path = new SwapRoute.Route[](1);
		path[0] = SwapRoute.Route({from: address(token0), to: address(token1), stable: STABLE});

		bytes[] memory inputs = new bytes[](1);
		inputs[0] = abi.encode(alice, amountOut, type(uint256).max, abi.encode(path), true);

		vm.prank(alice);
		universalRouter.execute(commands, inputs, block.timestamp);

		assertLt(token0.balanceOf(alice), BALANCE);
		assertEq(token1.balanceOf(alice), BALANCE + amountOut);
	}
}
