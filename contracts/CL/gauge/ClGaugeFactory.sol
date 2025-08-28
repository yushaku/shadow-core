// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IClGaugeFactory} from "./interfaces/IClGaugeFactory.sol";
import {GaugeV3} from "./GaugeV3.sol";

/// @title Canonical CL gauge factory
contract ClGaugeFactory is IClGaugeFactory {
	address public immutable override nfpManager;
	address public immutable override voter;
	address public immutable override feeCollector;

	mapping(address pool => address gauge) public override getGauge;

	constructor(address _nfpManager, address _voter, address _feeCollector) {
		nfpManager = _nfpManager;
		voter = _voter;
		feeCollector = _feeCollector;
	}

	/**
	 * @notice Creates a gauge for the given pool
	 * @param pool One of the desired gauge
	 * @return gauge The address of the newly created gauge
	 */
	function createGauge(address pool) external override returns (address gauge) {
		require(msg.sender == voter, NOT_AUTHORIZED());
		require(getGauge[pool] == address(0), GAUGE_EXIST());

		gauge = address(new GaugeV3(voter, nfpManager, feeCollector, pool));
		getGauge[pool] = gauge;

		emit GaugeCreated(pool, gauge);
	}
}
