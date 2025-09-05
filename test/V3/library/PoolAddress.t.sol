
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../Fixture.t.sol";
import "contracts/CL/periphery/libraries/PoolAddress.sol";
import "contracts/CL/core/RamsesV3Pool.sol";

contract PoolFactoryTest is Fixture {
	uint160 public constant INITIAL_SQRT_PRICE = 1 * 2 ** 96; // 1:1 price
	int24 public constant TICK_SPACING = 5;

	function setUp() public override {
		super.setUp();

    bytes32 hash = keccak256(type(RamsesV3Pool).creationCode);
    console.log("hash", vm.toString(hash));
	}

	/**
	 * @dev expect library PoolAddress of NonfungiblePositionManager to return the same address as PoolFactory create new pool
	 * @notice this test is important to ensure that the pool address is computed correctly
	 * @notice if failed -> POOL_INIT_CODE_HASH of PoolAddress is not correct
	 */
  function testAddress() external {
		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);

		PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
			token0: tokenA,
			token1: tokenB,
			tickSpacing: TICK_SPACING
		});

		address calPool = PoolAddress.computeAddress(address(clPoolDeployer), poolKey);

    address realPool = clPoolFactory.createPool(tokenA, tokenB, TICK_SPACING, INITIAL_SQRT_PRICE);

    assertEq(calPool, realPool);
  }
}
