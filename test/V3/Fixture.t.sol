// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {WETH9} from "test/mocks/WETH9.sol";

// import {AccessHub, IAccessHub} from "contracts/AccessHub.sol";
// import {FeeRecipientFactory} from "contracts/fee/FeeRecipientFactory.sol";
// import {FeeDistributorFactory} from "contracts/fee/FeeDistributorFactory.sol";
// import {Voter} from "contracts/Voter.sol";
// import {VoteModule} from "contracts/VoteModule.sol";
// import {Minter} from "contracts/Minter.sol";

import {RamsesV3Pool} from "contracts/CL/core/RamsesV3Pool.sol";
import {FeeCollector} from "contracts/CL/gauge/FeeCollector.sol";
import {ClGaugeFactory} from "contracts/CL/gauge/ClGaugeFactory.sol";
import {RamsesV3Factory} from "contracts/CL/core/RamsesV3Factory.sol";
import {RamsesV3PoolDeployer} from "contracts/CL/core/RamsesV3PoolDeployer.sol";
import {NonfungiblePositionManager} from "contracts/CL/periphery/NonfungiblePositionManager.sol";
import {NonfungibleTokenPositionDescriptor} from "contracts/CL/periphery/NonfungibleTokenPositionDescriptor.sol";
import {SwapRouter} from "contracts/CL/periphery/SwapRouter.sol";
import {UniversalRouter} from "contracts/CL/universalRouter/UniversalRouter.sol";

// import {DeployCoreScript} from "script/DeployCore.s.sol";
import {DeployCLScript} from "script/DeployCL.s.sol";

// import {SetupScript} from "script/Setup.s.sol";

contract Fixture is Test {
	address public constant OPERATOR = address(0x1);
	address public constant TREASURY = address(0x1);
	address public constant TIMELOCK = address(0x3);
	address public constant VOTER = address(0x4);
	address public constant ACCESS_HUB = address(0x5);

	// address public constant xYSKAddress = address(0x4);
	// address public constant yskAddress = address(0x5);
	// address public constant x33Address = address(0x6);

	// AccessHub public accessHub;
	// Voter public voter;
	// VoteModule public voteModule;
	// Minter public minter;
	// FeeRecipientFactory public feeRecipientFactory;
	// FeeDistributorFactory public feeDistributorFactory;

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
	MockERC20 public token6Decimals;

	address public alice = makeAddr("alice");
	address public carol = makeAddr("carol");
	address public bob = makeAddr("bob");

	function setUp() public virtual {
		WETH = new WETH9();

		// _deployCore();
		_deployCL();
		_setup();

		token0 = new MockERC20("Token0", "TK0", 18);
		token1 = new MockERC20("Token1", "TK1", 18);
		token6Decimals = new MockERC20("Token6Decimals", "TK6D", 6);
	}

	// function _deployCore() internal {
	// 	DeployCoreScript deployCore = new DeployCoreScript();
	// 	(
	// 		address _accessHub,
	// 		address _voter,
	// 		address _voteModule,
	// 		address _minter,
	// 		address _feeRecipientFactory,
	// 		address _feeDistributorFactory
	// 	) = deployCore.run();

	// 	accessHub = AccessHub(_accessHub);
	// 	voter = Voter(_voter);
	// 	voteModule = VoteModule(_voteModule);
	// 	minter = Minter(_minter);
	// 	feeRecipientFactory = FeeRecipientFactory(_feeRecipientFactory);
	// 	feeDistributorFactory = FeeDistributorFactory(_feeDistributorFactory);
	// }

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
			address _universalRouter
		) = deployCL.forTest(address(ACCESS_HUB), address(VOTER), address(TREASURY), address(0));

		clPoolFactory = RamsesV3Factory(_clPoolFactory);
		clPoolDeployer = RamsesV3PoolDeployer(_clPoolDeployer);
		clGaugeFactory = ClGaugeFactory(_clGaugeFactory);
		clFeeCollector = FeeCollector(_clFeeCollector);
		nfpManager = NonfungiblePositionManager(payable(_nfpManager));
		nfpDescriptor = NonfungibleTokenPositionDescriptor(_nfpDescriptor);
		swapRouter = SwapRouter(payable(_swapRouter));
		universalRouter = UniversalRouter(payable(_universalRouter));
	}

	function _setup() internal {
		vm.startPrank(ACCESS_HUB);
		clPoolFactory.setFeeCollector(address(clFeeCollector));
		clPoolFactory.setVoter(VOTER);
		vm.stopPrank();
	}
}
