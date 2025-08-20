# router.sol

The legacy `Router.sol` looks very similar to a standard `Uniswap V2 router`.
The core logic for `swapping` and `managing liquidity` is indeed based on it.

## How the it Works

The `Router.sol` contract is the main _entry point_ for users to interact with the v2 pools.

- **Swapping**: Functions like `swapExactTokensForTokens` allow users to trade one token for another, automatically finding the best path through the available liquidity pools.
- **Liquidity Management**: Functions like `addLiquidity` and `removeLiquidity` let users provide or withdraw liquidity from the pools.
- **ETH Handling**: It includes wrapper functions (`addLiquidityETH`, `swapExactETHForTokens`, etc.) to seamlessly handle swaps and liquidity provisioning with `ETH`.

## Why This Custom Router is Necessary

1.  **Stable and Volatile Pools**: This DEX supports both _stable pools_ and _volatile pools_, each using a different mathematical curve.
    The router's functions have a stable parameter to ensure they interact with the correct pool and use the right calculations.

2.  **"Zap and Stake" Functionality**: This is a key feature. The `addLiquidityAndStake` and `addLiquidityETHAndStake` functions allow a user to:
    - Add liquidity to a pool.
    - Receive the LP tokens.
    - Automatically stake those LP tokens in the corresponding `Gauge.sol`.
      All in a _single transaction_. This is a significant UX improvement and requires the router to be aware of the `Voter.sol` and `Gauge.sol`.

3.  **Fee-on-Transfer Token Support**: The router includes specific functions (e.g., `swapExactTokensForTokensSupportingFeeOnTransferTokens`)
    to handle tokens that have a built-in fee mechanism, which is common with "_meme_" tokens.
