import {
  time,
  impersonateAccount,
  setBalance,
  loadFixture,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { FeeDistributor, Gauge, Pair } from "../typechain-types";
import { WEEK } from "../../utils/constants";
import { createPair, e, V1Contracts, TestTokens } from "../../utils/helpers";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";

describe("Minter", function () {
  let c: TestDeploy;
  let pair: Pair, gauge: Gauge, feeDistributor: FeeDistributor;

  beforeEach(async () => {
    c = await loadFixture(testDeploy);
    [pair, gauge, feeDistributor] = await createPair(c);
  });

  it("Should mint emission and growth correctly", async function () {
    const minter = c.minter;
    await c.shadow.approve(
      c.votingEscrow.getAddress(),
      ethers.MaxUint256,
    );
    await c.votingEscrow.createLock(e(10), await c.votingEscrow.MAXTIME());

    await minter.initiateEpochZero();

    const now = await time.latest();
    await time.setNextBlockTimestamp((now / WEEK) * WEEK + WEEK * 2 + 1);

    for (let i = 1; i <= 5; i++) {
      await time.increase(WEEK + 1);
      await minter.updatePeriod();
      await c.voter.vote(1, [pair.getAddress()], [1000]);
      const emission = await minter.weeklyEmission();
      const growth = await minter.calculateGrowth(emission);

      console.log(i, emission.toString(), growth.toString());
    }
  });
});
