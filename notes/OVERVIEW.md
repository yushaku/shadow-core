# Top-Level Contracts

## `AccessHub.sol`
Role: Central authority and access control manager for the protocol.
Features: Manages roles (e.g., SWAP_FEE_SETTER, PROTOCOL_OPERATOR), stores important contract addresses, and provides functions for protocol configuration (fee splits, treasury, timelock, etc).
Pattern: Uses OpenZeppelin's AccessControlEnumerableUpgradeable for role-based permissions.

2. `FeeDistributor.sol`
   Role: Handles distribution of protocol fees to participants.
   Features: Tracks balances, rewards, and votes over periods; interacts with voter and plugin contracts.

3. `FeeRecipient.sol`
   Role: Receives and splits fees for a specific pair.
   Features: Binds to a pair and voter, notifies and approves fee distribution.

4. `Gauge.sol`
   Role: Incentivizes pools by distributing rewards for staked LP tokens.
   Features: Manages staking, rewards, and interacts with voter and xShadow contracts.

5. `LauncherPlugin.sol`
   Role: Modular plugin system for pool launchers.
   Features: Manages authorities, operators, and plugin enablement for pools.

## `Minter.sol`

The Minter contract is responsible for:

- Controlling and distributing SHADOW token emissions on a epoch basis.
- Calculating the amount of SHADOW to be emitted each epoch and ensuring emissions follow the protocol’s rules (e.g., supply caps, emission decay/multiplier).
- Coordinating with the voting system (xSHADOW holders) to direct emissions to specific liquidity pools based on governance votes.
- Providing the SHADOW rewards that are distributed to liquidity providers via the gauge system, according to the votes cast by xSHADOW holders.

How it fits into the system:

- xSHADOW holders vote each week to determine how emissions are allocated among different pools.
- The Minter contract receives these votes and mints/distributes SHADOW tokens to the appropriate pools/gauges, in proportion to the votes received.
- Emissions are distributed linearly over each epoch (week).
- The contract enforces emission limits, supply caps, and controls the emission schedule.

## `Pair.sol`

Role: Core AMM pool contract.
Features: Manages liquidity, swaps, oracles, and fee recipients for token pairs.

## `Router.sol`

Role: Main entrypoint for users to interact with pools (add/remove liquidity, swap).
Features: Handles routing, token sorting, WETH integration, and path validation.

## `Shadow.sol`

Role: ERC20 token contract for the protocol.
Features: Mintable, burnable, and supports permit (EIP-2612).

## `ShadowTimelock.sol`

Role: Timelock controller for governance actions.
Features: Inherits OpenZeppelin's TimelockController.

## `TimelockedTransparentUpgradableProxy.sol`

Role: Upgradeable proxy with timelock.
Features: Uses OpenZeppelin's proxy and admin patterns for secure upgrades.

## `VoteModule.sol`

Role: Handles voting, staking, and reward distribution for governance.
Features: Manages staking, cooldowns, and reward calculations.

## `Voter.sol`

Role: Central contract for governance and voting.
Features: Manages gauges, pools, voting, and distribution logic.

## Key Subdirectories

- CL: Likely contains concentrated liquidity logic (e.g., Uniswap v3-style pools, gauges, and interfaces).
- factories: Factory contracts for deploying instances of pools, gauges, or other protocol modules.
- interfaces: Interface definitions for all protocol contracts, ensuring modularity and upgradability.
- libraries: Shared utility libraries.
- xShadow: Likely contains contracts related to the xShadow staking/locking mechanism.
