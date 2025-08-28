// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {ContractDeployer} from "contracts/ContractDeployer.sol";

contract Deployer is Script {
	ContractDeployer public deployer;

	function run() public {
		vm.startBroadcast();

		bytes32 salt = bytes32(0);
		address owner = vm.envAddress("DEPLOYER_ADDRESS");
		deployer = new ContractDeployer{salt: salt}(owner);

		vm.stopBroadcast();
	}
}
