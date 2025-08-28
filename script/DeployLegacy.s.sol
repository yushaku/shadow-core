// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "contracts/legacy/factories/GaugeFactory.sol";
import "contracts/legacy/factories/PairFactory.sol";
import "contracts/legacy/LauncherPlugin.sol";
import "contracts/legacy/Router.sol";

import "./Helper.s.sol";

contract DeployLegacy is Script {
	Helper.Config public config;
	Helper helper;

	constructor() {
		helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function run() public returns (address, address, address, address) {
		address accessHubAddress = helper.readAddress("AccessHub");
		address voterAddress = helper.readAddress("Voter");
		address voteModuleAddress = helper.readAddress("VoteModule");
		address feeRecipientFactoryAddress = helper.readAddress("FeeRecipientFactory");
		address treasuryAddress = config.deployer;
		address operator = config.deployer;

		if (
			accessHubAddress == address(0) ||
			voterAddress == address(0) ||
			voteModuleAddress == address(0) ||
			feeRecipientFactoryAddress == address(0)
		) revert("Core Contracts not deployed");

		return
			_deploy(
				accessHubAddress,
				voterAddress,
				treasuryAddress,
				feeRecipientFactoryAddress,
				operator
			);
	}

	function forTest(
		address _accessHubAddress,
		address _voterAddress,
		address _treasuryAddress,
		address _feeRecipientFactoryAddress,
		address _operator
	) public returns (address, address, address, address) {
		return
			_deploy(
				_accessHubAddress,
				_voterAddress,
				_treasuryAddress,
				_feeRecipientFactoryAddress,
				_operator
			);
	}

	function _deploy(
		address _accessHubAddress,
		address _voterAddress,
		address _treasuryAddress,
		address _feeRecipientFactoryAddress,
		address _operator
	) internal returns (address, address, address, address) {
		vm.startBroadcast(config.deployer);

		GaugeFactory gaugeFactory = new GaugeFactory();

		PairFactory pairFactory = new PairFactory(
			_voterAddress,
			_treasuryAddress,
			_accessHubAddress,
			_feeRecipientFactoryAddress
		);

		LauncherPlugin launcherPlugin = new LauncherPlugin(
			_voterAddress,
			_accessHubAddress,
			_operator
		);

		Router router = new Router(address(pairFactory), config.WETH);

		vm.stopBroadcast();

		return (
			address(gaugeFactory),
			address(pairFactory),
			address(launcherPlugin),
			address(router)
		);
	}
}
