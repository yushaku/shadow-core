# Legacy Router (Uniswap V2 Style)

A "legacy router" contract, typically based on the Uniswap V2 design, is a fundamental component in many Decentralized Finance (DeFi) protocols. Its primary role is to serve as the main entry point for users to interact with the protocol's liquidity pools. The router itself is stateless (it doesn't hold tokens); it's a utility contract designed to make token swaps and liquidity management safer and more user-friendly.

## Core Functions

### 1. Swapping Tokens

This is the router's most frequent use case. It abstracts away the complexity of interacting directly with individual liquidity pool contracts.

- **Key Functions:**
  - `swapExactTokensForTokens`: The user specifies the _exact_ amount of an input token they want to trade and the _minimum_ amount of the output token they are willing to accept.
  - `swapTokensForExactTokens`: The user specifies the _exact_ amount of an output token they want to receive and the _maximum_ amount of the input token they are willing to spend.
  - `swapExactETHForTokens`: A convenience function for swapping native ETH for an ERC20 token.
    The router automatically handles wrapping the ETH into WETH (Wrapped ETH) to make it compatible with the ERC20-only liquidity pools.

- **Core Concepts:**
  - **Path:** The router enables multi-hop swaps.
    If a direct trading pair doesn't exist (e.g., A/C), a user can specify a path through an intermediary token (e.g., `[addressA, addressB, addressC]`).
    The router will execute the series of trades automatically.
  - **Slippage Protection:** The `amountOutMin` and `amountInMax` parameters are critical safety features.
    They protect users from price changes that can occur between transaction submission and execution.
    If the final price is worse than the user's specified limit, the transaction reverts.
  - **Deadline:** This is another safety mechanism.
    It's a timestamp that marks the absolute latest time the transaction can be executed.
    This prevents a transaction from getting stuck and being executed much later at a disadvantageous price.

### 2. Managing Liquidity

The router also provides a simplified interface for liquidity providers (LPs).

- **Key Functions:**
  - `addLiquidity`: Allows a user to provide a pair of tokens to a liquidity pool.
    The router calculates the correct ratio and transfers the tokens to the pair contract.
    In return, the user receives LP (Liquidity Provider) tokens representing their share of the pool.
  - `removeLiquidity`: Allows a user to burn their LP tokens to withdraw their proportional share of the underlying assets from the pool.
  - `addLiquidityETH`: A convenience function for providing liquidity with native ETH and an ERC20 token.

## System Interactions

A router operates as part of a system of contracts:

1.  **Factory Contract:** The router communicates with the Factory to find the address of a specific liquidity pair.
    If the pair doesn't exist, the Factory is responsible for creating it.
2.  **Pair Contracts:** These contracts hold the token reserves and contain the core pricing logic (the `k = x * y` formula).
    The router calls the `swap()` function on these pair contracts to execute trades.
3.  **WETH Contract:** This contract is used to wrap native ETH into an ERC20-compliant token (WETH), allowing it to be traded in the exchange's liquidity pools.

