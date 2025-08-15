// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "contracts/CL/core/test/WETH9.sol";

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

		address weth = new WETH9();

		return Config({WETH: weth, deployer: 0xd23714A6662eA86271765acF906AECA80EF7d6Fa});
	}
}
