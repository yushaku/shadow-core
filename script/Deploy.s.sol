// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "contracts/AccessHub.sol";
import "contracts/VoteModule.sol";
import "contracts/Voter.sol";

import "contracts/Minter.sol";
import "contracts/YSK.sol";
import "contracts/x/XY.sol";
import "contracts/x/x33.sol";
// import {Treasury} from "contracts/Treasury.sol"

import "contracts/legacy/factories/GaugeFactory.sol";
import "contracts/legacy/factories/PairFactory.sol";
import "contracts/legacy/factories/FeeRecipientFactory.sol";
import "contracts/legacy/factories/FeeDistributorFactory.sol";
import "contracts/legacy/LauncherPlugin.sol";
import "contracts/legacy/Router.sol";

import "./Helper.s.sol";

contract DeployScript is Script {
	Helper.Config public config;

	address[] public tokens;

	AccessHub public accessHub;
	VoteModule public voteModule;
	Voter public voter;

	Minter public minter;
	YSK public ysk;
	XY public xYSK;
	X33 public x33;

	PairFactory public pairFactory;
	GaugeFactory public gaugeFactory;
	FeeRecipientFactory public feeRecipientFactory;
	FeeDistributorFactory public feeDistributorFactory;
	LauncherPlugin public launcherPlugin;
	Router public router;

	// TODO: deploy treasury contract
	address public _treasury;

	constructor() {
		Helper helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
		_treasury = config.deployer;
	}

	function run() public {
		vm.startBroadcast();

		_deployCore();
		_deployTokens();
		_deployLegacy();

		_setUp();

		vm.stopBroadcast();
	}

	function _deployCore() internal {
		bytes memory initAccessHub = abi.encodeWithSelector(
			IAccessHub.initialize.selector,
			config.deployer
		);
		AccessHub accessHubImplement = new AccessHub();
		ERC1967Proxy accessHubProxy = new ERC1967Proxy(address(accessHubImplement), initAccessHub);
		accessHub = AccessHub(address(accessHubProxy));

		bytes memory initVoter = abi.encodeWithSelector(
			IVoter.initialize.selector,
			config.deployer
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
	}

	function _deployTokens() internal {
		address operator = config.deployer;

		minter = new Minter(address(accessHub), operator);

		ysk = new YSK(address(minter));
		tokens.push(address(ysk));

		xYSK = new XY(
			address(ysk),
			address(voter),
			operator,
			address(accessHub),
			address(voteModule),
			address(minter)
		);

		x33 = new X33(
			operator,
			address(accessHub),
			address(xYSK),
			address(voter),
			address(voteModule)
	);
	}

	function _deployLegacy() internal {
		gaugeFactory = new GaugeFactory();

		feeDistributorFactory = new FeeDistributorFactory();

		feeRecipientFactory = new FeeRecipientFactory(
			_treasury,
			address(voter),
			address(accessHub)
		);

		pairFactory = new PairFactory(
			address(voter),
			_treasury,
			address(accessHub),
			address(feeRecipientFactory)
		);

		launcherPlugin = new launcherPlugin(address(voter), address(accessHub), operator);

		router = new Router(address(pairFactory), config.WETH);
	}

	//TODO: setup core contracts with deployed liquidity/token contracts
	function _setUp() internal {
		address operator = config.deployer;

		voteModule.setUp(address(xYSK));
		voter.setUp(
			address(ysk),
			address(pairFactory),
			address(gaugeFactory),
			address(feeDistributorFactory),
			address(minter),
			operator,
			address(xYSK),
			// address _clFactory,
			// address _clGaugeFactory,
			// address _nfpManager,
			// address _feeRecipientFactory,
			address(voteModule),
			address(launcherPlugin)
		);

    uint256 weeklyEmissions = 17660997143544218356406;
    uint256 emissionsMultiplier = 10000;
    minter.kickoff(
      address(ysk),
      address(xYSK),
      address(voter),
      weeklyEmissions,
      emissionsMultiplier
    );
		// accessHub.setUp();
	}
}
