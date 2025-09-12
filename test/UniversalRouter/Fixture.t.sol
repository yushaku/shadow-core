// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {WETH9} from "test/mocks/WETH9.sol";

import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";

import "contracts/legacy/factories/GaugeFactory.sol";
import "contracts/legacy/factories/PairFactory.sol";
import "contracts/legacy/LauncherPlugin.sol";
import "contracts/legacy/Router.sol";

import {RamsesV3Pool} from "contracts/CL/core/RamsesV3Pool.sol";
import {FeeCollector} from "contracts/CL/gauge/FeeCollector.sol";
import {ClGaugeFactory} from "contracts/CL/gauge/ClGaugeFactory.sol";
import {RamsesV3Factory} from "contracts/CL/core/RamsesV3Factory.sol";
import {RamsesV3PoolDeployer} from "contracts/CL/core/RamsesV3PoolDeployer.sol";
import {NonfungiblePositionManager} from "contracts/CL/periphery/NonfungiblePositionManager.sol";
import {NonfungibleTokenPositionDescriptor} from "contracts/CL/periphery/NonfungibleTokenPositionDescriptor.sol";
import {SwapRouter} from "contracts/CL/periphery/SwapRouter.sol";
import {UniversalRouter} from "contracts/universalRouter/UniversalRouter.sol";

import {DeployCLScript} from "script/DeployCL.s.sol";
import {DeployURouterScript, Helper} from "script/DeployURouter.s.sol";
import {DeployLegacyScript} from "script/DeployLegacy.s.sol";

contract Fixture is Test {
	address public constant OPERATOR = address(0x1);
	address public constant TREASURY = address(0x1);
	address public constant TIMELOCK = address(0x3);
	address public constant VOTER = address(0x4);
	address public constant ACCESS_HUB = address(0x5);
	address public constant FEE_RECIPIENT_FACTORY = address(0x6);

	IPermit2 public permit2;

	GaugeFactory public gaugeFactory;
	PairFactory public pairFactory;
	LauncherPlugin public launcherPlugin;
	Router public router;

	RamsesV3Pool public clPool;
	FeeCollector public clFeeCollector;
	ClGaugeFactory public clGaugeFactory;
	RamsesV3Factory public clPoolFactory;
	RamsesV3PoolDeployer public clPoolDeployer;
	NonfungiblePositionManager public nfpManager;
	NonfungibleTokenPositionDescriptor public nfpDescriptor;
	SwapRouter public swapRouter;

	UniversalRouter public universalRouter;

	WETH9 public WETH;
	MockERC20 public token0;
	MockERC20 public token1;

	address public alice = makeAddr("alice");
	address public carol = makeAddr("carol");
	address public bob = makeAddr("bob");

	function setUp() public virtual {
		vm.createFork("bsc_testnet");
		vm.selectFork(0);

		_deployLegacy();
		_deployCL();
		_setup();

		token0 = new MockERC20("Token0", "TK0", 18);
		token1 = new MockERC20("Token1", "TK1", 18);
	}

	function _deployLegacy() internal {
		DeployLegacyScript deployLegacy = new DeployLegacyScript();
		(
			address _gaugeFactory,
			address _pairFactory,
			address _launcherPlugin,
			address _router
		) = deployLegacy.forTest(ACCESS_HUB, VOTER, TREASURY, FEE_RECIPIENT_FACTORY, OPERATOR);

		gaugeFactory = GaugeFactory(_gaugeFactory);
		pairFactory = PairFactory(_pairFactory);
		launcherPlugin = LauncherPlugin(_launcherPlugin);
		router = Router(payable(_router));
	}

	function _deployCL() internal {
		DeployCLScript deployCL = new DeployCLScript();
		(
			address _clPoolFactory,
			address _clPoolDeployer,
			address _clGaugeFactory,
			address _clFeeCollector,
			address _nfpManager,
			address _nfpDescriptor,
			address _swapRouter,
			,

		) = deployCL.forTest(address(ACCESS_HUB), address(VOTER), address(TREASURY));

		clPoolFactory = RamsesV3Factory(_clPoolFactory);
		clPoolDeployer = RamsesV3PoolDeployer(_clPoolDeployer);
		clGaugeFactory = ClGaugeFactory(_clGaugeFactory);
		clFeeCollector = FeeCollector(_clFeeCollector);
		nfpManager = NonfungiblePositionManager(payable(_nfpManager));
		nfpDescriptor = NonfungibleTokenPositionDescriptor(_nfpDescriptor);
		swapRouter = SwapRouter(payable(_swapRouter));

		DeployURouterScript deployURouter = new DeployURouterScript();
		(address _universalRouter) = deployURouter.forTest(
			address(pairFactory),
			_clPoolDeployer,
			_nfpManager
		);
		universalRouter = UniversalRouter(payable(_universalRouter));

		address weth = swapRouter.WETH9();
		WETH = WETH9(payable(weth));
		Helper.Config memory _config = deployURouter.getConfig();
		permit2 = IPermit2(payable(_config.permit2));
	}

	function _setup() internal {
		vm.startPrank(ACCESS_HUB);
		clPoolFactory.setFeeCollector(address(clFeeCollector));
		clPoolFactory.setVoter(VOTER);
		vm.stopPrank();
	}
}
