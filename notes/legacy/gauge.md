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

## In summary:

The legacy `Gauge.sol` contract is a standard _staking contract_ that rewards LPs with emissions.
The redirection of trading fees away from LPs and towards voters happens in a parallel system.
So, by staking in the gauge, LPs are implicitly "forgoing" the fees because the fees are being sent to a different group of users (the voters).
