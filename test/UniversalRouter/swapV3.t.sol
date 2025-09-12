// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./Fixture.t.sol";

import "contracts/CL/periphery/interfaces/INonfungiblePositionManager.sol";
import "contracts/universalRouter/libraries/Commands.sol";
import "solmate/src/tokens/ERC20.sol";

import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";

contract SwapV3Test is Fixture {
	uint160 public constant INITIAL_SQRT_PRICE = 1 * 2 ** 96; // 1:1 price
	int24 public constant TICK_SPACING = 5;
	int24 public constant TICK_LOWER = -120;
	int24 public constant TICK_UPPER = 120;

	function setUp() public override {
		super.setUp();

		(address tokenA, address tokenB) = clPoolFactory.sortTokens(
			address(token0),
			address(token1)
		);

		nfpManager.createAndInitializePoolIfNecessary(
			tokenA,
			tokenB,
			TICK_SPACING,
			INITIAL_SQRT_PRICE
		);

		token0.mint(alice, 2000e18);
		token1.mint(alice, 2000e18);

		vm.startPrank(alice);
		token0.approve(address(nfpManager), 1000e18);
		token1.approve(address(nfpManager), 1000e18);

		INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
			.MintParams({
				token0: tokenA,
				token1: tokenB,
				tickSpacing: TICK_SPACING,
				tickLower: TICK_LOWER,
				tickUpper: TICK_UPPER,
				amount0Desired: 1000e18,
				amount1Desired: 1000e18,
				amount0Min: 0,
				amount1Min: 0,
				recipient: alice,
				deadline: block.timestamp
			});

		nfpManager.mint(params);
		vm.stopPrank();
	}

	// ============ Helper function ============
	function getPermit2Signature(
		address tokenIn,
		uint160 amountIn,
		uint256 signerPrivateKey
	) public returns (bytes memory signature, IAllowanceTransfer.PermitSingle memory permitSingle) {
		permitSingle = IAllowanceTransfer.PermitSingle({
			details: IAllowanceTransfer.PermitDetails({
				token: tokenIn,
				amount: amountIn,
				expiration: uint48(block.timestamp + 60),
				nonce: 0
			}),
			spender: address(universalRouter),
			sigDeadline: block.timestamp + 60
		});

		bytes32 PERMIT_SINGLE_TYPEHASH = keccak256(
			"PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
		);

		bytes32 PERMIT_DETAILS_TYPEHASH = keccak256(
			"PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
		);

		bytes32 detailsHash = keccak256(
			abi.encode(
				PERMIT_DETAILS_TYPEHASH,
				permitSingle.details.token,
				permitSingle.details.amount,
				permitSingle.details.expiration,
				permitSingle.details.nonce
			)
		);

		bytes32 structHash = keccak256(
			abi.encode(
				PERMIT_SINGLE_TYPEHASH,
				detailsHash,
				permitSingle.spender,
				permitSingle.sigDeadline
			)
		);

		bytes32 domainSeparator = permit2.DOMAIN_SEPARATOR();
		bytes32 typedDataHash = keccak256(
			abi.encodePacked("\x19\x01", domainSeparator, structHash)
		);

		(uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, typedDataHash);
		signature = abi.encodePacked(r, s, v);
	}

	// Trade on Uniswap with Permit2, giving approval every time
	// V3 exactIn, permiting the exact amount
	// V3 exactOut, permiting the exact amount
	//
	//
	// ERC20 --> ERC20

	/*
	 * @notice: timebase permistion swap by permit2
	 * step 1: one-time approval for permit2 with max allowance
	 * step 2: permit2 approves the exact amount with deadline
	 * step 3: swap with exact amount
	 */
	function testSwapV3ExactIn() public {
		uint256 amountIn = 100e18;
		address tokenIn = address(token1);
		address tokenOut = address(token0);

		vm.startPrank(alice);
		ERC20(tokenIn).approve(address(permit2), amountIn);
		permit2.approve(
			tokenIn,
			address(universalRouter),
			uint160(amountIn),
			uint48(block.timestamp + 60)
		);

		bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
		bytes[] memory inputs = new bytes[](1);

		bytes memory path = abi.encodePacked(tokenIn, TICK_SPACING, tokenOut);

		inputs[0] = abi.encode(
			alice, // recipient
			amountIn,
			0, // amountOutMinimum
			path,
			true // payer is user
		);

		uint256 balanceOutBefore = ERC20(tokenOut).balanceOf(alice);
		uint256 balanceInBefore = ERC20(tokenIn).balanceOf(alice);

		universalRouter.execute(commands, inputs, block.timestamp);

		uint256 balanceOutAfter = ERC20(tokenOut).balanceOf(alice);
		uint256 balanceInAfter = ERC20(tokenIn).balanceOf(alice);

		assertTrue(balanceOutAfter > balanceOutBefore, "no token out received");
		assertEq(balanceInBefore - balanceInAfter, amountIn, "wrong amount spent");
		vm.stopPrank();
	}

	function testSwapV3ExactInWithOffChainSignature() public {
		uint256 signerPrivateKey = 0x123456789;
		address signer = vm.addr(signerPrivateKey);

		uint256 amountIn = 100e18;

		address tokenIn = address(token1);
		address tokenOut = address(token0);

		token1.mint(signer, amountIn);

		vm.startPrank(signer);
		ERC20(tokenIn).approve(address(permit2), type(uint256).max);
		(
			bytes memory signature,
			IAllowanceTransfer.PermitSingle memory permitSingle
		) = getPermit2Signature(tokenIn, uint160(amountIn), signerPrivateKey);

		bytes memory commands = abi.encodePacked(
			uint8(Commands.PERMIT2_PERMIT),
			uint8(Commands.V3_SWAP_EXACT_IN)
		);
		bytes[] memory inputs = new bytes[](2);

		inputs[0] = abi.encode(permitSingle, signature);

		bytes memory path = abi.encodePacked(tokenIn, TICK_SPACING, tokenOut);
		inputs[1] = abi.encode(signer, amountIn, 0, path, true);

		uint256 balanceOutBefore = ERC20(tokenOut).balanceOf(signer);
		uint256 balanceInBefore = ERC20(tokenIn).balanceOf(signer);

		universalRouter.execute(commands, inputs, block.timestamp);

		uint256 balanceOutAfter = ERC20(tokenOut).balanceOf(signer);
		uint256 balanceInAfter = ERC20(tokenIn).balanceOf(signer);

		assertTrue(balanceOutAfter > balanceOutBefore, "no token out received");
		assertEq(balanceInBefore - balanceInAfter, amountIn, "wrong amount spent");
		vm.stopPrank();
	}
}
