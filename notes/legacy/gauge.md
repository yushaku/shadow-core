# Gauge.sol

## Purpose

The legacy `Gauge.sol` is a _staking contract_ that distributes rewards to users who _stake_ their legacy _LP tokens_.
Its main job is to **incentivize liquidity providers** by giving them _YSK emissions_ and other _whitelisted tokens_.

How It Works: A Step-by-Step Guide

1.  _Staking LP Tokens_:
    - A liquidity provider who has `LP tokens` from a legacy pool calls the `deposit` or `depositFor` function on the corresponding Gauge contract.
    - The gauge then takes their `LP tokens` and updates the user's balance in its `balanceOf` mapping and the `totalSupply` of staked tokens.

2.  _Receiving Rewards_ (Emissions):
    - The `Voter.sol`, which distributes the protocol's emissions, calls the `notifyRewardAmount` function on the gauge.
    - This function adds the reward tokens (e.g., `YSK`) to the gauge's reward pool. The rewards are set to be distributed over a 7-day period (DURATION).
    - Other projects can also add their own tokens as rewards to incentivize a pool, as long as the token is whitelisted.

3.  _Calculating Rewards_:
    - The contract calculates rewards using a standard `rewardPerToken` mechanism. This tracks the cumulative rewards distributed for each LP token staked.
    - When a user interacts with the gauge, the earned function calculates their specific rewards by looking at the change in `rewardPerToken`
      since their last interaction and multiplying it by their staked balance.

4.  _Claiming Rewards_:
    - The user calls the `getReward` function to claim their accumulated rewards.
    - The contract calculates their earned rewards and transfers the tokens to them.

## The Fee-Forgoing Mechanism: A Crucial Clarification

The documentation mentions that LPs who stake in the gauge forgo their trading fees.
However, after analyzing the Gauge.sol contract, I can confirm that this contract does not handle the fee-forgoing logic directly.

Instead, the fee redirection is managed by the system I described to you earlier:

- When a `gauge` is created for a legacy pair, the `Voter.sol` sets the pair's `feeRecipient`.
- This `FeeRecipient.sol` _collects_ the _trading fees_ (which are minted as new LP tokens) and passes them to a `FeeDistributor`.
- The `FeeDistributor.sol` then _distributes_ these fees to the _voters_, not the liquidity providers in the gauge.

## Legacy Pool Fee Distribution

The fee claiming and distribution process for legacy pools is quite different from the CL pools, as it involves minting new LP tokens to represent the fees.

Here is a step-by-step breakdown of the process:

### Step 1: Fee Generation

- **Fees are Generated**: Every time a user swaps tokens in a legacy `Pair` contract, a trading fee is taken.
- **Fees Accumulate**: Unlike CL pools, the fees in legacy pools don't accumulate as separate tokens. Instead, the reserves of the pool grow, and the value of the LP tokens increases.

### Step 2: Fee Collection Trigger

Similar to CL pools, the fee collection process is triggered when the `distribute()` function on the `Voter.sol` contract is called for a specific legacy gauge.

As part of the `distribute()` process, the following happens:

- The `Voter` contract calls the `mintFee()` function on the legacy `Pair` contract.

### Step 3: Minting LP Tokens as Fees

This is the key difference in the legacy system.

- **`mintFee()`**: The `Pair` contract calculates the protocol's share of the fees that have accrued since the last collection.
- **New LP Tokens are Minted**: Instead of transferring the underlying tokens, the `Pair` contract mints new LP tokens that represent the value of the collected fees.
- **Sent to `FeeRecipient`**: These newly minted LP tokens are sent to a dedicated `FeeRecipient` contract that is unique to that pair.

### Step 4: The `FeeRecipient` Contract in Action

The `FeeRecipient` contract acts as an intermediary, processing the LP tokens it has received.

1.  **`notifyFees()` is Called**: After `mintFee()` is called, the `Voter` contract immediately calls the `notifyFees()` function on the `FeeRecipient`.
2.  **Treasury Cut**: The `FeeRecipient` first calculates if a portion of the received LP tokens should go to the treasury. If so, it transfers that portion to the treasury address.
3.  **Forwards LP Tokens to Distributor**: The remaining LP tokens are then forwarded to the `FeeDistributor` contract by calling the `notifyRewardAmount()` function.

### Step 5: Distribution to Voters

1.  **`FeeDistributor` Receives LP Tokens**: The `FeeDistributor` receives the LP tokens from the `FeeRecipient` and adds them to its reward pool.
2.  **Voters Claim LP Tokens**: Users who have voted for that specific legacy gauge can then claim their proportional share of those LP tokens from the `FeeDistributor`. They can then hold these LP tokens or burn them to claim the underlying assets.

### Summary of the Flow

'''
Swap in Legacy Pair
↓
Fees accrue in the pool, increasing LP token value
↓
distribute() is called on the Voter contract
↓
Voter calls mintFee() on the Pair contract
↓
Pair mints new LP tokens and sends them to FeeRecipient
↓
Voter calls notifyFees() on the FeeRecipient
↓
FeeRecipient sends a cut to the Treasury
↓
FeeRecipient sends the rest to the FeeDistributor
↓
Voters claim their share of the LP tokens from the FeeDistributor
'''

This system ensures that the fees generated by a legacy pool are distributed to the voters as productive assets (LP tokens) themselves.

