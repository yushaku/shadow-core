# GaugeV3.sol Report

## Overview

`GaugeV3` is the contract where users stake their V3 Liquidity Position NFTs to earn rewards. It serves as the primary mechanism for distributing YSK emissions and other incentives to liquidity providers.

## Core Functionalities

### 1. Reward Distribution

- **`notifyRewardAmount(token, amount)`**: The main entry point for rewards to be added to the gauge.
  The `Minter` contract calls this to distribute YSK emissions, and the `FeeCollector` can also call it to distribute its share of protocol fees.
- **`earned(token, tokenId)`**: A view function that calculates the total pending rewards for a specific staked NFT.
- **`getReward(...)`**: The function users call to claim their accumulated rewards. This function calculates rewards earned period by period and transfers them to the user.

### 2. Claiming LP Fees

A key feature of the `GaugeV3` is that it also handles the collection of the LP's direct trading fees (the 95% share) for staked positions.

- Since the gauge owns the staked NFT, it is the only contract that can call `collect()` on the pool.
- The `rewards` array in the gauge includes the pool's `token0` and `token1` by default.
- When a user calls `getReward` to claim YSK, they can also pass in the pool's tokens to claim their accrued LP fees at the same time. The gauge calls `cachePeriodEarned` which calculates the fees owed and then `_getReward` transfers them to the user.

### 3. Automated Fee Collection

- **`pushFees` modifier**: The `notifyRewardAmount` function has a `pushFees` modifier. This modifier automatically calls `feeCollector.collectProtocolFees(pool)` on the associated pool.
- **This creates a powerful automated cycle**: Whenever new YSK rewards are sent to the gauge, the gauge immediately triggers the collection of protocol fees from the pool. These fees are then routed by the `FeeCollector` right back to a `FeeDistributor`, which can then be distributed through the gauge system.

## Key Interactions

- Holds LP NFTs on behalf of stakers.
- Receives rewards from the `Minter` (for YSK) and potentially the `FeeCollector`.
- Interacts with its corresponding `RamsesV3Pool` to calculate position-specific data (`positionPeriodSecondsInRange`).
- Triggers the `FeeCollector` to collect protocol fees from the pool.
- Is managed by the `Voter` contract (e.g., for adding/removing reward tokens).
