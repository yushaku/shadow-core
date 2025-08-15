// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {Permit2} from "permit2/src/Permit2.sol";

contract DeployPermit2Script is Script {
	bytes32 internal constant SALT =
		0x0000000000000000000000000000000000000000000000000000000000015c01;

	function run() external returns (Permit2 permit2) {
		vm.startBroadcast();
		permit2 = new Permit2{salt: SALT}();
		console.log("Permit2 deployed at:", address(permit2));
		vm.stopBroadcast();
	}
}
