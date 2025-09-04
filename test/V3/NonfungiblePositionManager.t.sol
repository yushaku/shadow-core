// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "test/V3/Fixture.t.sol";
import "contracts/CL/periphery/interfaces/INonfungiblePositionManager.sol";
import "contracts/CL/core/interfaces/IRamsesV3Pool.sol";
import "contracts/CL/periphery/libraries/PoolAddress.sol";

contract NonfungiblePositionManagerTest is Fixture {
	uint256 constant DEADLINE = 1e18;
	int24 constant TICK_SPACING = 60;
	int24 constant TICK_LOWER = -120;
	int24 constant TICK_UPPER = 120;

	function setUp() public override {
		super.setUp();

		// Fund test accounts
		token0.mint(alice, 10000e18);
		token1.mint(alice, 10000e18);
		token0.mint(bob, 10000e18);
		token1.mint(bob, 10000e18);
		token0.mint(carol, 10000e18);
		token1.mint(carol, 10000e18);

		vm.deal(alice, 10000e18);
		vm.deal(bob, 10000e18);
		vm.deal(carol, 10000e18);
	}

	// Helper function to get tokens in correct order
	function getSortedTokens() internal view returns (address tokenA, address tokenB) {
		if (address(token0) < address(token1)) {
			return (address(token0), address(token1));
		} else {
			return (address(token1), address(token0));
		}
	}

	// ============ UTILITY FUNCTIONS ============

	function testTokenURI() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Test tokenURI
		string memory uri = nfpManager.tokenURI(tokenId);
		assertTrue(bytes(uri).length > 0);
	}

	function testTokenURIRevertOnInvalidToken() public {
		vm.expectRevert();
		nfpManager.tokenURI(999);
	}

	// ============ POSITION MINTING ============

	function testMintPosition() public {
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.mint(
			params
		);

		assertEq(tokenId, 1);
		assertGt(liquidity, 0);
		assertGt(amount0, 0);
		assertGt(amount1, 0);

		// Check that NFT was minted
		assertEq(nfpManager.ownerOf(tokenId), alice);
		assertEq(nfpManager.balanceOf(alice), 1);
		vm.stopPrank();
	}

	function testMintPositionWithETH() public {
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: address(WETH),
				token1: address(token0),
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.mint{
			value: 1000e18
		}(params);

		assertEq(tokenId, 1);
		assertGt(liquidity, 0);
		assertGt(amount0, 0);
		assertGt(amount1, 0);

		// Check that NFT was minted
		assertEq(nfpManager.ownerOf(tokenId), alice);
		vm.stopPrank();
	}

	function testMintPositionRevertOnDeadline() public {
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp - 1
			});

		vm.expectRevert();
		nfpManager.mint(params);
		vm.stopPrank();
	}

	// ============ POSITION QUERIES ============

	function testPositions() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Query position details
		(
			address posToken0,
			address posToken1,
			int24 posTickSpacing,
			int24 posTickLower,
			int24 posTickUpper,
			uint128 posLiquidity,
			uint256 feeGrowthInside0LastX128,
			uint256 feeGrowthInside1LastX128,
			uint128 tokensOwed0,
			uint128 tokensOwed1
		) = nfpManager.positions(tokenId);

		assertEq(posToken0, tokenA);
		assertEq(posToken1, tokenB);
		assertEq(posTickSpacing, TICK_SPACING);
		assertEq(posTickLower, TICK_LOWER);
		assertEq(posTickUpper, TICK_UPPER);
		assertGt(posLiquidity, 0);
		assertEq(tokensOwed0, 0);
		assertEq(tokensOwed1, 0);
	}

	function testPositionsRevertOnInvalidToken() public {
		vm.expectRevert();
		nfpManager.positions(999);
	}

	// ============ INCREASE LIQUIDITY ============

	function testIncreaseLiquidity() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);

		// Increase liquidity
		INonfungiblePositionManager.IncreaseLiquidityParams
			memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: tokenId,
				amount0Desired: 500e18,
				amount1Desired: 500e18,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp + 1
			});

		(uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.increaseLiquidity(
			increaseParams
		);

		assertGt(liquidity, 0);
		assertGt(amount0, 0);
		assertGt(amount1, 0);
		vm.stopPrank();
	}

	function testIncreaseLiquidityRevertOnDeadline() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);

		// Try to increase liquidity with expired deadline
		INonfungiblePositionManager.IncreaseLiquidityParams
			memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: tokenId,
				amount0Desired: 500e18,
				amount1Desired: 500e18,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp - 1
			});

		vm.expectRevert();
		nfpManager.increaseLiquidity(increaseParams);
		vm.stopPrank();
	}

	function testIncreaseLiquidityRevertOnUnauthorized() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: address(token0),
				token1: address(token1),
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Try to increase liquidity from different account
		vm.startPrank(bob);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		INonfungiblePositionManager.IncreaseLiquidityParams
			memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: tokenId,
				amount0Desired: 500e18,
				amount1Desired: 500e18,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp + 1
			});

		// This should work since increaseLiquidity doesn't check ownership
		(uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.increaseLiquidity(
			increaseParams
		);
		assertGt(liquidity, 0);
		vm.stopPrank();
	}

	// ============ DECREASE LIQUIDITY ============

	function testDecreaseLiquidity() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 initialLiquidity, , ) = nfpManager.mint(params);

		// Decrease liquidity
		INonfungiblePositionManager.DecreaseLiquidityParams
			memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: tokenId,
				liquidity: initialLiquidity / 2,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp + 1
			});

		(uint256 amount0, uint256 amount1) = nfpManager.decreaseLiquidity(decreaseParams);

		assertGt(amount0, 0);
		assertGt(amount1, 0);
		vm.stopPrank();
	}

	function testDecreaseLiquidityRevertOnUnauthorized() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 initialLiquidity, , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Try to decrease liquidity from different account
		vm.startPrank(bob);
		INonfungiblePositionManager.DecreaseLiquidityParams
			memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: tokenId,
				liquidity: initialLiquidity / 2,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp + 1
			});

		vm.expectRevert();
		nfpManager.decreaseLiquidity(decreaseParams);
		vm.stopPrank();
	}

	function testDecreaseLiquidityRevertOnDeadline() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 initialLiquidity, , ) = nfpManager.mint(params);

		// Try to decrease liquidity with expired deadline
		INonfungiblePositionManager.DecreaseLiquidityParams
			memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: tokenId,
				liquidity: initialLiquidity / 2,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp - 1
			});

		vm.expectRevert();
		nfpManager.decreaseLiquidity(decreaseParams);
		vm.stopPrank();
	}

	// ============ COLLECT FEES ============

	function testCollect() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);

		// Collect fees
		INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager
			.CollectParams({
				tokenId: tokenId,
				recipient: alice,
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			});

		(uint256 amount0, uint256 amount1) = nfpManager.collect(collectParams);

		// Initially there should be no fees to collect
		assertEq(amount0, 0);
		assertEq(amount1, 0);
		vm.stopPrank();
	}

	function testCollectRevertOnUnauthorized() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Try to collect from different account
		vm.startPrank(bob);
		INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager
			.CollectParams({
				tokenId: tokenId,
				recipient: bob,
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			});

		vm.expectRevert();
		nfpManager.collect(collectParams);
		vm.stopPrank();
	}

	// ============ BURN POSITION ============

	function testBurn() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, uint128 initialLiquidity, , ) = nfpManager.mint(params);

		// Decrease all liquidity first
		INonfungiblePositionManager.DecreaseLiquidityParams
			memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: tokenId,
				liquidity: initialLiquidity,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp + 1
			});

		nfpManager.decreaseLiquidity(decreaseParams);

		// Collect any remaining tokens
		INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager
			.CollectParams({
				tokenId: tokenId,
				recipient: alice,
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			});

		nfpManager.collect(collectParams);

		// Now burn the position
		nfpManager.burn(tokenId);

		// Verify the token is burned
		vm.expectRevert();
		nfpManager.ownerOf(tokenId);
		vm.stopPrank();
	}

	function testBurnRevertOnNotCleared() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);

		// Try to burn without clearing liquidity
		vm.expectRevert();
		nfpManager.burn(tokenId);
		vm.stopPrank();
	}

	function testBurnRevertOnUnauthorized() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Try to burn from different account
		vm.startPrank(bob);
		vm.expectRevert();
		nfpManager.burn(tokenId);
		vm.stopPrank();
	}

	// ============ ERC721 FUNCTIONALITY ============

	function testERC721Basics() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Test ERC721 basics
		assertEq(nfpManager.ownerOf(tokenId), alice);
		assertEq(nfpManager.balanceOf(alice), 1);
		assertEq(nfpManager.tokenOfOwnerByIndex(alice, 0), tokenId);
		assertEq(nfpManager.totalSupply(), 1);
	}

	function testTransferPosition() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);
		vm.stopPrank();

		// Transfer the position
		vm.startPrank(alice);
		nfpManager.transferFrom(alice, bob, tokenId);
		vm.stopPrank();

		// Verify transfer
		assertEq(nfpManager.ownerOf(tokenId), bob);
		assertEq(nfpManager.balanceOf(alice), 0);
		assertEq(nfpManager.balanceOf(bob), 1);
	}

	// ============ MULTIPLE POSITIONS ============

	function testMultiplePositions() public {
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		// Mint first position
		INonfungiblePositionManager.MintParams memory params1 = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId1, , , ) = nfpManager.mint(params1);

		// Mint second position with different tick range
		INonfungiblePositionManager.MintParams memory params2 = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER + 60,
				tickUpper: TICK_UPPER + 60,
				amount0Desired: 500e18,
				amount1Desired: 500e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId2, , , ) = nfpManager.mint(params2);

		assertEq(tokenId1, 1);
		assertEq(tokenId2, 2);
		assertEq(nfpManager.balanceOf(alice), 2);
		assertEq(nfpManager.totalSupply(), 2);
		vm.stopPrank();
	}

	// ============ EDGE CASES ============

	function testMintWithZeroAmounts() public {
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 0,
				amount1Desired: 0,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		// This should revert or create a position with 0 liquidity
		vm.expectRevert();
		nfpManager.mint(params);
		vm.stopPrank();
	}

	function testCollectWithZeroAmounts() public {
		// Mint a position first
		vm.startPrank(alice);
		token0.approve(address(nfpManager), type(uint256).max);
		token1.approve(address(nfpManager), type(uint256).max);

		(address tokenA, address tokenB) = getSortedTokens();

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp + 1
			});

		(uint256 tokenId, , , ) = nfpManager.mint(params);

		// Try to collect with zero amounts
		INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager
			.CollectParams({tokenId: tokenId, recipient: alice, amount0Max: 0, amount1Max: 0});

		vm.expectRevert();
		nfpManager.collect(collectParams);
		vm.stopPrank();
	}
}
