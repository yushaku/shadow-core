// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "contracts/AccessHub.sol";
import "contracts/VoteModule.sol";
import "contracts/Voter.sol";
import "contracts/Minter.sol";

import "./Helper.s.sol";

contract SetupScript is Script {
	address public immutable TREASURY;

	Helper.Config public config;
	Helper helper;

	AccessHub public accessHub;
	Voter public voter;
	Minter public minter;
	VoteModule public voteModule;

	constructor() {
		helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
		TREASURY = config.deployer;

		address accessHubAddress = helper.readAddress("AccessHub");
		address voterAddress = helper.readAddress("Voter");
		address minterAddress = helper.readAddress("Minter");
		address voteModuleAddress = helper.readAddress("VoteModule");

		require(accessHubAddress != address(0), "AccessHub address not found in deployment");
		require(voterAddress != address(0), "Voter address not found in deployment");
		require(minterAddress != address(0), "Minter address not found in deployment");
		require(voteModuleAddress != address(0), "VoteModule address not found in deployment");

		accessHub = AccessHub(accessHubAddress);
		voter = Voter(voterAddress);
		minter = Minter(minterAddress);
		voteModule = VoteModule(voteModuleAddress);
	}

	function run() public {
		vm.startBroadcast(config.deployer);

		address operator = config.deployer;

		// Read all required addresses
		address pairFactoryAddress = helper.readAddress("PairFactory");
		address gaugeFactoryAddress = helper.readAddress("GaugeFactory");
		address feeDistributorFactoryAddress = helper.readAddress("FeeDistributorFactory");
		address clPoolFactoryAddress = helper.readAddress("CLPoolFactory");
		address clGaugeFactoryAddress = helper.readAddress("CLGaugeFactory");
		address nfpManagerAddress = helper.readAddress("NFPManager");
		address feeRecipientFactoryAddress = helper.readAddress("FeeRecipientFactory");
		address launcherPluginAddress = helper.readAddress("LauncherPlugin");
		address yskAddress = helper.readAddress("ysk");
		address xYSKAddress = helper.readAddress("xYSK");
		address x33Address = helper.readAddress("x33");
		address feeCollectorAddress = helper.readAddress("FeeCollector");

		// Validate all addresses
		require(pairFactoryAddress != address(0));
		require(gaugeFactoryAddress != address(0));
		require(feeDistributorFactoryAddress != address(0));
		require(clPoolFactoryAddress != address(0));
		require(clGaugeFactoryAddress != address(0));
		require(nfpManagerAddress != address(0));
		require(feeRecipientFactoryAddress != address(0));
		require(launcherPluginAddress != address(0));

		voteModule.setUp(xYSKAddress);
		voter.setUp(
			yskAddress,
			pairFactoryAddress,
			gaugeFactoryAddress,
			feeDistributorFactoryAddress,
			address(minter),
			operator,
			xYSKAddress,
			clPoolFactoryAddress,
			clGaugeFactoryAddress,
			nfpManagerAddress,
			feeRecipientFactoryAddress,
			address(voteModule),
			launcherPluginAddress
		);

		uint256 weeklyEmissions = 100_000e18;
		uint256 emissionsMultiplier = 10_000;
		minter.kickoff(
			yskAddress,
			xYSKAddress,
			address(voter),
			weeklyEmissions,
			emissionsMultiplier
		);

		IAccessHub.InitParams memory params = IAccessHub.InitParams({
			timelock: operator,
			treasury: TREASURY,
			voter: address(voter),
			minter: address(minter),
			launcherPlugin: launcherPluginAddress,
			xYSK: xYSKAddress,
			x33: x33Address,
			ramsesV3PoolFactory: clPoolFactoryAddress,
			poolFactory: pairFactoryAddress,
			clGaugeFactory: clGaugeFactoryAddress,
			gaugeFactory: gaugeFactoryAddress,
			feeRecipientFactory: feeRecipientFactoryAddress,
			feeDistributorFactory: feeDistributorFactoryAddress,
			feeCollector: feeCollectorAddress,
			voteModule: address(voteModule)
		});
		accessHub.setup(params);
		vm.stopBroadcast();
	}
}
