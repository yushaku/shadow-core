// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/console2.sol";
import "forge-std/Script.sol";

import {Minter} from "contracts/Minter.sol";

contract DeployMinter is Script {
	function setUp() public {}

	function run() public returns (Minter minter) {
		vm.startBroadcast();

		minter = new Minter(msg.sender, msg.sender);
		console2.log("Minter Deployed:", address(minter));

		vm.stopBroadcast();
	}
}
