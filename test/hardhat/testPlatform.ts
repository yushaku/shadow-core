import {
  time,
  impersonateAccount,
  setBalance,
  loadFixture,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import { setERC20Balance } from "../../utils/helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { FeeDistributor, Gauge, Pair } from "../typechain-types";
import { WEEK } from "../../utils/constants";
import { createPair, e } from "../../utils/helpers";
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

    // create pair
    await c.pairFactory.createPair(
      c.shadow.getAddress(),
      c.weth.getAddress(),
      false,
    );
    pair = await ethers.getContractAt(
      "Pair",
      await c.pairFactory.getPair(
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
      ),
    );
    await c.voter.createGauge(pair.getAddress());
    gauge = await ethers.getContractAt(
      "Gauge",
      await c.voter.gauges(pair.getAddress()),
    );
    feeDistributor = await ethers.getContractAt(
      "FeeDistributor",
      await c.voter.feeDistributors(gauge.getAddress()),
    );

    await c.minter.initiateEpochZero();

    // set next block timestamp to the begining of next week
    const now = await time.latest();
    // await time.setNextBlockTimestamp(now.div(WEEK).mul(WEEK).add(WEEK).add(1));
  });

  async function initLper() {
    // transfer LP token to lper
    await c.shadow.approve(c.router.getAddress(), ethers.MaxUint256);
    await c.weth.approve(c.router.getAddress(), ethers.MaxUint256);
    await c.router.addLiquidity(
      c.shadow.getAddress(),
      c.weth.getAddress(),
      false,
      e(10e6),
      e(100),
      0,
      0,
      deployer.getAddress(),
      Date.now(),
    );

    const lpBalance = await pair.balanceOf(deployer.getAddress());
    await pair.connect(deployer).transfer(lper.getAddress(), lpBalance);
    expect(
      await pair.balanceOf(lper.getAddress()),
      "lper should have some LP",
    ).to.gt(0);

    // deposit into gauge
    await pair.connect(lper).approve(gauge.getAddress(), ethers.MaxUint256);
    await gauge.connect(lper)["deposit(uint256,uint256)"](lpBalance, 0);
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
      .createLock(
        await c.shadow.balanceOf(voter.address),
        await c.votingEscrow.MAXTIME(),
      );

    return tokenId;
  }

  it("Simple platform test", async function () {
    // initialize
    await initLper();
    const tokenId = await initVoter();

    // vote for this pair
    await c.voter.connect(voter).vote(tokenId, [pair.getAddress()], [10000]);

    // should be able to change vote
    await c.voter.connect(voter).vote(tokenId, [pair.getAddress()], [20000]);

    // perform a few swaps
    await c.router.swapExactTokensForTokensSimple(
      e(1),
      0,
      c.weth.getAddress(),
      c.shadow.getAddress(),
      false,
      deployer.address,
      Date.now(),
    );
    await c.router.swapExactTokensForTokensSimple(
      e(1000),
      0,
      c.shadow.getAddress(),
      c.weth.getAddress(),
      false,
      deployer.address,
      Date.now(),
    );

    let balances;

    // voter should claim nothing
    balances = {
      shadow: await c.shadow.balanceOf(voter.address),
      weth: await c.weth.balanceOf(voter.address),
    };
    await gauge.claimFees();
    await feeDistributor
      .connect(voter)
      .getReward(tokenId, [c.shadow.getAddress(), c.weth.getAddress()]);
    expect(balances.shadow).eq(
      await c.shadow.balanceOf(voter.address),
    );
    expect(balances.weth).eq(await c.weth.balanceOf(voter.address));

    // go to next epoch
    await time.increase(WEEK);
    await c.minter.updatePeriod();
    await time.increase(WEEK);
    await c.minter.updatePeriod();

    // distribute emissions
    await c.voter.distribute(gauge.getAddress());
    expect(
      await c.shadow.balanceOf(gauge.getAddress()),
      "gauge should have some rewards",
    ).gt(0);

    // lper should claim emission
    balances = {
      shadow: await c.shadow.balanceOf(lper.address),
    };
    await gauge
      .connect(lper)
      .getReward(lper.address, [
        c.shadow.getAddress(),
        c.weth.getAddress(),
      ]);
    expect(balances.shadow).lessThan(
      await c.shadow.balanceOf(lper.address),
    );

    // perform a few swaps
    await c.router.swapExactTokensForTokensSimple(
      e(1),
      0,
      c.weth.getAddress(),
      c.shadow.getAddress(),
      false,
      deployer.address,
      Date.now(),
    );
    await c.router.swapExactTokensForTokensSimple(
      e(1000),
      0,
      c.shadow.getAddress(),
      c.weth.getAddress(),
      false,
      deployer.address,
      Date.now(),
    );

    // voter should claim fees
    balances = {
      shadow: await c.shadow.balanceOf(voter.address),
      weth: await c.weth.balanceOf(voter.address),
    };
    await gauge.claimFees();
    await feeDistributor
      .connect(voter)
      .getReward(tokenId, [c.shadow.getAddress(), c.weth.getAddress()]);
    //expect(balances.shadow).lessThan(await c.shadow.balanceOf(voter.address));
    //expect(balances.weth).lessThan(await c.weth.balanceOf(voter.address));

    // go to next epoch
    await time.increase(WEEK);
    await c.minter.updatePeriod();

    await time.increase(WEEK);
    await c.minter.updatePeriod();

    // console.log('balance before', await c.shadow.balanceOf(c.rewardsDistributor.address));

    // voter should claim growth
    const tokenSize = (await c.votingEscrow.locked(tokenId)).amount;
    await c.rewardsDistributor.connect(voter).claim(tokenId);
    expect(tokenSize).lessThan((await c.votingEscrow.locked(tokenId)).amount);

    // console.log('balance after', await c.shadow.balanceOf(c.rewardsDistributor.address));
  });
});
