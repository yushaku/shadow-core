// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "test/mocks/WETH9.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";

contract Helper is Script {
	struct Config {
		address WETH;
		address deployer;
		address permit2;
	}

	Config internal config;

	constructor() {
		if (block.chainid == 11155111) {
			config = getSepolia();
		} else if (block.chainid == 97) {
			config = getBSCTestnet();
		} else {
			config = getLocal();
		}
	}

	// function run() public {
	// 	bytes32 storageLocation = keccak256(
	// 		abi.encode(uint256(keccak256("ysk.treasury.helper.v1")) - 1)
	// 	) & ~bytes32(uint256(0xff));
	// 	console.log("storageLocation", vm.toString(storageLocation));
	// }

	function getConfig() public view returns (Config memory) {
		return config;
	}

	function getSepolia() public pure returns (Config memory) {
		return Config({WETH: address(0), deployer: address(0), permit2: address(0)});
	}

	function getBSCTestnet() public view returns (Config memory) {
		address deployer = vm.envAddress("DEPLOYER_ADDRESS");
		return
			Config({
				WETH: address(0),
				deployer: deployer,
				permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3
			});
	}

	function getLocal() public returns (Config memory) {
		if (config.deployer != address(0)) {
			return config;
		}

		address deployer = vm.envAddress("DEPLOYER_ADDRESS");

		vm.startBroadcast(deployer);
		WETH9 weth = new WETH9();
		vm.stopBroadcast();

		return Config({WETH: address(weth), deployer: deployer, permit2: address(0)});
	}

	function getPath() public view returns (string memory) {
		return
			string.concat(
				vm.projectRoot(),
				"/deploy-addresses/",
				vm.toString(block.chainid),
				".json"
			);
	}

	function readAddress(string memory contractName) public view returns (address) {
		string memory path = getPath();
		if (!vm.exists(path)) return address(0);

		string memory json = vm.readFile(path);
		if (bytes(json).length == 0) return address(0);

		bytes memory raw = vm.parseJson(json, string.concat(".", contractName));
		return abi.decode(raw, (address));
	}

	function saveAddress(string memory contractName, address addr) public {
		string memory path = getPath();
		if (!vm.exists(path)) {
			vm.writeFile(path, "{}");
		}

		vm.writeJson(vm.toString(addr), path, string.concat(".", contractName));
	}
}
