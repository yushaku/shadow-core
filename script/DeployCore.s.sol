// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "contracts/AccessHub.sol";
import "contracts/VoteModule.sol";
import "contracts/Voter.sol";
import "contracts/Minter.sol";

import "contracts/legacy/factories/FeeRecipientFactory.sol";
import "contracts/legacy/factories/FeeDistributorFactory.sol";
import "contracts/Timelock.sol";

import "./Helper.s.sol";

contract DeployCoreScript is Script {
	Helper.Config public config;

	AccessHub public accessHub;
	Minter public minter;
	VoteModule public voteModule;
	Voter public voter;
	FeeRecipientFactory public feeRecipientFactory;
	FeeDistributorFactory public feeDistributorFactory;

	constructor() {
		console.log(block.chainid);
		Helper helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function run() public returns (address, address, address, address, address, address) {
		vm.startBroadcast(config.deployer);

		bytes memory initAccessHub = abi.encodeWithSelector(
			IAccessHub.initialize.selector,
			config.deployer
		);
		AccessHub accessHubImplement = new AccessHub();
		ERC1967Proxy accessHubProxy = new ERC1967Proxy(address(accessHubImplement), initAccessHub);
		accessHub = AccessHub(address(accessHubProxy));

		bytes memory initVoter = abi.encodeWithSelector(
			IVoter.initialize.selector,
			config.deployer,
			address(accessHub)
		);
		Voter voterImplement = new Voter();
		ERC1967Proxy voterProxy = new ERC1967Proxy(address(voterImplement), initVoter);
		voter = Voter(address(voterProxy));

		bytes memory initVoteModule = abi.encodeWithSelector(
			VoteModule.initialize.selector,
			config.deployer,
			address(voter),
			address(accessHub)
		);
		VoteModule voteModuleImplement = new VoteModule();
		ERC1967Proxy voteModuleProxy = new ERC1967Proxy(
			address(voteModuleImplement),
			initVoteModule
		);
		voteModule = VoteModule(address(voteModuleProxy));

		minter = new Minter(address(accessHub), config.deployer);

		feeDistributorFactory = new FeeDistributorFactory();

		feeRecipientFactory = new FeeRecipientFactory(
			config.deployer,
			address(voter),
			address(accessHub)
		);

		vm.stopBroadcast();

		return (
			address(accessHub),
			address(voter),
			address(voteModule),
			address(minter),
			address(feeRecipientFactory),
			address(feeDistributorFactory)
		);
	}
}
