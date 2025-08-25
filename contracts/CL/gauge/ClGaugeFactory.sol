// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IClGaugeFactory} from "./interfaces/IClGaugeFactory.sol";
import {GaugeV3} from "./GaugeV3.sol";

/// @title Canonical CL gauge factory
contract ClGaugeFactory is IClGaugeFactory {
	error NOT_AUTHORIZED();
  error GAUGE_EXIST();

	address public immutable override nfpManager;
	address public immutable override voter;
	address public immutable override feeCollector;

	/// @inheritdoc IClGaugeFactory
	mapping(address => address) public override getGauge;

	constructor(address _nfpManager, address _voter, address _feeCollector) {
		nfpManager = _nfpManager;
		voter = _voter;
		feeCollector = _feeCollector;

		emit OwnerChanged(address(0), msg.sender);
	}

	/// @inheritdoc IClGaugeFactory
	function createGauge(address pool) external override returns (address gauge) {
		require(msg.sender == voter, NOT_AUTHORIZED());
		require(getGauge[pool] == address(0), GAUGE_EXIST());

		gauge = address(new GaugeV3(voter, nfpManager, feeCollector, pool));
		getGauge[pool] = gauge;
		emit GaugeCreated(pool, gauge);
	}
}
