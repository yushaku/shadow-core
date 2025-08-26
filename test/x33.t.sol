// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {Voter} from "contracts/Voter.sol";
import {VoteModule} from "contracts/VoteModule.sol";
import {XYSK} from "contracts/x/XYSK.sol";
import {X33} from "contracts/x/x33.sol";
import {AccessHub} from "contracts/AccessHub.sol";
import {PairFactory} from "contracts/legacy/factories/PairFactory.sol";
import {GaugeFactory} from "contracts/legacy/factories/GaugeFactory.sol";
import {FeeDistributorFactory} from "contracts/legacy/factories/FeeDistributorFactory.sol";
import {FeeRecipientFactory} from "contracts/legacy/factories/FeeRecipientFactory.sol";
// import {YSK} from "contracts/YSK.sol";
import {IAccessHub} from "contracts/interfaces/IAccessHub.sol";
import {IX33} from "contracts/interfaces/IX33.sol";
// import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";

import "test/mocks/MockERC20.sol";
import "test/mocks/MockX33.sol";
import "test/Base.t.sol";

contract x33Test is TheTestBase {
	Voter public voter;
	address public constant CL_FACTORY = address(0xabc);
	address public constant CL_GAUGE_FACTORY = address(0xdef);
	address public constant NFP_MANAGER = address(0xbcd);
	address public constant PROTOCOL_OPERATOR = address(0x123);
	address public constant FEE_COLLECTOR = address(0x123);

	XYSK public xYSK;
	VoteModule public voteModule;
	PairFactory public pairFactory;
	GaugeFactory public gaugeFactory;
	FeeDistributorFactory public feeDistributorFactory;
	X33 public vault;

	function setUp() public override {
		// Call parent setUp and deploy core contracts
		super.setUp();

		bytes memory initAccessHub = abi.encodeWithSelector(
			IAccessHub.initialize.selector,
			PROTOCOL_OPERATOR
		);
		AccessHub accessHubImplement = new AccessHub();
		ERC1967Proxy accessHubProxy = new ERC1967Proxy(address(accessHubImplement), initAccessHub);
		accessHub = AccessHub(address(accessHubProxy));

		bytes memory initVoter = abi.encodeWithSelector(
			IVoter.initialize.selector,
			PROTOCOL_OPERATOR,
			address(accessHub)
		);
		Voter voterImplement = new Voter();
		ERC1967Proxy voterProxy = new ERC1967Proxy(address(voterImplement), initVoter);
		voter = Voter(address(voterProxy));

		bytes memory initVoteModule = abi.encodeWithSelector(
			VoteModule.initialize.selector,
			PROTOCOL_OPERATOR,
			address(voter),
			address(accessHub)
		);
		VoteModule voteModuleImplement = new VoteModule();
		ERC1967Proxy voteModuleProxy = new ERC1967Proxy(
			address(voteModuleImplement),
			initVoteModule
		);
		voteModule = VoteModule(address(voteModuleProxy));

		// Deploy xYSK with dependencies
		xYSK = new XYSK(
			address(ysk),
			address(voter),
			address(TREASURY),
			address(accessHub),
			address(voteModule),
			address(mockMinter)
		);

		// Deploy factory contracts
		feeRecipientFactory = new FeeRecipientFactory(TREASURY, address(voter), address(accessHub));
		pairFactory = new PairFactory(
			address(voter),
			address(TREASURY),
			address(accessHub),
			address(feeRecipientFactory)
		);
		gaugeFactory = new GaugeFactory();
		feeDistributorFactory = new FeeDistributorFactory();

		// Deploy and initialize x33 vault
		vault = new X33(
			address(TREASURY),
			address(accessHub),
			address(xYSK),
			address(voter),
			address(voteModule)
		);

		// Initialize core with all dependencies
		vm.startPrank(address(PROTOCOL_OPERATOR));
		IAccessHub.InitParams memory params = IAccessHub.InitParams({
			timelock: TIMELOCK,
			treasury: TREASURY,
			voter: address(voter),
			minter: address(mockMinter),
			launcherPlugin: address(mockLauncherPlugin),
			xYSK: address(xYSK),
			x33: address(vault),
			ramsesV3PoolFactory: address(CL_FACTORY),
			poolFactory: address(pairFactory),
			clGaugeFactory: CL_GAUGE_FACTORY,
			gaugeFactory: address(gaugeFactory),
			feeRecipientFactory: address(feeRecipientFactory),
			feeDistributorFactory: address(feeDistributorFactory),
			feeCollector: address(mockFeeCollector),
			voteModule: address(voteModule)
		});
		accessHub.setup(params);
		accessHub.grantRole(accessHub.PROTOCOL_OPERATOR(), PROTOCOL_OPERATOR);
		voteModule.setUp(address(xYSK));
		voter.setUp(
			address(ysk),
			address(pairFactory),
			address(gaugeFactory),
			address(feeDistributorFactory),
			address(mockMinter),
			PROTOCOL_OPERATOR,
			address(xYSK),
			address(0),
			address(0),
			address(0),
			address(0),
			address(voteModule),
			address(0)
		);

		// 6. Whitelist tokens
		vm.startPrank(address(PROTOCOL_OPERATOR));
		address[] memory tokens = new address[](5);
		tokens[0] = address(ysk);
		tokens[1] = address(token0);
		tokens[2] = address(token1);
		tokens[3] = address(xYSK);
		tokens[4] = address(token6Decimals);
		bool[] memory whitelisted = new bool[](5);
		whitelisted[0] = true;
		whitelisted[1] = true;
		whitelisted[2] = true;
		whitelisted[3] = true;
		whitelisted[4] = true;
		accessHub.governanceWhitelist(tokens, whitelisted);
		vm.stopPrank();

		// 9. Set exemptions for vault
		vm.startPrank(address(accessHub));
		address[] memory exemptees = new address[](1);
		exemptees[0] = address(vault);
		bool[] memory exemptStatus = new bool[](1);
		exemptStatus[0] = true;
		xYSK.setExemption(exemptees, exemptStatus);
		xYSK.setExemptionTo(exemptees, exemptStatus);
		vm.stopPrank();
	}

	function test_constructor() public view {
		// 1. Verify operator and accessHub addresses
		assertEq(vault.operator(), address(TREASURY), "Incorrect operator address");
		assertEq(vault.accessHub(), address(accessHub), "Incorrect accessHub address");

		// 2. Verify token addresses
		assertEq(address(vault.xYSK()), address(xYSK), "Incorrect xYSK address");
		assertEq(address(vault.voter()), address(voter), "Incorrect voter address");
		assertEq(address(vault.voteModule()), address(voteModule), "Incorrect voteModule address");

		// 3. Verify period initialization
		assertEq(vault.activePeriod(), vault.getPeriod(), "Incorrect activePeriod");
	}

	function test_enterVault() public {
		// 1. Setup test amount and give tokens to alice
		uint256 amount = 100e18;
		deal(address(xYSK), alice, amount);

		// 2. Unlock the current period
		vm.prank(address(TREASURY));
		vault.unlock();

		// 3. Enter vault and verify balances
		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);

		vm.expectEmit();
		emit IERC4626.Deposit(alice, alice, amount, amount);
		vault.deposit(amount, alice);
		vm.stopPrank();

		assertEq(vault.balanceOf(alice), amount, "Incorrect balance after enter");
		assertEq(vault.totalSupply(), amount, "Incorrect total supply after enter");
	}

	function test_exitVaultWithRightAmount() public {
		// 1. Setup test amount and give tokens to alice
		uint256 amount = 100e18;
		deal(address(xYSK), alice, amount);

		// 2. Unlock period and enter vault
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);
		vault.deposit(amount, alice);

		vault.withdraw(amount, alice, alice);
		vm.stopPrank();

		assertEq(vault.balanceOf(alice), 0, "Balance should be 0 after exit");
		assertEq(vault.totalSupply(), 0, "Total supply should be 0 after exit");
	}

	function test_submitVotes() public {
		// 1. Setup test parameters
		address[] memory pools = new address[](1);
		pools[0] = address(0x1);
		uint256[] memory weights = new uint256[](1);
		weights[0] = 100;

		// 2. Mock voter call
		vm.mockCall(
			address(voter),
			abi.encodeWithSelector(voter.vote.selector, address(vault), pools, weights),
			abi.encode(true)
		);

		// 3. Submit votes
		vm.prank(address(TREASURY));
		vault.submitVotes(pools, weights);
	}

	function test_compound() public {
		// 1. Setup initial state and balances
		uint256 shadowAmount = 100e18;
		deal(address(vault.YSK()), address(vault), shadowAmount);
		uint256 depositAmount = 1000e18;
		deal(address(xYSK), alice, depositAmount);

		// 2. Unlock period and have alice deposit
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), depositAmount);
		vault.deposit(depositAmount, alice);
		vm.stopPrank();

		// 3. Mock calls and compound
		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.deposit.selector, depositAmount),
			abi.encode()
		);

		vm.prank(address(TREASURY));
		vm.expectEmit();
		emit IX33.Compounded(1e18, 1.1e18, shadowAmount);

		vault.compound();
	}

	function test_claimRebase() public {
		// 1. Setup initial state and balances
		uint256 depositAmount = 1000e18;
		deal(address(xYSK), alice, depositAmount);

		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), depositAmount);
		vault.deposit(depositAmount, alice);
		vm.stopPrank();

		// 2. Setup mocks
		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.periodFinish.selector),
			abi.encode(block.timestamp - 1)
		);

		uint256 rebaseAmount = 100e18;
		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.earned.selector, address(vault)),
			abi.encode(rebaseAmount)
		);

		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.getReward.selector),
			abi.encode()
		);
		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.deposit.selector, type(uint256).max),
			abi.encode()
		);

		// 3. Claim rebase and verify
		vm.prank(address(TREASURY));
		vm.expectEmit(false, false, false, true);
		emit IX33.Rebased(1e18, 1e18, rebaseAmount);

		vault.claimRebase();
	}

	function test_rescueBribe() public {
		// 1. Setup test token and amount
		address token = address(new MockERC20("test", "TST", 18));
		uint256 amount = 100e18;
		deal(token, address(vault), amount);

		// 2. Rescue bribe
		vm.prank(address(accessHub));
		vault.rescue(token, amount);

		// 3. Verify balance
		assertEq(
			IERC20(token).balanceOf(address(accessHub)),
			amount,
			"Incorrect balance after rescue"
		);
	}

	function test_unlock() public {
		// 1. Setup unlock call
		vm.prank(address(TREASURY));
		vm.expectEmit(false, false, false, true);
		emit IX33.Unlocked(block.timestamp);

		// 2. Unlock period
		vault.unlock();

		// 3. Verify unlock status
		assertTrue(vault.periodUnlockStatus(vault.getPeriod()));
	}

	function test_transferOperator() public {
		// 1. Setup new operator address
		address newOperator = address(0x123);

		// 2. Transfer operator
		vm.prank(address(accessHub));
		vm.expectEmit(true, true, false, true);
		emit IX33.NewOperator(address(TREASURY), newOperator);

		vault.transferOperator(newOperator);

		// 3. Verify operator update
		assertEq(vault.operator(), newOperator, "Operator not updated correctly");
	}

	function test_whitelistAggregator() public {
		// 1. Set up test aggregator address
		address aggregator = address(0x123);

		// 2. Whitelist aggregator and verify event emission
		vm.prank(address(accessHub));
		vm.expectEmit(true, false, false, true);
		emit IX33.AggregatorWhitelistUpdated(aggregator, true);

		vault.whitelistAggregator(aggregator, true);

		// 3. Verify aggregator is whitelisted
		assertTrue(vault.whitelistedAggregators(aggregator), "Aggregator not whitelisted");
	}

	function test_ratio() public {
		// 1. Set up test amount and give tokens to alice
		uint256 amount = 100e18;
		deal(address(xYSK), alice, amount);

		// 2. Unlock vault and approve tokens
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);

		// 3. Enter vault and verify ratio
		vault.deposit(amount, alice);
		vm.stopPrank();

		assertEq(vault.ratio(), 1e18, "Incorrect ratio");
	}

	function test_isUnlocked() public {
		// 1. Test initial locked state
		assertFalse(vault.isUnlocked(), "Period should be locked by default");

		// 2. Test unlocked state not near period end
		vm.prank(address(TREASURY));
		vault.unlock();
		vm.warp(((vault.getPeriod() + 1) * 1 weeks) - 2 hours);
		assertTrue(
			vault.isUnlocked(),
			"Period should be unlocked when not within 1 hour of next period"
		);

		// 3. Test locked state near period end
		vm.warp(((vault.getPeriod() + 1) * 1 weeks) - 30 minutes);
		assertFalse(
			vault.isUnlocked(),
			"Period should be locked when within 1 hour of next period"
		);
	}

	function test_isCooldownActive() public {
		// 1. Test active cooldown
		vm.mockCall(
			address(voteModule),
			abi.encodeWithSelector(voteModule.unlockTime.selector),
			abi.encode(block.timestamp + 1 days)
		);

		assertTrue(vault.isCooldownActive());

		// 2. Test inactive cooldown
		vm.warp(block.timestamp + 2 days);
		assertFalse(vault.isCooldownActive());
	}

	function testFuzz_enterVault(uint256 amount) public {
		// 1. Set up fuzz bounds and give tokens
		vm.assume(amount >= 1e18 && amount <= 1000000e18);
		deal(address(xYSK), alice, amount);

		// 2. Unlock vault and approve tokens
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);

		// 3. Enter vault and verify balance
		vault.deposit(amount, alice);
		assertEq(vault.balanceOf(alice), amount, "Incorrect balance after fuzz enter");
	}

	function testFuzz_exitVault(uint256 amount) public {
		// 1. Set up fuzz bounds and give tokens
		vm.assume(amount >= 1e18 && amount <= 1000000e18);
		deal(address(xYSK), alice, amount);

		// 2. Unlock vault and enter
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);
		vault.deposit(amount, alice);

		// 3. Exit vault and verify balance
		vault.withdraw(amount, alice, alice);
		vm.stopPrank();

		assertEq(vault.balanceOf(alice), 0, "Balance should be 0 after fuzz exit");
	}

	function test_enterVault_RevertWhenPeriodLocked() public {
		// 1. Set up test amount and give tokens
		uint256 amount = 100e18;
		deal(address(xYSK), alice, amount);

		// 2. Approve tokens
		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);

		// 3. Attempt enter without unlocking and verify revert
		vm.expectRevert(abi.encodeWithSignature("LOCKED()"));
		vault.deposit(amount, alice);
	}

	function test_exitVault_RevertWhenInsufficientBalance() public {
		// 1. Set up test amount and give tokens
		uint256 amount = 100e18;
		deal(address(xYSK), alice, amount);

		// 2. Unlock vault and enter
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), amount);
		vault.deposit(amount, alice);

		// 3. Attempt exit with too much and verify revert
		vm.expectRevert(
			abi.encodeWithSelector(
				ERC4626.ERC4626ExceededMaxWithdraw.selector,
				alice,
				amount + 1,
				amount
			)
		);
		vault.withdraw(amount + 1, alice, alice);
	}

	function test_submitVotesRevertWhenNotOperator() public {
		// 1. Set up test parameters
		address[] memory pools = new address[](1);
		pools[0] = address(0x1);
		uint256[] memory weights = new uint256[](1);
		weights[0] = 100;

		// 2. Attempt call as non-operator
		vm.prank(alice);

		// 3. Verify revert
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		vault.submitVotes(pools, weights);
	}

	function test_compoundRevertWhenNotOperator() public {
		// 1. Start prank as non-operator
		vm.prank(alice);

		// 2. Attempt compound
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));

		// 3. Call and verify revert
		vault.compound();
	}

	function test_claimRebaseRevertWhenNotOperator() public {
		// 1. Start prank as non-operator
		vm.prank(alice);

		// 2. Attempt claim rebase
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));

		// 3. Call and verify revert
		vault.claimRebase();
	}

	function test_claimIncentivesRevertWhenNotOperator() public {
		// 1. Set up test parameters
		address[] memory distributors = new address[](1);
		address[][] memory tokens = new address[][](1);

		// 2. Attempt claim as non-operator
		vm.prank(alice);

		// 3. Verify revert
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		vault.claimIncentives(distributors, tokens);
	}

	function test_swapIncentiveViaAggregatorRevertWhenNotOperator() public {
		// 1. Set up empty params
		IX33.AggregatorParams memory params;

		// 2. Attempt swap as non-operator
		vm.prank(alice);

		// 3. Verify revert
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));
		vault.swapIncentiveViaAggregator(params);
	}

	function test_swapIncentiveViaAggregatorRevertWhenAggregatorNotWhitelisted() public {
		// 1. Set up test parameters
		address aggregator = address(0x123);
		IX33.AggregatorParams memory params = IX33.AggregatorParams({
			aggregator: aggregator,
			tokenIn: address(token0),
			amountIn: 100e18,
			minAmountOut: 90e18,
			callData: ""
		});

		// 2. Attempt swap with non-whitelisted aggregator
		vm.prank(address(TREASURY));

		// 3. Verify revert
		vm.expectRevert(abi.encodeWithSignature("AGGREGATOR_NOT_WHITELISTED(address)", aggregator));
		vault.swapIncentiveViaAggregator(params);
	}

	function test_rescueBribeRevertWhenNotAccessHub() public {
		// 1. Start prank as non-access hub
		vm.prank(alice);

		// 2. Attempt rescue
		vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB(address)", alice));

		// 3. Call and verify revert
		vault.rescue(address(0), 0);
	}

	function test_unlockRevertWhenNotOperator() public {
		// 1. Start prank as non-operator
		vm.prank(alice);

		// 2. Attempt unlock
		vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", alice));

		// 3. Call and verify revert
		vault.unlock();
	}

	function test_transferOperatorRevertWhenNotAccessHub() public {
		// 1. Start prank as non-access hub
		vm.prank(alice);

		// 2. Attempt transfer
		vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB(address)", alice));

		// 3. Call and verify revert
		vault.transferOperator(address(0));
	}

	function test_whitelistAggregatorRevertWhenNotAccessHub() public {
		// 1. Start prank as non-access hub
		vm.prank(alice);

		// 2. Attempt whitelist
		vm.expectRevert(abi.encodeWithSignature("NOT_ACCESSHUB(address)", alice));

		// 3. Call and verify revert
		vault.whitelistAggregator(address(0), true);
	}

	function test_multipleUsersEnterExit() public {
		// 1. Set up test amounts and give tokens
		uint256 aliceAmount = 100e18;
		uint256 bobAmount = 200e18;

		deal(address(xYSK), alice, aliceAmount);
		deal(address(xYSK), bob, bobAmount);

		// 2. Unlock vault and have users enter
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		xYSK.approve(address(vault), aliceAmount);
		vault.deposit(aliceAmount, alice);
		vm.stopPrank();

		vm.startPrank(bob);
		xYSK.approve(address(vault), bobAmount);
		vault.deposit(bobAmount, bob);
		vm.stopPrank();

		// 3. Verify balances and test partial exit
		assertEq(vault.balanceOf(alice), aliceAmount, "Incorrect Alice balance after enter");
		assertEq(vault.balanceOf(bob), bobAmount, "Incorrect Bob balance after enter");
		assertEq(
			vault.totalSupply(),
			aliceAmount + bobAmount,
			"Incorrect total supply after both enter"
		);

		uint256 aliceExitAmount = aliceAmount / 2;
		vm.prank(alice);
		vault.withdraw(aliceExitAmount, alice, alice);

		assertEq(
			vault.balanceOf(alice),
			aliceAmount - aliceExitAmount,
			"Incorrect Alice balance after partial exit"
		);
		assertEq(vault.balanceOf(bob), bobAmount, "Bob's balance should be unchanged");
		assertEq(
			vault.totalSupply(),
			(aliceAmount - aliceExitAmount) + bobAmount,
			"Incorrect total supply after partial exit"
		);
	}

	function test_periodTransitions() public {
		// 1. Get current period and unlock it
		uint256 currentPeriod = vault.getPeriod();

		vm.prank(address(TREASURY));
		vault.unlock();
		assertTrue(vault.periodUnlockStatus(currentPeriod), "Period should be unlocked");

		// 2. Move to next period and verify locked state
		vm.warp(block.timestamp + 1 weeks);
		assertEq(vault.getPeriod(), currentPeriod + 1, "Incorrect period after time warp");
		assertFalse(vault.periodUnlockStatus(currentPeriod + 1), "New period should start locked");

		// 3. Unlock new period and verify
		vm.prank(address(TREASURY));
		vault.unlock();
		assertTrue(
			vault.periodUnlockStatus(currentPeriod + 1),
			"New period should be unlocked after unlock call"
		);
	}

	function test_swapIncentiveViaAggregator_Success() public {
		// 1. Deploy mock aggregator and set up test parameters
		MockAggregator aggregator = new MockAggregator();
		address tokenIn = address(token0);
		uint256 amountIn = 100e18;
		uint256 minAmountOut = 90e18;
		bytes memory callData = abi.encodeWithSelector(
			MockAggregator.swap.selector,
			tokenIn,
			address(vault.YSK()),
			amountIn,
			minAmountOut,
			address(vault)
		);

		// 2. Setup initial token balances
		deal(tokenIn, address(vault), amountIn);
		deal(address(vault.YSK()), address(aggregator), minAmountOut);

		// 3. Whitelist the aggregator
		vm.prank(address(accessHub));
		vault.whitelistAggregator(address(aggregator), true);

		// 4. Create aggregator params struct
		IX33.AggregatorParams memory params = IX33.AggregatorParams({
			aggregator: address(aggregator),
			tokenIn: tokenIn,
			amountIn: amountIn,
			minAmountOut: minAmountOut,
			callData: callData
		});

		// 5. Execute swap and verify event emission
		vm.prank(address(TREASURY));
		vm.expectEmit();
		emit IX33.SwappedBribe(address(TREASURY), tokenIn, amountIn, minAmountOut);
		vault.swapIncentiveViaAggregator(params);
	}

	function test_swapIncentiveViaAggregatorRevertWhenSlippageTooHigh() public {
		// 1. Set up test parameters
		address tokenIn = address(token0);
		uint256 amountIn = 100e18;
		uint256 minAmountOut = 90e18;
		MockAggregator mockAggregator = new MockAggregator();

		// 2. Setup initial token balances
		deal(tokenIn, address(vault), amountIn);
		deal(address(vault.YSK()), address(mockAggregator), minAmountOut);

		// 3. Create calldata with insufficient output amount
		bytes memory callData = abi.encodeWithSelector(
			MockAggregator.swap.selector,
			tokenIn,
			address(vault.YSK()),
			amountIn,
			minAmountOut - 1e18,
			address(vault)
		);

		// 4. Whitelist the aggregator
		vm.prank(address(accessHub));
		vault.whitelistAggregator(address(mockAggregator), true);

		// 5. Create aggregator params struct
		IX33.AggregatorParams memory params = IX33.AggregatorParams({
			aggregator: address(mockAggregator),
			tokenIn: tokenIn,
			amountIn: amountIn,
			minAmountOut: minAmountOut,
			callData: callData
		});

		// 6. Execute swap and verify revert
		vm.prank(address(TREASURY));
		console.log("minAmountOut", minAmountOut);
		vm.expectRevert(
			abi.encodeWithSignature("AMOUNT_OUT_TOO_LOW(uint256)", minAmountOut - 1e18)
		);
		vault.swapIncentiveViaAggregator(params);
	}

	function test_swapIncentiveViaAggregatorRevertWhenAggregatorCallFails() public {
		// 1. Set up test parameters
		MockAggregator aggregator = new MockAggregator();
		address tokenIn = address(token0);
		uint256 amountIn = 100e18;
		uint256 minAmountOut = 90e18;
		bytes memory callData = abi.encodeWithSelector(
			MockAggregator.swap.selector,
			tokenIn,
			address(vault.YSK()),
			amountIn,
			minAmountOut,
			address(vault)
		);

		// 2. Setup initial token balance
		deal(tokenIn, address(vault), amountIn);

		// 3. Whitelist the aggregator
		vm.prank(address(accessHub));
		vault.whitelistAggregator(address(aggregator), true);

		// 4. Create aggregator params struct
		IX33.AggregatorParams memory params = IX33.AggregatorParams({
			aggregator: address(aggregator),
			tokenIn: tokenIn,
			amountIn: amountIn,
			minAmountOut: minAmountOut,
			callData: callData
		});

		// 5. Mock aggregator to revert on swap
		vm.mockCallRevert(address(aggregator), callData, callData);

		// 6. Execute swap and verify revert
		vm.prank(address(TREASURY));
		vm.expectRevert(abi.encodeWithSignature("AGGREGATOR_REVERTED(bytes)", callData));
		vault.swapIncentiveViaAggregator(params);
	}

	function test_swapIncentiveViaAggregatorRevertWhenXShadowBalanceChanged() public {
		// 1. Set up test parameters
		MockAggregator aggregator = new MockAggregator();
		address tokenIn = address(token0);
		uint256 amountIn = 100e18;
		uint256 minAmountOut = 90e18;
		bytes memory callData = abi.encodeWithSelector(
			MockAggregator.swapAndShadow.selector,
			tokenIn,
			address(vault.xYSK()),
			address(vault.YSK()),
			amountIn,
			minAmountOut,
			100e18,
			address(vault)
		);

		// 2. Whitelist aggregator in xYSK
		vm.prank(address(accessHub));
		address[] memory exemptees = new address[](1);
		bool[] memory statuses = new bool[](1);
		exemptees[0] = address(aggregator);
		statuses[0] = true;
		xYSK.setExemption(exemptees, statuses);

		// 3. Setup initial token balances
		deal(tokenIn, address(vault), amountIn);
		deal(address(xYSK), address(aggregator), 100e18);
		deal(address(vault.YSK()), address(aggregator), 100e18);

		// 4. Whitelist the aggregator
		vm.prank(address(accessHub));
		vault.whitelistAggregator(address(aggregator), true);

		// 5. Create aggregator params struct
		IX33.AggregatorParams memory params = IX33.AggregatorParams({
			aggregator: address(aggregator),
			tokenIn: tokenIn,
			amountIn: amountIn,
			minAmountOut: minAmountOut,
			callData: callData
		});

		// 6. Mock voteModule balance changes
		bytes memory mockCallData = abi.encodeWithSelector(
			IERC20.balanceOf.selector,
			address(vault)
		);
		bytes[] memory returnData = new bytes[](2);
		returnData[0] = abi.encode(100e18);
		returnData[1] = abi.encode(200e18);
		vm.mockCalls(address(voteModule), mockCallData, returnData);

		// 7. Execute swap and verify revert
		vm.startPrank(address(TREASURY));
		vm.expectRevert(abi.encodeWithSignature("FORBIDDEN_TOKEN(address)", address(vault.YSK())));
		vault.swapIncentiveViaAggregator(params);
	}

	function test_exitVaultRevertWhenZero() public {
		vm.startPrank(alice);
		// 1. Expect revert when trying to exit with 0 amount
		vm.expectRevert(abi.encodeWithSignature("ZERO_AMOUNT()"));
		vault.withdraw(0, alice, alice);
	}

	function test_enterExitMultipleUsersDifferentTimes() public {
		// 1. Set test amounts for different users
		uint256 aliceAmount = 100e18;
		uint256 bobAmount = 200e18;
		uint256 carolAmount = 150e18;

		// 2. Give tokens to users
		deal(address(xYSK), alice, aliceAmount);
		deal(address(xYSK), bob, bobAmount);
		deal(address(xYSK), carol, carolAmount);

		// 3. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		// 4. Alice enters first
		vm.startPrank(alice);
		xYSK.approve(address(vault), aliceAmount);
		vault.deposit(aliceAmount, alice);
		vm.stopPrank();

		// 5. Advance time 1 day
		vm.warp(block.timestamp + 1 days);

		// 6. Bob enters second
		vm.startPrank(bob);
		xYSK.approve(address(vault), bobAmount);
		vault.deposit(bobAmount, bob);
		vm.stopPrank();

		// 7. Advance time another day
		vm.warp(block.timestamp + 1 days);

		// 8. Carol enters last
		vm.startPrank(carol);
		xYSK.approve(address(vault), carolAmount);
		vault.deposit(carolAmount, carol);
		vm.stopPrank();

		// 9. Verify all balances are correct
		assertEq(vault.balanceOf(alice), aliceAmount);
		assertEq(vault.balanceOf(bob), bobAmount);
		assertEq(vault.balanceOf(carol), carolAmount);
		assertEq(vault.totalSupply(), aliceAmount + bobAmount + carolAmount);

		// 10. Users exit in different order
		// Bob exits fully
		vm.prank(bob);
		vault.withdraw(bobAmount, bob, bob);

		// 11. Alice exits partially
		vm.prank(alice);
		vault.withdraw(aliceAmount / 2, alice, alice);

		// 12. Carol exits fully
		vm.prank(carol);
		vault.withdraw(carolAmount, carol, carol);

		// 13. Verify final balances
		assertEq(vault.balanceOf(alice), aliceAmount / 2);
		assertEq(vault.balanceOf(bob), 0);
		assertEq(vault.balanceOf(carol), 0);
		assertEq(vault.totalSupply(), aliceAmount / 2);
	}

	function testFuzz_enterExitMultipleAmounts(uint256 amount1, uint256 amount2) public {
		// 1. Bound input amounts to reasonable ranges
		vm.assume(amount1 >= 1e18 && amount1 <= type(uint128).max);
		vm.assume(amount2 >= 1e18 && amount2 <= type(uint128).max);

		// 2. Give alice enough tokens for both amounts
		deal(address(xYSK), alice, amount1 + amount2);

		// 3. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		// 4. Approve total amount
		xYSK.approve(address(vault), amount1 + amount2);

		// 5. Enter with first amount and verify balance
		vault.deposit(amount1, alice);
		assertEq(vault.balanceOf(alice), amount1);

		// 6. Enter with second amount and verify total balance
		vault.deposit(amount2, alice);
		assertEq(vault.balanceOf(alice), amount1 + amount2);

		// 7. Exit full amount and verify zero balance
		vault.withdraw(amount1 + amount2, alice, alice);
		assertEq(vault.balanceOf(alice), 0);
	}

	function testFuzz_enterExitPartialAmounts(uint256 depositAmount, uint256 exitAmount) public {
		// 1. Bound input amounts to reasonable ranges
		vm.assume(depositAmount >= 1e18 && depositAmount <= type(uint128).max);
		vm.assume(exitAmount >= 1e18 && exitAmount <= depositAmount);

		// 2. Give alice deposit amount
		deal(address(xYSK), alice, depositAmount);

		// 3. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		vm.startPrank(alice);
		// 4. Approve and deposit
		xYSK.approve(address(vault), depositAmount);
		vault.deposit(depositAmount, alice);

		// 5. Exit partial amount
		vault.withdraw(exitAmount, alice, alice);

		// 6. Verify remaining balance
		assertEq(vault.balanceOf(alice), depositAmount - exitAmount);
	}

	function test_enterExitRatioMaintained() public {
		// 1. Set initial deposit amount
		uint256 initialDeposit = 10e18;

		// 2. Give tokens to alice
		deal(address(xYSK), address(this), initialDeposit);

		// 3. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		// 4. Alice deposits initial amount
		xYSK.approve(address(vault), initialDeposit);
		vault.deposit(initialDeposit, alice);

		// 5. Verify deposit and ratio
		assertEq(vault.balanceOf(alice), initialDeposit);
		assertEq(vault.ratio(), 1e18);
		// 1. Set test amounts
		uint256 aliceAmount = 100e18;
		uint256 bobAmount = 200e18;

		// 2. Give tokens to users
		deal(address(xYSK), alice, aliceAmount);
		deal(address(xYSK), bob, bobAmount);

		// 3. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		// 4. Check initial ratio
		assertEq(vault.ratio(), 1e18);

		// 5. Alice enters and verify ratio
		vm.startPrank(alice);
		xYSK.approve(address(vault), aliceAmount);
		vault.deposit(aliceAmount, alice);
		vm.stopPrank();
		assertEq(vault.ratio(), 1e18);

		// 6. Bob enters and verify ratio
		vm.startPrank(bob);
		xYSK.approve(address(vault), bobAmount);
		vault.deposit(bobAmount, bob);
		vm.stopPrank();
		assertEq(vault.ratio(), 1e18);

		// 7. Alice exits partially and verify ratio maintained
		vm.prank(alice);
		vault.withdraw(aliceAmount / 2, alice, alice);
		assertEq(vault.ratio(), 1e18);
	}

	function testFuzz_enterExitRatioInvariant(uint256[] calldata amounts) public {
		// 1. Bound array length
		vm.assume(amounts.length > 0 && amounts.length <= 10);

		// 2. Unlock the vault
		vm.prank(address(TREASURY));
		vault.unlock();

		uint256 totalDeposited = 0;

		// 3. Process each amount
		for (uint256 i = 0; i < amounts.length; i++) {
			// 4. Bound each amount to reasonable range
			uint256 amount = bound(amounts[i], 1e18, 1000000e18);

			// 5. Give alice tokens and enter vault
			deal(address(xYSK), alice, amount);
			vm.startPrank(alice);
			xYSK.approve(address(vault), amount);
			vault.deposit(amount, alice);
			vm.stopPrank();

			totalDeposited += amount;

			// 6. Verify ratio and supply after each deposit
			assertEq(vault.ratio(), 1e18);
			assertEq(vault.totalSupply(), totalDeposited);
		}
	}
}

contract MockAggregator {
	uint256 public rate;

	constructor() {}

	function swap(
		address tokenIn,
		address tokenOut,
		uint256 amountIn,
		uint256 amountOut,
		address recipient
	) external returns (uint256) {
		// Pull in tokenIn amount
		IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

		// Deal out tokenOut amount
		IERC20(tokenOut).transfer(recipient, amountOut);

		return amountOut;
	}

	function swapAndShadow(
		address tokenIn,
		address tokenOut,
		address ysk,
		uint256 amountIn,
		uint256 amountOut,
		uint256 amountShadow,
		address recipient
	) external returns (uint256) {
		// Pull in tokenIn amount
		IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

		// Transfer out tokenOut amount
		IERC20(tokenOut).transfer(recipient, amountOut);
		// Transfer out ysk amount
		IERC20(ysk).transfer(recipient, amountShadow);
		return amountOut;
	}
}
