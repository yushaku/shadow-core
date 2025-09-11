// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "contracts/universalRouter/libraries/Commands.sol";
import "contracts/universalRouter/interfaces/IUniversalRouter.sol";
import "contracts/universalRouter/UniversalRouter.sol";

import "lib/permit2/src/interfaces/IAllowanceTransfer.sol";

interface IQuoterV2 {
	struct QuoteExactInputSingleParams {
		address tokenIn;
		address tokenOut;
		uint256 amountIn;
		uint24 fee;
		uint160 sqrtPriceLimitX96;
	}

	function quoteExactInputSingle(
		QuoteExactInputSingleParams calldata params
	)
		external
		returns (
			uint256 amountOut,
			uint160 sqrtPriceAfterX96,
			uint32 initializedTicksCrossed,
			uint256 gasEstimate
		);
}

/**
 * @title UniversalRouterSwapTest
 * @notice Integration tests for the UniversalRouterSwap contract using mainnet fork.
 * @dev To run: forge test --fork-url bsc --match-path test/Integration/UniversalRouter.it.sol -vvvv
 */
contract UniversalRouterSwapTest is Test {
	using SafeERC20 for IERC20;

	// --- Mainnet Addresses ---
	address internal constant UNIVERSAL_ROUTER = 0x1906c1d672b88cD1B9aC7593301cA990F94Eae07;
	address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
	address internal constant DAI = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3;
	address internal constant UNISWAP_QUOTER = 0x78D78E420Da98ad378D7799bE8f4AF69033EB077;
	address internal constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
	uint24 internal constant POOL_FEE = 3000; // 0.3%

	UniversalRouter internal router;
	IAllowanceTransfer internal permit2;
	IQuoterV2 internal quoter = IQuoterV2(UNISWAP_QUOTER);

	address internal constant USER = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;
	uint256 internal constant WBNB_AMOUNT_IN = 1 ether;

	function setUp() public {
		router = UniversalRouter(payable(UNIVERSAL_ROUTER));
		permit2 = IAllowanceTransfer(PERMIT2_ADDRESS);
		deal(WBNB, USER, WBNB_AMOUNT_IN);

		vm.label(UNIVERSAL_ROUTER, "UniversalRouter");
		vm.label(WBNB, "WBNB");
		vm.label(DAI, "DAI");
		vm.label(USER, "User");
	}

	/**
	 * @notice Tests a successful swap of 1 BNB for DAI.
	 */
	function testSwap() public {
		(uint256 expectedAmountOut, , , ) = quoter.quoteExactInputSingle(
			IQuoterV2.QuoteExactInputSingleParams({
				tokenIn: address(WBNB),
				tokenOut: address(DAI),
				amountIn: WBNB_AMOUNT_IN,
				fee: POOL_FEE,
				sqrtPriceLimitX96: 0
			})
		);

		// slippage is 1% for amountOutMinimum
		uint256 amountOutMinimum = (expectedAmountOut * 99) / 100;

		console.log("Amount In (WBNB):", WBNB_AMOUNT_IN);
		console.log("Expected Amount Out (DAI):", expectedAmountOut);
		console.log("Minimum Amount Out (DAI):", amountOutMinimum);

		/**
		 * @dev 2 Steps: Prepare the commands and inputs for the Universal Router
		 * @dev Command 1: V3_SWAP_EXACT_IN (0x00) -> Swaps the tokens
		 * @dev Command 2: SWEEP (0x01) -> Sends the received tokens (DAI) to the user
		 */
		bytes memory commands = abi.encodePacked(
			uint8(Commands.V3_SWAP_EXACT_IN),
			uint8(Commands.SWEEP)
		);
		bytes[] memory inputs = new bytes[](2);

		// This command sends the specified token from the router's balance to the user.
		bytes memory path = abi.encodePacked(address(WBNB), POOL_FEE, address(DAI));
		bool payerIsUser = true;
		inputs[0] = abi.encode(
			address(UNIVERSAL_ROUTER),
			WBNB_AMOUNT_IN,
			amountOutMinimum,
			path,
			payerIsUser
		);

		// This command sends the specified token from the router's balance to the user.
		inputs[1] = abi.encode(address(DAI), USER, 0); // 0 means sweep the full balance

		vm.startPrank(USER);
		IERC20(WBNB).approve(UNIVERSAL_ROUTER, type(uint256).max);
		IERC20(WBNB).approve(PERMIT2_ADDRESS, type(uint256).max);
		IERC20(DAI).approve(PERMIT2_ADDRESS, type(uint256).max);
		uint48 deadline = uint48(block.timestamp + 1 days);
		permit2.approve(WBNB, UNIVERSAL_ROUTER, uint160(WBNB_AMOUNT_IN), deadline);
		router.execute(commands, inputs, block.timestamp + 1 days);
		vm.stopPrank();

		// is USER received enough DAI?
		uint256 userDaiBalance = IERC20(DAI).balanceOf(USER);
		assertTrue(userDaiBalance >= amountOutMinimum, "User did not receive enough DAI");
		console.log("Actual DAI received by user:", userDaiBalance);

		// check contract has no WBNB or DAI
		assertEq(IERC20(WBNB).balanceOf(address(router)), 0, "Contract should not hold WBNB");
		assertEq(IERC20(DAI).balanceOf(address(router)), 0, "Contract should not hold DAI");
	}
}
