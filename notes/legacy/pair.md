# Pair.sol

## fee management

1. Fee Collection during Swaps: When a user swaps tokens on a legacy _Pair.sol_ pool, a trading fee is taken from their input tokens.

2. Fees are Minted into LP Tokens: The collected fees are not immediately distributed.
   Instead, the _Voter.sol_ contract's distribute function calls the `mintFee function` on the _Pair.sol_ contract.
   This `mintFee function` mints new LP tokens representing the value of the collected fees.

3. Dedicated `FeeRecipient` Contract: This is the key part.
   When a gauge is created for a legacy pair, the _Voter.sol_ contract also creates a dedicated `FeeRecipient` contract for that pair using a _FeeRecipientFactory.sol_.

4. LP Tokens are Sent to the `FeeRecipient`: The newly minted LP tokens(step 2) are sent to this dedicated `FeeRecipient` contract.

5. Distribution to Voters: The `FeeRecipient's job` is to forward these LP tokens to a `FeeDistributor` contract.
   The `FeeDistributor` then distributes these LP tokens as rewards to the users who **voted** for that specific _pair's gauge_.

## In summary:

Instead of fees going directly to liquidity providers, they are converted into new LP tokens and distributed to the users who govern the protocol by voting on gauges.
This creates a direct link between participating in governance and earning a share of the protocol's revenue.

This mechanism involves the following contracts:

- `Pair.sol`: Collects the fees.
- `Voter.sol`: Orchestrates the process of minting fees and creating the fee-related contracts.
- `PairFactory.sol`: Creates the Pair.sol contracts.
- `FeeRecipientFactory.sol`: Creates the dedicated `FeeRecipient` contracts.
