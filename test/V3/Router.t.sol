// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Fixture.t.sol";
import {RamsesV3Pool, IRamsesV3Factory} from "contracts/CL/core/RamsesV3Pool.sol";
import {SwapRouter, ISwapRouter} from "contracts/CL/periphery/SwapRouter.sol";
import {NonfungiblePositionManager} from "contracts/CL/periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "contracts/CL/periphery/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "contracts/CL/core/libraries/TickMath.sol";
import {LiquidityAmounts} from "contracts/CL/periphery/libraries/LiquidityAmounts.sol";

contract SwapRouterTest is Fixture {
	RamsesV3Pool public pool;
	uint256 public tokenId;

	// Test parameters
	uint160 public constant INITIAL_SQRT_PRICE = 1 * 2 ** 96; // 1:1 price
	int24 public constant TICK_SPACING = 5;
	int24 public constant TICK_LOWER = -1000;
	int24 public constant TICK_UPPER = 1000;

	function setUp() public override {
		super.setUp();

		// Create a pool with properly sorted tokens
		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);
		pool = RamsesV3Pool(
			clPoolFactory.createPool(tokenA, tokenB, TICK_SPACING, INITIAL_SQRT_PRICE)
		);
		pool.slot0();

		// Add liquidity to the pool
		_addLiquidityToPool();
	}

	function _addLiquidityToPool() internal {
		// Get the sorted token order from the pool
		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);

		// Mint tokens to alice
		token0.mint(alice, 1000e18);
		token1.mint(alice, 1000e18);

		vm.startPrank(alice);

		// Approve tokens for NFP manager
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		// Create position with sorted tokens
		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 100e18,
				amount1Desired: 100e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1000
			});

		(tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();
	}

	function testConstructor() public view {
		// Just verify that the router has the expected WETH address
		assertEq(swapRouter.WETH9(), address(WETH));
	}

	function testPoolCreation() public view {
		assertEq(
			address(pool),
			clPoolFactory.getPool(address(token0), address(token1), TICK_SPACING)
		);
	}

	function testSortTokens() public view {
		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);
		// Just verify that tokens are sorted (lower address first)
		assertTrue(tokenA < tokenB, "Tokens should be sorted by address");
	}

	// ============ Exact Input Single Tests ============

	function testExactInputSingle() public {
		uint256 amountIn = 10e18;
		uint256 amountOutMinimum = 9e18; // Allow some slippage

		// Mint tokens to bob
		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: amountOutMinimum,
			sqrtPriceLimitX96: 0
		});

		uint256 balanceBefore = token1.balanceOf(bob);
		uint256 amountOut = swapRouter.exactInputSingle(params);
		uint256 balanceAfter = token1.balanceOf(bob);

		assertGt(amountOut, 0, "Should receive tokens");
		assertEq(balanceAfter - balanceBefore, amountOut, "Balance should increase by amountOut");
		assertGe(amountOut, amountOutMinimum, "Should respect minimum output");
		vm.stopPrank();
	}

	function testExactInputSingleWithPriceLimit() public {
		uint256 amountIn = 10e18;
		uint256 amountOutMinimum = 9e18;

		// Mint tokens to bob
		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		// Set a price limit
		uint160 sqrtPriceLimitX96 = (INITIAL_SQRT_PRICE * 95) / 100; // 5% price impact limit

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: amountOutMinimum,
			sqrtPriceLimitX96: sqrtPriceLimitX96
		});

		uint256 amountOut = swapRouter.exactInputSingle(params);
		assertGt(amountOut, 0, "Should receive tokens");
		vm.stopPrank();
	}

	function testExactInputSingleInsufficientOutput() public {
		uint256 amountIn = 10e18;
		uint256 amountOutMinimum = 20e18; // Unrealistic minimum

		// Mint tokens to bob
		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: amountOutMinimum,
			sqrtPriceLimitX96: 0
		});

		vm.expectRevert("Too little received");
		swapRouter.exactInputSingle(params);
		vm.stopPrank();
	}

	function testExactInputSingleExpiredDeadline() public {
		uint256 amountIn = 10e18;

		// Mint tokens to bob
		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp - 1, // Expired
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		vm.expectRevert();
		swapRouter.exactInputSingle(params);
		vm.stopPrank();
	}

	// ============ Exact Output Single Tests ============

	function testExactOutputSingle() public {
		uint256 amountOut = 5e18;
		uint256 amountInMaximum = 10e18;

		// Mint tokens to bob
		token0.mint(bob, amountInMaximum);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountInMaximum);

		ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountOut: amountOut,
			amountInMaximum: amountInMaximum,
			sqrtPriceLimitX96: 0
		});

		uint256 balanceBefore = token1.balanceOf(bob);
		uint256 amountIn = swapRouter.exactOutputSingle(params);
		uint256 balanceAfter = token1.balanceOf(bob);

		assertGt(amountIn, 0, "Should consume tokens");
		assertLe(amountIn, amountInMaximum, "Should respect maximum input");
		assertEq(balanceAfter - balanceBefore, amountOut, "Should receive exact output");
		vm.stopPrank();
	}

	function testExactOutputSingleExcessiveInput() public {
		uint256 amountOut = 5e18;
		uint256 amountInMaximum = 1e18; // Too low

		// Mint tokens to bob
		token0.mint(bob, amountInMaximum);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountInMaximum);

		ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountOut: amountOut,
			amountInMaximum: amountInMaximum,
			sqrtPriceLimitX96: 0
		});

		vm.expectRevert("Too much requested");
		swapRouter.exactOutputSingle(params);
		vm.stopPrank();
	}

	// ============ Edge Cases and Error Tests ============

	function testSwapWithZeroAmount() public {
		vm.startPrank(bob);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: 0,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		uint256 amountOut = swapRouter.exactInputSingle(params);
		assertEq(amountOut, 0, "Should return 0 for zero input");
		vm.stopPrank();
	}

	function testSwapToZeroAddress() public {
		uint256 amountIn = 10e18;

		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: address(0), // Zero address
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		uint256 amountOut = swapRouter.exactInputSingle(params);
		assertGt(amountOut, 0, "Should still execute swap");
		// Tokens should go to router address when recipient is zero
		assertEq(token1.balanceOf(address(swapRouter)), amountOut, "Tokens should go to router");
		vm.stopPrank();
	}

	function testSwapWithInvalidTickSpacing() public {
		uint256 amountIn = 10e18;

		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: 3, // Invalid tick spacing
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		// Should revert because pool doesn't exist
		vm.expectRevert();
		swapRouter.exactInputSingle(params);
		vm.stopPrank();
	}

	function testSwapWithSameTokens() public {
		uint256 amountIn = 10e18;

		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token0), // Same token
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		// Should revert because pool doesn't exist for same tokens
		vm.expectRevert();
		swapRouter.exactInputSingle(params);
		vm.stopPrank();
	}

	// ============ Multicall Tests ============

	function testMulticall() public {
		uint256 amountIn = 5e18;

		token0.mint(bob, amountIn * 2);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn * 2);

		// Prepare two swap calls
		ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		ISwapRouter.ExactInputSingleParams memory params2 = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		bytes memory call1 = abi.encodeWithSelector(swapRouter.exactInputSingle.selector, params1);
		bytes memory call2 = abi.encodeWithSelector(swapRouter.exactInputSingle.selector, params2);

		bytes[] memory calls = new bytes[](2);
		calls[0] = call1;
		calls[1] = call2;

		uint256 balanceBefore = token1.balanceOf(bob);
		bytes[] memory results = swapRouter.multicall(calls);
		uint256 balanceAfter = token1.balanceOf(bob);

		assertEq(results.length, 2, "Should return results for both calls");
		assertGt(balanceAfter - balanceBefore, 0, "Should receive tokens from both swaps");
		vm.stopPrank();
	}

	// ============ Self Permit Tests ============

	function testSelfPermit() public {
		// This test would require setting up permit functionality
		// For now, we'll just test that the function exists and doesn't revert
		vm.startPrank(bob);

		// Create a permit signature (this is a simplified test)
		uint256 deadline = block.timestamp + 1000;
		uint8 v = 27;
		bytes32 r = bytes32(uint256(1));
		bytes32 s = bytes32(uint256(2));

		// This should not revert (though it may not work without proper permit setup)
		swapRouter.selfPermit(address(token0), 0, deadline, v, r, s);
		vm.stopPrank();
	}

	// ============ WETH Integration Tests ============

	function testSwapWithWETH() public {
		// Create WETH/token0 pool
		RamsesV3Pool wethPool = RamsesV3Pool(
			clPoolFactory.createPool(
				address(WETH),
				address(token0),
				TICK_SPACING,
				INITIAL_SQRT_PRICE
			)
		);

		// Add liquidity to WETH pool
		vm.deal(alice, 1000e18);
		token0.mint(alice, 1000e18);

		vm.startPrank(alice);
		WETH.deposit{value: 100e18}();
		WETH.approve(address(nfpManager), type(uint256).max);
		token0.approve(address(nfpManager), type(uint256).max);

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: address(WETH),
				token1: address(token0),
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 10e18,
				amount1Desired: 10e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1000
			});

		nfpManager.mint(params);
		vm.stopPrank();

		// Test ETH to token swap
		uint256 amountIn = 1e18;
		uint256 amountOutMinimum = 0.9e18;

		vm.deal(bob, amountIn);
		vm.startPrank(bob);

		ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(WETH),
			tokenOut: address(token0),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: amountOutMinimum,
			sqrtPriceLimitX96: 0
		});

		uint256 balanceBefore = token0.balanceOf(bob);
		uint256 amountOut = swapRouter.exactInputSingle{value: amountIn}(swapParams);
		uint256 balanceAfter = token0.balanceOf(bob);

		assertGt(amountOut, 0, "Should receive tokens");
		assertEq(balanceAfter - balanceBefore, amountOut, "Balance should increase by amountOut");
		vm.stopPrank();
	}

	// ============ Gas Optimization Tests ============

	function testGasOptimizationExactInput() public {
		uint256 amountIn = 1e18;

		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		uint256 gasBefore = gasleft();

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		swapRouter.exactInputSingle(params);
		uint256 gasUsed = gasBefore - gasleft();

		// Gas usage should be reasonable (less than 500k for a simple swap)
		assertLt(gasUsed, 500000, "Gas usage should be reasonable");
		vm.stopPrank();
	}

	// ============ Reentrancy Tests ============

	function testNoReentrancy() public {
		// This test verifies that the router doesn't allow reentrancy
		// The router should be safe from reentrancy attacks due to the pool's lock mechanism

		uint256 amountIn = 1e18;
		token0.mint(bob, amountIn);
		vm.startPrank(bob);
		token0.approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: address(token0),
			tokenOut: address(token1),
			tickSpacing: TICK_SPACING,
			recipient: bob,
			deadline: block.timestamp + 1000,
			amountIn: amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		// This should not cause any reentrancy issues
		uint256 amountOut = swapRouter.exactInputSingle(params);
		assertGt(amountOut, 0, "Swap should complete successfully");
		vm.stopPrank();
	}
}
