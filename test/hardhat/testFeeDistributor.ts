import {
  time,
  impersonateAccount,
  setBalance,
  loadFixture,
} from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
//import { token } from "../typechain-types/@openzeppelin/contracts";
import { WEEK } from "../../utils/constants";
import {
  e,
  expectBalanceIncrease,
  generateSwapFee,
  getBalances,
  getPair,
  TestTokens,
  V1Contracts,
} from "../../utils/helpers";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";
import { ERC20 } from "../typechain-types";

describe("FeeDistributor", function () {
  let c: TestDeploy;
  let deployer: HardhatEthersSigner,
    user1: HardhatEthersSigner,
    user2: HardhatEthersSigner,
    user3: HardhatEthersSigner;
  let user1TokenId: bigint, user2TokenId: bigint, user3TokenId: bigint;

  let balances, tokens;

  beforeEach(async () => {
    c = await loadFixture(testDeploy);
    await c.minter.initiateEpochZero();

    [deployer, user1, user2, user3] = await ethers.getSigners();
    await c.shadow.approve(
      c.votingEscrow.getAddress(),
      ethers.MaxUint256,
    );

    await c.votingEscrow.createLockFor(
      e(100e3),
      await c.votingEscrow.MAXTIME(),
      user1.address,
    );
    await c.votingEscrow.createLockFor(
      e(100e3),
      await c.votingEscrow.MAXTIME(),
      user2.address,
    );
    await c.votingEscrow.createLockFor(
      e(100e3),
      await c.votingEscrow.MAXTIME(),
      user3.address,
    );

    user3TokenId = await c.votingEscrow.latestTokenId();
    user2TokenId = user3TokenId - 1n;
    user1TokenId = user3TokenId - 2n;

    await c.pairFactory.setFeeSplit(10, 0);

    // set next block timestamp to the begining of next week
    const now = await time.latest();
    await time.setNextBlockTimestamp((now / WEEK) * WEEK + WEEK + 1);

    let tokens = {
      shadow: c.shadow,
      weth: c.weth,
      usdc: c.usdc,
      usdt: c.usdt,
      dei: c.dei,
      deus: c.deus,
      wbtc: c.wbtc,
    };

    for (const token of Object.values(tokens)) {
      await token.approve(c.router.getAddress(), ethers.MaxUint256);
    }

    const pools = [
      [
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
        e(10e6),
        e(100),
      ],
      [c.usdc.getAddress(), c.weth.getAddress(), false, e(150000), e(100)],
      [c.usdc.getAddress(), c.deus.getAddress(), false, e(100000), e(2000)],
      [c.usdc.getAddress(), c.usdt.getAddress(), true, e(1e6), e(1e6)],
      [c.usdc.getAddress(), c.dei.getAddress(), true, e(1e6), e(1e6)],
    ];

    // create pairs
    for (const pool of pools) {
      await c.router.addLiquidity(
        // @ts-ignore
        ...pool,
        0,
        0,
        deployer.address,
        Date.now(),
      );

      const pairAddress = await c.pairFactory.getPair(
        // @ts-ignore
        pool[0],
        pool[1],
        pool[2],
      );

      const _pair = await ethers.getContractAt("Pair", pairAddress);
      await _pair.setFeeSplit();
      await c.voter.createGauge(pairAddress);
    }
  });

  /*
        accouting should be accurate after changing votes multiple times in each epoch
    */
  it("Should account correctly", async function () {
    const ram_weth = await getPair(
      c,
      await c.shadow.getAddress(),
      await c.weth.getAddress(),
      false,
    );
    const weth_usdc = await getPair(
      c,
      await c.usdc.getAddress(),
      await c.weth.getAddress(),
      false,
    );
    const usdc_usdt = await getPair(
      c,
      await c.usdc.getAddress(),
      await c.usdt.getAddress(),
      true,
    );
    const pairs = [ram_weth, weth_usdc, usdc_usdt];

    // user1 votes for ram_weth and weth_usdc equally
    await c.voter
      .connect(user1)
      .vote(
        user1TokenId,
        [ram_weth.pair.getAddress(), weth_usdc.pair.getAddress()],
        [500, 500],
      );

    // user2 votes for weth_usdc and usdc_usdt equally
    await c.voter
      .connect(user2)
      .vote(
        user2TokenId,
        [weth_usdc.pair.getAddress(), usdc_usdt.pair.getAddress()],
        [500, 500],
      );

    await generateSwapFee(c);

    // bribe all pairs with wbtc
    for (const pair of pairs) {
      await c.wbtc.approve(pair.feeDistributor.getAddress(), ethers.MaxUint256);
      await pair.feeDistributor.incentivize(c.wbtc.getAddress(), e(1));
    }

    // epoch flip
    await time.increase(WEEK);
    // distribute rewards to gauges
    await c.voter.distributeAllUnchecked();

    // users should be able to claim their rewards
    tokens = [c.shadow, c.weth, c.usdc, c.wbtc];
    balances = await getBalances(
      await user1.getAddress(),
      tokens as any as ERC20[],
    );
    await c.voter.connect(user1).claimIncentives(
      pairs.map((o) => o.feeDistributor.getAddress()),
      [
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
      ],
      user1TokenId,
    );
    await expectBalanceIncrease(
      await user1.getAddress(),
      tokens as any as ERC20[],
      balances,
    );

    tokens = [c.weth, c.usdc, c.usdt, c.wbtc];
    balances = await getBalances(
      await user2.getAddress(),
      tokens as any as ERC20[],
    );
    await c.voter.connect(user2).claimIncentives(
      pairs.map((o) => o.feeDistributor.getAddress()),
      [
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
      ],
      user2TokenId,
    );
    await expectBalanceIncrease(
      await user2.getAddress(),
      tokens as any as ERC20[],
      balances,
    );

    // user1 changes his votes multiple times
    await c.voter.connect(user1).poke(user1TokenId);
    await c.voter.connect(user1).reset(user1TokenId);
    await c.voter
      .connect(user1)
      .connect(user1)
      .vote(user1TokenId, [usdc_usdt.pair.getAddress()], [1000]);
    await c.voter
      .connect(user1)
      .vote(
        user1TokenId,
        [weth_usdc.pair.getAddress(), usdc_usdt.pair.getAddress()],
        [500, 500],
      );
    await c.voter
      .connect(user1)
      .vote(user1TokenId, [usdc_usdt.pair.getAddress()], [1000]);

    // user2 votes for all pairs
    await c.voter.connect(user2).vote(
      user2TokenId,
      pairs.map((o) => o.pair.getAddress()),
      pairs.map((o) => 1000),
    );

    // user3 votes for all pairs
    await c.voter.connect(user3).vote(
      user3TokenId,
      pairs.map((o) => o.pair.getAddress()),
      pairs.map((o) => 1000),
    );

    await generateSwapFee(c);

    // bribe all pairs with deus
    for (const pair of pairs) {
      await c.deus.approve(pair.feeDistributor.getAddress(), ethers.MaxUint256);
      await pair.feeDistributor.incentivize(c.deus.getAddress(), e(1));
    }

    // epoch flip
    await time.increase(WEEK);
    // distribute rewards to gauges
    await c.voter.distributeAllUnchecked();

    // users should be able to claim their rewards
    // user1
    tokens = [c.usdc, c.usdt, c.deus];
    balances = await getBalances(
      await user1.getAddress(),
      tokens as any as ERC20[],
    );
    await c.voter
      .connect(user1)
      .claimIncentives(
        [usdc_usdt.feeDistributor.getAddress()],
        [tokens.map((o) => o.getAddress())],
        user1TokenId,
      );
    await expectBalanceIncrease(
      await user1.getAddress(),
      tokens as any as ERC20[],
      balances,
    );
    // user2
    tokens = [c.shadow, c.weth, c.usdc, c.usdt, c.deus];
    balances = await getBalances(
      await user2.getAddress(),
      tokens as any as ERC20[],
    );
    await c.voter.connect(user2).claimIncentives(
      pairs.map((o) => o.feeDistributor.getAddress()),
      [
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
      ],
      user2TokenId,
    );
    await expectBalanceIncrease(
      await user2.getAddress(),
      tokens as any as ERC20[],
      balances,
    );
    // user3
    tokens = [c.shadow, c.weth, c.usdc, c.usdt, c.deus];
    balances = await getBalances(
      await user3.getAddress(),
      tokens as any as ERC20[],
    );
    await c.voter.connect(user3).claimIncentives(
      pairs.map((o) => o.feeDistributor.getAddress()),
      [
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
        tokens.map((o) => o.getAddress()),
      ],
      user3TokenId,
    );
    await expectBalanceIncrease(
      await user3.getAddress(),
      tokens as any as ERC20[],
      balances,
    );

    // all fee distributors balance of all tokens should be zero
    tokens = [c.shadow, c.weth, c.usdc, c.usdt, c.wbtc, c.weth];
    for (const pair of pairs) {
      balances = await getBalances(
        await pair.feeDistributor.getAddress(),
        tokens as any as ERC20[],
      );
      Object.values(balances).forEach((balance) =>
        expect(balance).closeTo(0, 10),
      );
    }
  });
});
