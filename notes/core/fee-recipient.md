# FeeRecipient

## Overview

The `FeeRecipient` contract plays a key role in the fee collection process for legacy liquidity pools.
It is responsible for receiving a portion of the trading fees from the pools
and forwarding them to the `FeeDistributor` for distribution to the voters.

## Role in Legacy Pools

In the legacy pool ecosystem, each pool can have a designated `feeRecipient` address.
When trading fees are generated in the pool, a portion of these fees (determined by the `feeSplit` variable) is minted as new liquidity provider (LP) tokens and sent to the `feeRecipient` address.

The `FeeRecipient` contract would then be responsible for:

1.  **Burning LP Tokens:** Burning the received LP tokens to claim the underlying assets (the actual fee tokens) from the pool.
2.  **Forwarding Fees:** Sending the claimed fee tokens to the `FeeDistributor` by calling its `notifyRewardAmount()` function.

## Relationship with `FeeCollector` (for CL Pools)

For the Concentrated Liquidity (CL) pools, the `FeeRecipient` contract is not directly used in the fee collection process.
Instead, the `FeeCollector` contract serves a similar purpose.

The `FeeCollector` is responsible for:

1.  **Collecting Protocol Fees:** Directly collecting the protocol fees (in the underlying tokens) from the CL pools.
2.  **Sending Fees to `FeeDistributor`:** Sending the collected fees to the `FeeDistributor` for distribution.

In essence, the `FeeRecipient` (for legacy pools) and the `FeeCollector` (for CL pools) are both responsible for aggregating fees from the liquidity pools and ensuring they are sent to the `FeeDistributor` for distribution to the protocol's stakeholders.
