// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Fixture.t.sol";
import {RamsesV3Pool, IRamsesV3Factory} from "contracts/CL/core/RamsesV3Pool.sol";

contract PoolFactoryTest is Fixture {
	function setUp() public override {
		super.setUp();
	}

	function testInitialize() public view {
		assertEq(clPoolFactory.feeProtocol(), 5);
		assertEq(clPoolFactory.ramsesV3PoolDeployer(), address(clPoolDeployer));
		assertEq(clPoolFactory.feeCollector(), address(clFeeCollector));
		assertEq(clPoolFactory.accessHub(), ACCESS_HUB);
		assertEq(clPoolFactory.voter(), VOTER);
	}

	function testCreatePool() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		address poolAddress = clPoolFactory.createPool(
			address(token0),
			address(token1),
			tickSpacing,
			sqrtPriceX96
		);

		assertEq(poolAddress, clPoolFactory.getPool(address(token0), address(token1), tickSpacing));
		assertEq(poolAddress, clPoolFactory.getPool(address(token1), address(token0), tickSpacing));

		RamsesV3Pool pool = RamsesV3Pool(poolAddress);
		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);
		assertEq(pool.token0(), tokenA);
		assertEq(pool.token1(), tokenB);
		assertEq(pool.tickSpacing(), tickSpacing);
	}

	function testCanNotCreatePool2Times() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		clPoolFactory.createPool(address(token0), address(token1), tickSpacing, sqrtPriceX96);

		vm.expectRevert(abi.encodeWithSignature("POOL_EXIST()"));
		clPoolFactory.createPool(address(token0), address(token1), tickSpacing, sqrtPriceX96 * 2);
	}

	function testCanNotCreatePoolWithSameAddress() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		vm.expectRevert(abi.encodeWithSignature("IT()"));
		clPoolFactory.createPool(address(token0), address(token0), tickSpacing, sqrtPriceX96);
	}

	function testCanNotCreatePoolWithZeroToken() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
		clPoolFactory.createPool(address(0), address(token0), tickSpacing, sqrtPriceX96);
	}

	function testCanNotCreatePoolWithInvalidTickSpace() public {
		int24 invalidTickSpacing = 2;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		vm.expectRevert(abi.encodeWithSignature("ZERO_FEE()"));
		clPoolFactory.createPool(
			address(token1),
			address(token0),
			invalidTickSpacing,
			sqrtPriceX96
		);
	}

	/**
	 * test governance functions
	 */

	function testEnableTickSpacing() public {
		int24 invalidTickSpacing = 2;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		vm.prank(ACCESS_HUB);
		clPoolFactory.enableTickSpacing(2, 120);
		address poolAddress = clPoolFactory.createPool(
			address(token1),
			address(token0),
			invalidTickSpacing,
			sqrtPriceX96
		);
		assertEq(
			poolAddress,
			clPoolFactory.getPool(address(token1), address(token0), invalidTickSpacing)
		);
	}

	function testSetFee() public {
		uint24 newFee = 5000;

		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(ACCESS_HUB);
		vm.expectEmit();
		emit IRamsesV3Factory.FeeAdjustment(pool, newFee);
		clPoolFactory.setFee(pool, newFee);
		assertEq(RamsesV3Pool(pool).fee(), newFee, "Fee not updated correctly");
	}

	// ============ Additional Test Cases ============

	function testCreatePoolWithoutInitialization() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 0; // No initialization

		address poolAddress = clPoolFactory.createPool(
			address(token0),
			address(token1),
			tickSpacing,
			sqrtPriceX96
		);

		assertEq(poolAddress, clPoolFactory.getPool(address(token0), address(token1), tickSpacing));

		RamsesV3Pool pool = RamsesV3Pool(poolAddress);
		assertEq(pool.tickSpacing(), tickSpacing);
	}

	function testCreatePoolWithDifferentTickSpacings() public {
		// Test all default tick spacings
		int24[] memory tickSpacings = new int24[](6);
		tickSpacings[0] = 1;
		tickSpacings[1] = 5;
		tickSpacings[2] = 10;
		tickSpacings[3] = 50;
		tickSpacings[4] = 100;
		tickSpacings[5] = 200;

		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		for (uint i = 0; i < tickSpacings.length; i++) {
			address poolAddress = clPoolFactory.createPool(
				address(token0),
				address(token1),
				tickSpacings[i],
				sqrtPriceX96
			);

			RamsesV3Pool pool = RamsesV3Pool(poolAddress);
			assertEq(pool.tickSpacing(), tickSpacings[i]);
		}
	}

	function testSortTokens() public view {
		(address token0, address token1) = clPoolFactory.sortTokens(
			address(token1),
			address(token0)
		);
		assertEq(token0, address(token0)); // token0 should be the lower address
		assertEq(token1, address(token1));

		(address token0Again, address token1Again) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);
		assertEq(token0Again, address(token0));
		assertEq(token1Again, address(token1));
	}

	function testTickSpacingInitialFee() public view {
		// Test default tick spacing fees
		assertEq(clPoolFactory.tickSpacingInitialFee(1), 100);
		assertEq(clPoolFactory.tickSpacingInitialFee(5), 250);
		assertEq(clPoolFactory.tickSpacingInitialFee(10), 500);
		assertEq(clPoolFactory.tickSpacingInitialFee(50), 3000);
		assertEq(clPoolFactory.tickSpacingInitialFee(100), 10000);
		assertEq(clPoolFactory.tickSpacingInitialFee(200), 20000);

		// Test non-existent tick spacing
		assertEq(clPoolFactory.tickSpacingInitialFee(3), 0);
	}

	// ============ Governance Function Tests ============

	function testEnableTickSpacingWithInvalidFee() public {
		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("FEE_TOO_HIGH()"));
		clPoolFactory.enableTickSpacing(15, 1_000_000); // Fee too high
	}

	function testEnableTickSpacingWithInvalidTickSpacing() public {
		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("INVALID_TICK_SPACING()"));
		clPoolFactory.enableTickSpacing(0, 100); // Zero tick spacing

		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("INVALID_TICK_SPACING()"));
		clPoolFactory.enableTickSpacing(16384, 100); // Too high tick spacing
	}

	function testEnableTickSpacingAlreadyEnabled() public {
		vm.prank(ACCESS_HUB);
		clPoolFactory.enableTickSpacing(15, 100);

		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("ZERO_FEE()"));
		clPoolFactory.enableTickSpacing(15, 200); // Already enabled
	}

	function testEnableTickSpacingNonGovernance() public {
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.enableTickSpacing(15, 100);
	}

	function testSetFeeProtocol() public {
		uint8 newFeeProtocol = 10;

		vm.prank(ACCESS_HUB);
		vm.expectEmit();
		emit IRamsesV3Factory.SetFeeProtocol(5, newFeeProtocol);
		clPoolFactory.setFeeProtocol(newFeeProtocol);
		assertEq(clPoolFactory.feeProtocol(), newFeeProtocol);
	}

	function testSetFeeProtocolTooHigh() public {
		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("FEE_TOO_HIGH()"));
		clPoolFactory.setFeeProtocol(101); // > 100%
	}

	function testSetFeeProtocolNonGovernance() public {
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.setFeeProtocol(10);
	}

	function testSetPoolFeeProtocol() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);
		uint8 newFeeProtocol = 15;

		vm.prank(ACCESS_HUB);
		vm.expectEmit();
		emit IRamsesV3Factory.SetPoolFeeProtocol(pool, 5, newFeeProtocol);
		clPoolFactory.setPoolFeeProtocol(pool, newFeeProtocol);
		assertEq(clPoolFactory.poolFeeProtocol(pool), newFeeProtocol);
	}

	function testSetPoolFeeProtocolTooHigh() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("FEE_TOO_HIGH()"));
		clPoolFactory.setPoolFeeProtocol(pool, 101);
	}

	function testSetPoolFeeProtocolNonGovernance() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.setPoolFeeProtocol(pool, 15);
	}

	function testSetFeeCollector() public {
		address newFeeCollector = makeAddr("newFeeCollector");

		vm.prank(ACCESS_HUB);
		clPoolFactory.setFeeCollector(newFeeCollector);
		assertEq(clPoolFactory.feeCollector(), newFeeCollector);
	}

	function testSetFeeCollectorZeroAddress() public {
		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
		clPoolFactory.setFeeCollector(address(0));
	}

	function testSetFeeCollectorNonGovernance() public {
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.setFeeCollector(makeAddr("newFeeCollector"));
	}

	function testSetVoter() public {
		address newVoter = makeAddr("newVoter");

		vm.prank(ACCESS_HUB);
		clPoolFactory.setVoter(newVoter);
		assertEq(clPoolFactory.voter(), newVoter);
	}

	function testSetVoterZeroAddress() public {
		vm.prank(ACCESS_HUB);
		vm.expectRevert(abi.encodeWithSignature("ZERO_ADDRESS()"));
		clPoolFactory.setVoter(address(0));
	}

	function testSetVoterNonGovernance() public {
		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.setVoter(makeAddr("newVoter"));
	}

	function testSetFeeNonGovernance() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(alice);
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED()"));
		clPoolFactory.setFee(pool, 5000);
	}

	// ============ Pool Fee Protocol Tests ============

	function testPoolFeeProtocolDefault() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		// Should return default fee protocol (5) when no specific fee is set
		assertEq(clPoolFactory.poolFeeProtocol(pool), 5);
	}

	function testPoolFeeProtocolCustom() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(ACCESS_HUB);
		clPoolFactory.setPoolFeeProtocol(pool, 20);

		assertEq(clPoolFactory.poolFeeProtocol(pool), 20);
	}

	// ============ Gauge Fee Split Tests ============

	function testGaugeFeeSplitEnableByVoter() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(VOTER);
		clPoolFactory.gaugeFeeSplitEnable(pool);

		// Should set fee protocol to 100 when called by voter
		assertEq(clPoolFactory.poolFeeProtocol(pool), 100);
	}

	function testGaugeFeeSplitEnableByNonVoter() public {
		address pool = clPoolFactory.createPool(address(token0), address(token1), 5, 1 * 2 ** 96);

		vm.prank(alice);
		clPoolFactory.gaugeFeeSplitEnable(pool);

		// Should not change fee protocol when called by non-voter
		assertEq(clPoolFactory.poolFeeProtocol(pool), 5);
	}

	// ============ Initialize Function Tests ============

	function testInitializeFunction() public {
		address newDeployer = makeAddr("newDeployer");

		vm.prank(address(clPoolDeployer));
		clPoolFactory.initialize(newDeployer);

		assertEq(clPoolFactory.ramsesV3PoolDeployer(), newDeployer);
	}

	function testInitializeNonDeployer() public {
		vm.prank(alice);
		vm.expectRevert();
		clPoolFactory.initialize(makeAddr("newDeployer"));
	}

	// ============ Parameters Tests ============

	function testParametersDuringPoolCreation() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		// Parameters should be set during pool creation
		clPoolFactory.createPool(address(token0), address(token1), tickSpacing, sqrtPriceX96);

		// Parameters should be cleared after pool creation
		(
			address factory,
			address token0Param,
			address token1Param,
			uint24 fee,
			int24 tickSpacingParam
		) = clPoolFactory.parameters();
		assertEq(factory, address(0));
		assertEq(token0Param, address(0));
		assertEq(token1Param, address(0));
		assertEq(fee, 0);
		assertEq(tickSpacingParam, 0);
	}

	// ============ Edge Cases and Error Handling ============

	function testCreatePoolWithTokenOrdering() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		// Create pool with tokens in reverse order
		address poolAddress1 = clPoolFactory.createPool(
			address(token1), // Higher address
			address(token0), // Lower address
			tickSpacing,
			sqrtPriceX96
		);

		// Should get the same pool address regardless of token order
		address poolAddress2 = clPoolFactory.getPool(address(token0), address(token1), tickSpacing);
		assertEq(poolAddress1, poolAddress2);
	}

	function testCreatePoolWithHighSqrtPrice() public {
		int24 tickSpacing = 5;
		uint160 sqrtPriceX96 = 2 ** 96 * 1000; // High but reasonable value

		address poolAddress = clPoolFactory.createPool(
			address(token0),
			address(token1),
			tickSpacing,
			sqrtPriceX96
		);

		assertEq(poolAddress, clPoolFactory.getPool(address(token0), address(token1), tickSpacing));
	}

	function testMultiplePoolsSameTokensDifferentTickSpacing() public {
		uint160 sqrtPriceX96 = 1 * 2 ** 96;

		address pool1 = clPoolFactory.createPool(address(token0), address(token1), 1, sqrtPriceX96);
		address pool5 = clPoolFactory.createPool(address(token0), address(token1), 5, sqrtPriceX96);
		address pool10 = clPoolFactory.createPool(
			address(token0),
			address(token1),
			10,
			sqrtPriceX96
		);

		// All should be different pools
		assertTrue(pool1 != pool5);
		assertTrue(pool1 != pool10);
		assertTrue(pool5 != pool10);

		// Each should be retrievable by their respective tick spacing
		assertEq(clPoolFactory.getPool(address(token0), address(token1), 1), pool1);
		assertEq(clPoolFactory.getPool(address(token0), address(token1), 5), pool5);
		assertEq(clPoolFactory.getPool(address(token0), address(token1), 10), pool10);
	}
}
