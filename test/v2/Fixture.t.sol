// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import "test/mocks/MockERC20.sol";
import "test/mocks/WETH9.sol";
import "script/DeployLegacy.s.sol";

// import "contracts/fee/FeeRecipientFactory.sol";
// import "contracts/fee/FeeDistributorFactory.sol";
import "contracts/legacy/factories/GaugeFactory.sol";
import "contracts/legacy/factories/PairFactory.sol";
import "contracts/legacy/LauncherPlugin.sol";
import "contracts/legacy/Router.sol";

contract Fixture is Test {
	address public constant OPERATOR = address(0x1);
	address public constant TREASURY = address(0x1);
	address public constant TIMELOCK = address(0x3);
	address public constant VOTER = address(0x4);
	address public constant ACCESS_HUB = address(0x5);
	address public constant FEE_RECIPIENT_FACTORY = address(0x6);

	GaugeFactory public gaugeFactory;
	PairFactory public pairFactory;
	LauncherPlugin public launcherPlugin;
	Router public router;

	WETH9 public WETH;
	MockERC20 public token0;
	MockERC20 public token1;
	MockERC20 public token6Decimals;

	address public alice = makeAddr("alice");
	address public carol = makeAddr("carol");
	address public bob = makeAddr("bob");

	function setUp() public virtual {
		_deploy();
		_setup();

		token0 = new MockERC20("Token0", "TK0", 18);
		token1 = new MockERC20("Token1", "TK1", 18);
		token6Decimals = new MockERC20("Token6Decimals", "TK6D", 6);
	}

	function _deploy() internal {
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

		WETH = WETH9(payable(router.WETH()));
	}

	function _setup() internal {
		vm.startPrank(ACCESS_HUB);
		// clPoolFactory.setFeeCollector(address(clFeeCollector));
		// clPoolFactory.setVoter(VOTER);
		vm.stopPrank();
	}
}
