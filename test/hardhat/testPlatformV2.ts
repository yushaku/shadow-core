import {
  time,
  impersonateAccount,
  setBalance,
  loadFixture,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { FeeDistributor, Gauge, Pair } from "../typechain-types";
import { WEEK } from "../../utils/constants";
import {
  createPair,
  e,
  TestTokens,
  V1Contracts,
  V2Contracts,
  setERC20Balance,
} from "../../utils/helpers";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";

describe("Platform", function () {
  let c: TestDeploy;
  let pair: Pair, gauge: Gauge, feeDistributor: FeeDistributor;
  let deployer: HardhatEthersSigner,
    lper: HardhatEthersSigner,
    voter: HardhatEthersSigner,
    lpBriber: HardhatEthersSigner,
    voteBriber: HardhatEthersSigner;

  beforeEach(async () => {
    c = await loadFixture(testDeploy);
    [deployer, lper, voter, lpBriber, voteBriber] = await ethers.getSigners();
    // [pair, gauge, feeDistributor] = await createPair({...c, ...c.v1});

    await c.minter.initiateEpochZero();

    // set next block timestamp to the begining of next week
    const now = await time.latest();
    // await time.setNextBlockTimestamp(now.div(WEEK).mul(WEEK).add(WEEK).add(1));
  });

  async function initLper() {
    // transfer LP token to lper
    const lpBalance = await pair.balanceOf(deployer.address);
    await pair.connect(deployer).transfer(lper.address, lpBalance);

    // deposit into gauge
    await pair.connect(lper).approve(gauge.getAddress(), ethers.MaxUint256);
    await gauge
      .connect(lper)
      ["deposit(uint256,uint256,address[])"](lpBalance, 0, [
        c.shadow.getAddress(),
      ]);
  }

  async function initVoter() {
    // get some shadow
    await setERC20Balance(
      await c.shadow.getAddress(),
      voter.address,
      e(1),
    );
    console.log(
      "Shadow balance:",
      await c.shadow.balanceOf(voter.address),
    );

    // lock shadow
    await c.shadow
      .connect(voter)
      .approve(c.votingEscrow.getAddress(), ethers.MaxUint256);
    const tokenId = (await c.votingEscrow.connect(voter).latestTokenId()) + 1n;
    await c.votingEscrow
      .connect(voter)
      .createLock(e(1), await c.votingEscrow.MAXTIME());

    return tokenId;
  }

  it("Test Lper", async function () {
    // initialize
    // await initLper();
    const tokenId = await initVoter();
    console.log("Token ID:", tokenId.toString());
  });
});
