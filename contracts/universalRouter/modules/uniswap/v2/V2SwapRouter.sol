// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IPair} from "contracts/interfaces/IPair.sol";
import {IPairFactory} from "contracts/interfaces/IPairFactory.sol";
import {Permit2Payments} from "contracts/universalRouter/modules/Permit2Payments.sol";
import {Constants} from "contracts/universalRouter/libraries/Constants.sol";
import {SwapRoute} from "contracts/universalRouter/libraries/SwapRoute.sol";

import {V2Library} from "./V2Library.sol";
import {UniswapImmutables} from "../UniswapImmutables.sol";

import "forge-std/console.sol";

/// @title Router for v2 Trades
abstract contract V2SwapRouter is UniswapImmutables, Permit2Payments {
	error V2TooLittleReceived();
	error V2TooMuchRequested();
	error V2InvalidPath();

	function _v2Swap(SwapRoute.Route[] memory path, address recipient, address pair) private {
		unchecked {
			// cached to save on duplicate operations
			(address token0, ) = V2Library.sortTokens(path[0].from, path[0].to);

			uint256 lastIndex = path.length - 1;
			for (uint256 i; i < path.length; i++) {
				(address input, address output) = (path[i].from, path[i].to);
				(
					uint256 decimals0,
					uint256 decimals1,
					uint256 reserve0,
					uint256 reserve1,
					,
					,

				) = IPair(pair).metadata();
				(
					uint256 reserveInput,
					uint256 reserveOutput,
					uint256 decimalsInput,
					uint256 decimalsOutput
				) = input == token0
						? (reserve0, reserve1, decimals0, decimals1)
						: (reserve1, reserve0, decimals1, decimals0);
				uint256 amountInput = ERC20(input).balanceOf(pair) - reserveInput;
				amountInput -=
					(amountInput * IPairFactory(UNISWAP_V2_FACTORY).pairFee(pair)) / 1_000_000;

				uint256 amountOutput = V2Library.getAmountOut(
					amountInput,
					reserveInput,
					reserveOutput,
					path[i].stable,
					decimalsInput,
					decimalsOutput
				);

				console.log(amountInput, reserveInput, reserveOutput);

				(uint256 amount0Out, uint256 amount1Out) = input == token0
					? (uint256(0), amountOutput)
					: (amountOutput, uint256(0));
				address nextPair;
				(nextPair, token0) = i < lastIndex
					? V2Library.pairAndToken0For(
						UNISWAP_V2_FACTORY,
						UNISWAP_V2_PAIR_INIT_CODE_HASH,
						output,
						path[i + 1].to,
						path[i + 1].stable
					)
					: (recipient, address(0));
				IPair(pair).swap(amount0Out, amount1Out, nextPair, new bytes(0));
				pair = nextPair;
			}
		}
	}

	/// @notice Performs a Uniswap v2 exact input swap
	/// @param recipient The recipient of the output tokens
	/// @param amountIn The amount of input tokens for the trade
	/// @param amountOutMinimum The minimum desired amount of output tokens
	/// @param path The path of the trade as an array of token addresses
	/// @param payer The address that will be paying the input
	function v2SwapExactInput(
		address recipient,
		uint256 amountIn,
		uint256 amountOutMinimum,
		SwapRoute.Route[] memory path,
		address payer
	) internal {
		address firstPair = V2Library.pairFor(
			UNISWAP_V2_FACTORY,
			UNISWAP_V2_PAIR_INIT_CODE_HASH,
			path[0].from,
			path[0].to,
			path[0].stable
		);
		if (
			amountIn != Constants.ALREADY_PAID // amountIn of 0 to signal that the pair already has the tokens
		) {
			console.log("take token", amountIn);
			payOrPermit2Transfer(path[0].from, payer, firstPair, amountIn);
		}

		ERC20 tokenOut = ERC20(path[path.length - 1].to);
		uint256 balanceBefore = tokenOut.balanceOf(recipient);

		_v2Swap(path, recipient, firstPair);

		uint256 amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
		if (amountOut < amountOutMinimum) revert V2TooLittleReceived();
	}

	/// @notice Performs a Uniswap v2 exact output swap
	/// @param recipient The recipient of the output tokens
	/// @param amountOut The amount of output tokens to receive for the trade
	/// @param amountInMaximum The maximum desired amount of input tokens
	/// @param path The path of the trade as an array of token addresses
	/// @param payer The address that will be paying the input
	function v2SwapExactOutput(
		address recipient,
		uint256 amountOut,
		uint256 amountInMaximum,
		SwapRoute.Route[] memory path,
		address payer
	) internal {
		(uint256 amountIn, address firstPair) = V2Library.getAmountInMultihop(
			UNISWAP_V2_FACTORY,
			UNISWAP_V2_PAIR_INIT_CODE_HASH,
			amountOut,
			path
		);
		if (amountIn > amountInMaximum) revert V2TooMuchRequested();

		payOrPermit2Transfer(path[0].from, payer, firstPair, amountIn);
		_v2Swap(path, recipient, firstPair);
	}
}
