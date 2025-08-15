// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/console2.sol";
import "forge-std/Script.sol";

import {YSK} from "contracts/YSK.sol";

bytes32 constant SALT = bytes32(
	uint256(0x00000000000000000000000000000000000000000000000000000000000a1039)
);

contract DeployYSK is Script {
	function setUp() public pure {
		// get minter address from environment variable or use a default
	}

	function run() public returns (YSK ysk) {
		// Calculate the predicted address before deployment
		address deployer = vm.envUint("DEPLOYER_ADDRESS");
		bytes memory creationCode = abi.encodePacked(type(YSK).creationCode, deployer);

		// THAY ĐỔI QUAN TRỌNG: Dùng `address(this)` thay vì `msg.sender`
		bytes32 hash = keccak256(
			abi.encodePacked(bytes1(0xff), address(this), SALT, keccak256(creationCode))
		);

		address predictedAddress = address(uint160(uint256(hash)));
		console2.log("--- Prediction ---");
		console2.log("Script contract address (actual deployer):", address(this));
		console2.log("Broadcaster (your EOA):", deployer);
		console2.log("Predicted YSK address:", predictedAddress);
		console2.log("Salt:", vm.toString(SALT));

		// vm.startBroadcast();

		// ysk = new YSK{salt: SALT}(deployer);

		// vm.stopBroadcast();

		// console2.log("--- Deployment ---");
		// console2.log("YSK Deployed at:", address(ysk));

		// // So sánh kết quả
		// assertEq(predictedAddress, address(ysk));
		// console2.log("✅ Prediction matches deployment!");
	}
}
