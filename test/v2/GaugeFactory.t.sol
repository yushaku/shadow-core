// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {GaugeFactory} from "contracts/legacy/factories/GaugeFactory.sol";
import {Gauge} from "contracts/legacy/Gauge.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";

import "test/Base.t.sol";

interface IMinimalPoolInterface {
	function token0() external view returns (address);
	function token1() external view returns (address);
}

contract GaugeFactoryTest is TheTestBase {
	GaugeFactory public factory;
	address public pool;

	function setUp() public override {
		super.setUp();

		// Deploy the factory
		factory = new GaugeFactory();

		// Create a mock pool address
		pool = makeAddr("pool");
	}

	function test_createGauge() public {
		// Create a new Gauge from voter address
		vm.prank(address(mockVoter));
		// Mock token0/token1 calls for pool
		vm.mockCall(
			pool,
			abi.encodeWithSelector(IMinimalPoolInterface.token0.selector),
			abi.encode(address(token0))
		);
		vm.mockCall(
			pool,
			abi.encodeWithSelector(IMinimalPoolInterface.token1.selector),
			abi.encode(address(token1))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.ysk.selector),
			abi.encode(address(makeAddr("ysk")))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.xYSK.selector),
			abi.encode(address(makeAddr("xYSK")))
		);
		address newGauge = factory.createGauge(pool);

		// Verify the lastGauge was updated
		assertEq(factory.lastGauge(), newGauge, "Last gauge not updated correctly");

		// Verify the Gauge was initialized correctly
		Gauge gauge = Gauge(newGauge);

		// Check all constructor-initialized variables
		assertEq(gauge.VOTER(), address(mockVoter), "Voter not set correctly");
		assertEq(gauge.STAKE(), pool, "Pool not set correctly");

		// Check that emissions token is in whitelist
		address ysk = IVoter(address(mockVoter)).ysk();
		assertTrue(gauge.isWhitelisted(ysk), "Emissions token not whitelisted");
	}

	function test_createGaugeMultiple() public {
		// Create first Gauge
		vm.prank(address(mockVoter));
		vm.mockCall(
			pool,
			abi.encodeWithSelector(IMinimalPoolInterface.token0.selector),
			abi.encode(address(makeAddr("token0")))
		);
		vm.mockCall(
			pool,
			abi.encodeWithSelector(IMinimalPoolInterface.token1.selector),
			abi.encode(address(makeAddr("token1")))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.ysk.selector),
			abi.encode(address(makeAddr("ysk")))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.xYSK.selector),
			abi.encode(address(makeAddr("xYSK")))
		);
		address firstGauge = factory.createGauge(pool);

		// Create second Gauge with different pool
		address secondPool = makeAddr("secondPool");
		vm.prank(address(mockVoter));
		vm.mockCall(
			secondPool,
			abi.encodeWithSelector(IMinimalPoolInterface.token0.selector),
			abi.encode(address(makeAddr("tokenv0")))
		);
		vm.mockCall(
			secondPool,
			abi.encodeWithSelector(IMinimalPoolInterface.token1.selector),
			abi.encode(address(makeAddr("tokenv1")))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.ysk.selector),
			abi.encode(address(makeAddr("ysk")))
		);
		vm.mockCall(
			address(this),
			abi.encodeWithSelector(IVoter.xYSK.selector),
			abi.encode(address(makeAddr("xYSK")))
		);
		address secondGauge = factory.createGauge(secondPool);

		// Verify they are different addresses
		assertTrue(firstGauge != secondGauge, "Gauges should have different addresses");

		// Verify lastGauge points to the most recent creation
		assertEq(factory.lastGauge(), secondGauge, "Last gauge should be the second one");

		// Verify both gauges were initialized with correct values
		Gauge gauge1 = Gauge(firstGauge);
		Gauge gauge2 = Gauge(secondGauge);

		// Check first gauge
		assertEq(gauge1.VOTER(), address(mockVoter), "First gauge voter not set correctly");
		assertEq(gauge1.STAKE(), pool, "First gauge stake not set correctly");
		assertTrue(
			gauge1.isWhitelisted(IVoter(address(mockVoter)).ysk()),
			"First gauge emissions token not whitelisted"
		);

		// Check second gauge
		assertEq(gauge2.VOTER(), address(mockVoter), "Second gauge voter not set correctly");
		assertEq(gauge2.STAKE(), secondPool, "Second gauge stake not set correctly");
		assertTrue(
			gauge2.isWhitelisted(IVoter(address(mockVoter)).ysk()),
			"Second gauge emissions token not whitelisted"
		);
	}
}
