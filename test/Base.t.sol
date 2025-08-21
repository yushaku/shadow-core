// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./mocks/MockERC20.sol";
import "./mocks/WETH9.sol";
import "./mocks/MockX33.sol";

import {YSK} from "contracts/YSK.sol";
// import {XY} from "contracts/x/XY.sol";
import {AccessHub} from "contracts/AccessHub.sol";
// import {Voter} from "contracts/Voter.sol";

import {FeeRecipient} from "contracts/legacy/FeeRecipient.sol";
import {FeeRecipientFactory} from "contracts/legacy/factories/FeeRecipientFactory.sol";

contract TheTestBase is Test {
	address public constant ZERO_ADDRESS = address(0);
	address public constant TREASURY = address(0x1);
	address public constant ACCESS_MANAGER = address(0x2);
	address public constant TIMELOCK = address(0x3);

	WETH9 public WETH;
	YSK public ysk;
	AccessHub public accessHub;
	FeeRecipientFactory public feeRecipientFactory;
	MockVoter public mockVoter;
	MockERC20 public token0;
	MockERC20 public token1;
	MockERC20 public token6Decimals;
	MockMinter public mockMinter;
	MockVoteModule public mockVoteModule;
	MockLauncherPlugin public mockLauncherPlugin;
	MockFeeCollector public mockFeeCollector;

	address public alice;
	address public bob;
	uint256 public bobPrivateKey;
	address public carol;
	FeeRecipient public feeRecipient;
	MockX33 public mockX33;

	function setUp() public virtual {
		alice = makeAddr("alice");
		carol = makeAddr("carol");
		(bob, bobPrivateKey) = makeAddrAndKey("bob");

		WETH = new WETH9();
		ysk = new YSK(ACCESS_MANAGER);

		AccessHub implementation = new AccessHub();
		accessHub = AccessHub(address(new ERC1967Proxy(address(implementation), "")));

		mockVoteModule = new MockVoteModule();
		mockVoter = _createMockVoter();
		feeRecipientFactory = new FeeRecipientFactory(
			TREASURY,
			address(mockVoter),
			address(accessHub)
		);

		vm.prank(address(mockVoter));
		feeRecipient = FeeRecipient(feeRecipientFactory.createFeeRecipient(address(token0)));
		mockMinter = new MockMinter();
		token0 = new MockERC20("Token0", "TK0", 18);
		token1 = new MockERC20("Token1", "TK1", 18);
		token6Decimals = new MockERC20("Token6Decimals", "TK6D", 6);
		mockX33 = new MockX33();

		vm.label(alice, "alice");
		vm.label(bob, "bob");
		vm.label(carol, "carol");
		vm.label(TREASURY, "treasury");
		vm.label(ACCESS_MANAGER, "access_manager");
		vm.label(TIMELOCK, "timelock");
		vm.label(address(WETH), "weth");
		vm.label(address(ysk), "emissions_token");
		vm.label(address(feeRecipient), "fee_recipient");
		vm.label(address(accessHub), "access_hub");
		vm.label(address(mockVoter), "mock_voter");
		vm.label(address(feeRecipientFactory), "fee_recipient_factory");
		vm.label(address(token0), "token0");
		vm.label(address(token1), "token1");
		vm.label(address(token6Decimals), "token6Decimals");
		vm.label(address(mockMinter), "mock_minter");
		vm.label(address(mockVoteModule), "mock_vote_module");
	}

	function _dealAndApprove(address token, address to, uint256 amount, address spender) internal {
		deal(token, to, amount);
		vm.prank(to);
		MockERC20(token).approve(spender, type(uint256).max);
	}

	function _createMockVoter() internal returns (MockVoter) {
		return
			new MockVoter(
				makeAddr("launcherPlugin"),
				address(mockVoteModule),
				address(ysk),
				address(mockMinter)
			);
	}
}
