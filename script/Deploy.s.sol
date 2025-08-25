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
import "contracts/x/XYSK.sol";
import "contracts/x/x33.sol";
// import {Treasury} from "contracts/Treasury.sol"

import "contracts/legacy/factories/GaugeFactory.sol";
import "contracts/legacy/factories/PairFactory.sol";
import "contracts/legacy/factories/FeeRecipientFactory.sol";
import "contracts/legacy/factories/FeeDistributorFactory.sol";
import "contracts/legacy/LauncherPlugin.sol";
import "contracts/legacy/Router.sol";

import "contracts/CL/gauge/FeeCollector.sol";
import "contracts/CL/gauge/ClGaugeFactory.sol";
import "contracts/CL/core/RamsesV3Factory.sol";
import "contracts/CL/core/RamsesV3PoolDeployer.sol";
import "contracts/CL/periphery/NonfungiblePositionManager.sol";
import "contracts/CL/periphery/NonfungibleTokenPositionDescriptor.sol";
// import "contracts/CL/periphery/SwapRouter.sol";
import "contracts/CL/universalRouter/UniversalRouter.sol";

import "./Helper.s.sol";

contract DeployScript is Script {
	Helper.Config public config;

	address[] public tokens;

	// access control
	AccessHub public accessHub;

	// core
	Minter public minter;
	YSK public ysk;
	XYSK public xYSK;
	X33 public x33;
	VoteModule public voteModule;
	Voter public voter;

	// v2
	PairFactory public pairFactory;
	GaugeFactory public gaugeFactory;
	FeeRecipientFactory public feeRecipientFactory;
	FeeDistributorFactory public feeDistributorFactory;
	LauncherPlugin public launcherPlugin;
	Router public router;

	// v3
	// periphery
	NonfungiblePositionManager public nfpManager;
	NonfungibleTokenPositionDescriptor public nfpDescriptor;
	// SwapRouter public swapRouter;
	UniversalRouter public universalRouter;

	// pools
	RamsesV3Factory public clPoolFactory;
	RamsesV3PoolDeployer public clPoolDeployer;

	// gauges
	FeeCollector public clFeeCollector;
	ClGaugeFactory public clGaugeFactory;

	// TODO: deploy treasury contract
	address public _treasury;

	constructor() {
		Helper helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
		_treasury = config.deployer;
	}

	function run() public {
		vm.startBroadcast(config.deployer);

		_deployCore();
		_deployTokens();
		_deployLegacy();
		_deployCL();
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
	}

	function _deployTokens() internal {
		address operator = config.deployer;

		minter = new Minter(address(accessHub), operator);

		ysk = new YSK(address(minter));
		tokens.push(address(ysk));

		xYSK = new XYSK(
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

		launcherPlugin = new LauncherPlugin(address(voter), address(accessHub), config.deployer);

		router = new Router(address(pairFactory), config.WETH);
	}

	function _deployTreasury() internal {
		// Treasury treasuryImplement = new Treasury();
		// ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImplement), initTreasury);
		// treasury = Treasury(address(treasuryProxy));
	}

	function _deployCL() internal {
		clPoolFactory = new RamsesV3Factory(address(accessHub));
		clPoolDeployer = new RamsesV3PoolDeployer(address(clPoolFactory));
		clPoolFactory.initialize(address(clPoolDeployer));

		nfpDescriptor = new NonfungibleTokenPositionDescriptor(config.WETH);
		nfpManager = new NonfungiblePositionManager(
			address(clPoolDeployer),
			config.WETH,
			address(nfpDescriptor),
			address(accessHub)
		);

		//TODO:
		// SwapRouter = new SwapRouter(clPoolDeployer, config.WETH);
		// universalRouter = new UniversalRouter(pool);

		clFeeCollector = new FeeCollector(address(_treasury), address(voter));
		clGaugeFactory = new ClGaugeFactory(
			address(nfpManager),
			address(voter),
			address(clFeeCollector)
		);
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
			address(clPoolFactory),
			address(clGaugeFactory),
			address(nfpManager),
			address(feeRecipientFactory),
			address(voteModule),
			address(launcherPlugin)
		);

		uint256 weeklyEmissions = 100_000e18;
		uint256 emissionsMultiplier = 10_000;
		minter.kickoff(
			address(ysk),
			address(xYSK),
			address(voter),
			weeklyEmissions,
			emissionsMultiplier
		);

		IAccessHub.InitParams memory params = IAccessHub.InitParams({
			timelock: operator,
			treasury: _treasury,
			voter: address(voter),
			minter: address(minter),
			launcherPlugin: address(launcherPlugin),
			xYSK: address(xYSK),
			x33: address(x33),
			ramsesV3PoolFactory: address(clPoolFactory),
			poolFactory: address(pairFactory),
			clGaugeFactory: address(clGaugeFactory),
			gaugeFactory: address(gaugeFactory),
			feeRecipientFactory: address(feeRecipientFactory),
			feeDistributorFactory: address(feeDistributorFactory),
			feeCollector: address(clFeeCollector),
			voteModule: address(voteModule)
		});
		accessHub.setup(params);
	}

	function getConfig() public view returns (Helper.Config memory) {
		return config;
	}
}
