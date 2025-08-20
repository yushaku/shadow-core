// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "test/mocks/WETH9.sol";
import "forge-std/console.sol";

contract Helper is Script {
	struct Config {
		address WETH;
		address deployer;
	}

	Config internal config;

	constructor() {
		if (block.chainid == 11155111) {
			config = getSepolia();
		} else {
			config = getLocal();
		}
	}

	function run() public {
		bytes32 storageLocation = keccak256(
			abi.encode(uint256(keccak256("ysk.treasury.helper.v1")) - 1)
		) & ~bytes32(uint256(0xff));
		console.log("storageLocation", vm.toString(storageLocation));
	}

	function getConfig() public view returns (Config memory) {
		return config;
	}

	function getSepolia() public pure returns (Config memory) {
		return Config({WETH: address(0), deployer: address(0)});
	}

	function getLocal() public returns (Config memory) {
		if (config.deployer != address(0)) {
			return config;
		}

		address deployer = vm.envAddress("DEPLOYER_ADDRESS");

		vm.startBroadcast(deployer);
		WETH9 weth = new WETH9();
		vm.stopBroadcast();

		return Config({WETH: address(weth), deployer: deployer});
	}
}
