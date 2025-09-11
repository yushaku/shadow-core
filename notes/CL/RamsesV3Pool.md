# RamsesV3Pool.sol Report

## Overview

`RamsesV3Pool` is the core contract for a single liquidity pool, based on the Uniswap V3 model. It holds token reserves, facilitates swaps, and manages individual, concentrated liquidity positions.

## Core Functionalities

### 1. Liquidity Provision

- **`mint(...)`**: Allows users to add liquidity within a specific price range (tickLower, tickUpper), creating a liquidity position.
- **`burn(...)`**: Allows users to remove their liquidity from a position.
- **`collect(...)`**: Allows the owner of a liquidity position to claim the trading fees their position has accrued.

### 2. Trading

- **`swap(...)`**: The main function for executing trades. It swaps one token for another, updating the pool's price according to the available liquidity.

### 3. Fee Mechanism

The pool handles the crucial logic of splitting trading fees:

- **LP Fees (e.g., 95%)**: The majority of the fee is accrued for active liquidity providers. The pool tracks this using `feeGrowthGlobal` accumulators. LPs claim this via the `collect` function.
- **Protocol Fees (e.g., 5%)**: A percentage of the fee, determined by `feeProtocol` (set by the Factory), is separated and stored in the `protocolFees` variable.
- **`collectProtocol(...)`**: A permissioned function that allows the designated `feeCollector` contract to withdraw the accumulated protocol fees from the pool.

## Key State Variables

- **`slot0`**: Stores critical, frequently accessed data like the current price (`sqrtPriceX96`), current tick, and the `feeProtocol`.
- **`liquidity`**: The total amount of active liquidity at the current price.
- **`positions`**: A mapping that stores details for each individual LP position, including their liquidity and the fees they are owed (`tokensOwed0`, `tokensOwed1`).
- **`protocolFees`**: Stores the amount of `token0` and `token1` collected as protocol fees, waiting to be withdrawn by the `feeCollector`.

## Key Interactions

- Interacts with users (or a position manager like `NonfungiblePositionManager`) for minting, burning, and swapping.
- Interacts with the `RamsesV3Factory` to sync its `feeProtocol`.
- Interacts with the `FeeCollector` which pulls the protocol fees.
