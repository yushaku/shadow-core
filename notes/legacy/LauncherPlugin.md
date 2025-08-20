# LauncherPlugin.sol

## Purpose

The `LauncherPlugin.sol` contract is designed to create _special fee arrangements_ for specific liquidity pools, especially for new token launches or "_meme_" tokens.
It allows a portion of the _trading fees_ collected for a pool to be redirected to a _designated recipient_ (like the project's treasury) _instead of being fully distributed to the voters_ who voted for that pool's gauge.

This system is "_plug-n-play_" meaning it can be turned on and off for individual pools by authorized accounts.

### Key Roles

- `Authority`: A whitelisted address, like a token launchpad service. Authorities can enable the plugin for a pool and set the fee configuration.
- `Operator`: A highly privileged address (like a multisig or DAO) that manages the authorities, can disable the plugin for pools, and can migrate configurations from old pools to new ones.
- `AccessHub.sol`: A central contract that manages these roles and permissions.

## How It Works

1.  **Enabling a Pool**: An Authority can enable the _plugin_ for a specific liquidity pool by calling the enablePool function. This marks the pool as active within the LauncherPlugin.

2.  **Setting Fee Configurationsa**: Once a pool is enabled, an Authority can call setConfigs to define the special fee arrangement. This configuration includes:
    - `_take`: The percentage of the fees to be taken.
    - `_recipient`: The address that will receive this portion of the fees.

3.  **Fee Redirection**: The `LauncherPlugin` itself does not perform the fee splitting. It only acts as a configuration storage.
    The actual fee redirection happens in the `FeeDistributor` contract for the pool.

    Here's the inferred workflow:
    - When it's time to distribute the fees for a pool, the `FeeDistributor` contract is expected to query the LauncherPlugin's values function.
    - This values function checks if there's a special fee configuration for that `FeeDistributor`.
    - If a configuration exists, the `FeeDistributor` will:
      1.  Send the specified percentage (`_take`) of the fees to the designated `_recipient`.
      2.  Distribute the `remaining fees` to the `voters` as it normally would.

## In a nutshell:

The `LauncherPlugin.sol` contract is a configuration layer that allows authorized entities to set up special fee-sharing agreements for specific pools.
The actual enforcement of these agreements is handled by the `FeeDistributor` contracts, which read the configurations from the `LauncherPlugin`.
This provides a flexible way to incentivize new projects and token launches on the platform.
