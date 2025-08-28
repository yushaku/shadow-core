// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "contracts/YSK.sol";
import "contracts/x/XYSK.sol";
import "contracts/x/x33.sol";
import "contracts/ContractDeployer.sol";

import "./Helper.s.sol";

contract DeployScript is Script {
	Helper.Config public config;
	Helper helper;

	YSK public ysk;
	XYSK public xYSK;
	X33 public x33;

	constructor() {
		helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function run() public returns (address, address, address) {
		address operator = config.deployer;
		address voter = helper.readAddress("Voter");
		address accessHub = helper.readAddress("AccessHub");
		address voteModule = helper.readAddress("VoteModule");
		address minter = helper.readAddress("Minter");
		address contractDeployer = helper.readAddress("ContractDeployer");

		if (
			voter == address(0) ||
			accessHub == address(0) ||
			voteModule == address(0) ||
			minter == address(0)
		) {
			revert("Core Contracts not deployed");
		}

		vm.startBroadcast(operator);
		console.log("operator", operator);
		console.log("minter", minter);
		console.log("voter", voter);
		console.log("accessHub", accessHub);
		console.log("voteModule", voteModule);
		console.log("msg.sender", msg.sender);

		ContractDeployer deployer = ContractDeployer(contractDeployer);

		address yskAddress = helper.readAddress("YSK");
		if (yskAddress == address(0)) {
			bytes32 salt = 0x000000000000000000000000000000000000000000000000000000000011cee8;
			bytes memory bytecode = abi.encodePacked(type(YSK).creationCode, abi.encode(minter));
			yskAddress = deployer.deploy(bytecode, uint256(salt));
			ysk = YSK(yskAddress);
		}

		address xYSKAddress = helper.readAddress("XYSK");
		if (xYSKAddress == address(0)) {
			bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000034e87;
			bytes memory bytecode = abi.encodePacked(
				type(XYSK).creationCode,
				abi.encode(yskAddress, voter, operator, accessHub, voteModule, minter)
			);
			xYSKAddress = deployer.deploy(bytecode, uint256(salt));
			xYSK = XYSK(xYSKAddress);
		}

		address x33Address = helper.readAddress("X33");
		if (x33Address == address(0)) {
			bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000024cb8;
			bytes memory bytecode = abi.encodePacked(
				type(X33).creationCode,
				abi.encode(operator, accessHub, xYSK, voter, voteModule)
			);
			x33Address = deployer.deploy(bytecode, uint256(salt));
			x33 = X33(x33Address);
		}

		vm.stopBroadcast();

		return (yskAddress, xYSKAddress, x33Address);
	}
}
