# FeeDistributor

## Overview

The `FeeDistributor` contract is a central component of the Shadow Core rewards system.
Its primary responsibility is to distribute fees and other incentives to users
who have staked their tokens and voted for specific liquidity pools (gauges).

## Key Functions

- **Reward Distribution:** The `FeeDistributor` distributes various reward tokens to voters based on their voting weight in a given period (epoch).
- **Incentive Handling:** It allows external users to "incentivize" or "bribe" a pool by sending tokens to the contract, which are then distributed to the voters of that pool.
- **Fee Collection:** It receives fees from the `FeeRecipient` contract (for legacy pools) or the `FeeCollector` contract (for CL pools) and adds them to the pool of rewards to be distributed.

## Interaction with Pools

The `FeeDistributor` is used by both the legacy and Concentrated Liquidity (CL) pools, but the way fees are collected and sent to it differs slightly.

### Legacy Pools

For legacy pools, the `FeeRecipient` contract is responsible for collecting fees (in the form of LP tokens) and sending them to the `FeeDistributor`.

### CL Pools

For CL pools, the `FeeCollector` contract is responsible for collecting protocol fees from the pools and sending them to the `FeeDistributor`.

## Core Mechanics

1.  **`notifyRewardAmount()`:** This function is called by the `FeeRecipient` or `FeeCollector` to notify the `FeeDistributor` of new rewards that are available for distribution.
2.  **`earned()`:** This view function allows users to check the amount of rewards they have earned for a specific token.
3.  **`getReward()`:** This function allows users to claim their earned rewards.
