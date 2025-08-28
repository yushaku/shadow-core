// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ContractDeployer is Ownable {
	address public lastContract;
	address[] public deployedContracts;

	constructor(address _owner) Ownable(_owner) {}

	function deploy(
		bytes memory bytecode,
		uint256 _salt
	) public onlyOwner returns (address contractAddress) {
		assembly {
			contractAddress := create2(0, add(bytecode, 32), mload(bytecode), _salt)
		}
		if (contractAddress == address(0)) revert("create2 failed");

		deployedContracts.push(contractAddress);
		lastContract = contractAddress;
	}

	function deployMany(
		bytes memory bytecode,
		uint256[] memory salts
	) external onlyOwner returns (address[] memory contractAddresses) {
		contractAddresses = new address[](salts.length);
		for (uint256 i; i < contractAddresses.length; ++i) {
			contractAddresses[i] = deploy(bytecode, salts[i]);
		}
	}

	function deployedContractsLength() external view returns (uint256) {
		return deployedContracts.length;
	}

	function getDeployedContracts() external view returns (address[] memory) {
		return deployedContracts;
	}
}
