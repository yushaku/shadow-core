// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// import {Permit2} from "permit2/src/Permit2.sol";
import {YSK} from "contracts/YSK.sol";

contract FindSaltScript is Script {
	address internal constant DEPLOYER = 0xd23714A6662eA86271765acF906AECA80EF7d6Fa;
	uint160 internal constant TARGET_PREFIX = uint160(0x000000000022D473030F116dDEE9F6B43aC78BA3);
	uint256 internal constant PREFIX_BITS = 16;

	function run() external pure {
		bytes memory initCode = type(YSK).creationCode;
		bytes32 initCodeHash = keccak256(initCode);

		console.log("Deployer:", DEPLOYER);
		console.logBytes32(initCodeHash);
		console.log("Start finding salt...");

		uint256 saltNonce = 0;
		bytes32 salt;
		address computedAddress;

		uint256 mask = (~uint256(0)) << (160 - PREFIX_BITS);

		while (true) {
			salt = bytes32(saltNonce);
			computedAddress = address(
				uint160(
					uint256(keccak256(abi.encodePacked(bytes1(0xff), DEPLOYER, salt, initCodeHash)))
				)
			);

			if (uint256(uint160(computedAddress)) & mask == uint256(TARGET_PREFIX) & mask) {
				console.log("Success! Found salt!");
				console.log("   -> Number of attempts:", saltNonce);
				console.log("   -> Salt (hex):");
				console.logBytes32(salt);
				console.log("   -> Created address:", computedAddress);
				break;
			}

			if (saltNonce > 0 && saltNonce % 500000 == 0) {
				console.log("Tried %s salts...", saltNonce);
			}

			if (saltNonce == type(uint64).max) {
				console.log("Not found salt after tried uint64.max times.");
				break;
			}

			saltNonce++;
		}
	}
}
