// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IGauge} from "contracts/interfaces/IGauge.sol";
import {Gauge} from "contracts/legacy/Gauge.sol";

contract GaugeFactory {
	address public lastGauge;

	function createGauge(address _pool) external returns (address) {
		lastGauge = address(new Gauge(_pool, msg.sender));

		return lastGauge;
	}
}
