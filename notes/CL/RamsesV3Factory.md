# RamsesV3Factory.sol Report

## Overview

`RamsesV3Factory` is the central deployment and configuration contract for the Ramses V3 ecosystem. Its primary responsibilities are to create new `RamsesV3Pool` contracts and to manage protocol-level settings, most importantly the fee structures.

## Core Functionalities

### 1. Pool Creation

- **`createPool(tokenA, tokenB, tickSpacing, sqrtPriceX96)`**: The main function to deploy a new liquidity pool for a pair of tokens with a specified `tickSpacing` (which determines the fee tier). It uses a `ramsesV3PoolDeployer` contract to perform the low-level deployment.

### 2. Fee Management

The factory has granular control over the protocol's revenue share (`feeProtocol`).

- **`feeProtocol`**: This value represents the percentage of trading fees that are diverted to the protocol (for voters and the treasury) instead of going to Liquidity Providers (LPs).
- **`setFeeProtocol(uint8 _feeProtocol)`**: A governance function to set the **global default** protocol fee percentage. It is initialized to 5% in the constructor.
- **`setPoolFeeProtocol(address pool, uint8 _feeProtocol)`**: A governance function to set a **per-pool override** for the protocol fee, allowing for different fee structures on different pools.
- **`gaugeFeeSplitEnable(address pool)`**: A special function that can be called by the `Voter` contract to set a pool's `feeProtocol` to **100%**. This diverts all trading fees from LPs to the protocol, making the pool's yield entirely based on token emissions.

### 3. Configuration

- **`enableTickSpacing(...)`**: Allows governance to add new fee tiers (e.g., 0.01%, 0.05%, etc.) to the system.
- **`setFeeCollector(address _feeCollector)`**: Sets the address of the `FeeCollector` contract, which is responsible for collecting and distributing the protocol fees.

## Key Interactions

- Deploys `RamsesV3Pool` contracts.
- Is called by `RamsesV3Pool` to get configuration like the correct `feeProtocol`.
- Can be administered by a governance address (`accessHub`).
