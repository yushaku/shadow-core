// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Gauge} from "contracts/legacy/Gauge.sol";
import {IGaugeFactory} from "contracts/interfaces/IGaugeFactory.sol";

contract GaugeFactory is IGaugeFactory {
	address public lastGauge;

	function createGauge(address _pool) external returns (address) {
		lastGauge = address(new Gauge(_pool, msg.sender));

		return lastGauge;
	}
}
