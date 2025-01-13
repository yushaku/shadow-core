import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { setERC20Balance } from "../../utils/helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  FeeDistributor,
  Gauge,
  INonfungiblePositionManager,
  ISwapRouter,
  Pair,
  PairFees,
} from "../typechain-types";
import { WEEK } from "../../utils/constants";
import { e } from "../../utils/helpers";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";

describe("Platform", function () {
  let c: TestDeploy;
  let pair: Pair, gauge: Gauge, feeDistributor: FeeDistributor;
  let deployer: HardhatEthersSigner,
    user: HardhatEthersSigner,
    user2: HardhatEthersSigner,
    user3: HardhatEthersSigner;

  before(async () => {
    c = await loadFixture(testDeploy);
    [deployer, user, user2, user3] = await ethers.getSigners();
  });

  it("Should not have any issues with v1", async function () {
    expect(await c.shadow.balanceOf(deployer.getAddress())).equal(
      ethers.parseEther("100000000"),
    );

    await expect(
      await c.pairFactory.createPair(
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
      ),
    ).to.not.be.reverted;

    pair = await ethers.getContractAt(
      "Pair",
      await c.pairFactory.getPair(
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
      ),
    );

    await expect(c.voter.createGauge(pair.getAddress())).to.not.be.reverted;

    gauge = await ethers.getContractAt(
      "Gauge",
      await c.voter.gauges(pair.getAddress()),
    );

    feeDistributor = await ethers.getContractAt(
      "FeeDistributor",
      await c.voter.feeDistributors(gauge.getAddress()),
    );

    await c.shadow.approve(
      c.votingEscrow.getAddress(),
      ethers.MaxUint256,
    );

    await c.shadow
      .connect(user)
      .approve(c.votingEscrow.getAddress(), ethers.MaxUint256);

    await c.shadow
      .connect(user2)
      .approve(c.votingEscrow.getAddress(), ethers.MaxUint256);

    await c.shadow
      .connect(user3)
      .approve(c.votingEscrow.getAddress(), ethers.MaxUint256);

    await c.votingEscrow.createLock(
      ethers.parseEther("1"),
      await c.votingEscrow.MAXTIME(),
    );

    await c.votingEscrow.createLockFor(
      ethers.parseEther("1"),
      await c.votingEscrow.MAXTIME(),
      user.getAddress(),
    );

    await c.votingEscrow.createLockFor(
      ethers.parseEther("1"),
      await c.votingEscrow.MAXTIME(),
      user2.getAddress(),
    );

    await c.votingEscrow.createLockFor(
      ethers.parseEther("1"),
      await c.votingEscrow.MAXTIME(),
      user3.getAddress(),
    );

    await c.minter.initiateEpochZero();

    await time.increase(WEEK);
    await c.minter.updatePeriod();

    await c.voter.vote(1, [pair.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user)
      .vote(2, [pair.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user2)
      .vote(3, [pair.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user3)
      .vote(4, [pair.getAddress()], [ethers.parseEther("1")]);

    await c.shadow.approve(c.router.getAddress(), ethers.MaxUint256);
    await c.weth.approve(c.router.getAddress(), ethers.MaxUint256);
    await c.router.addLiquidity(
      c.shadow.getAddress(),
      c.weth.getAddress(),
      false,
      ethers.parseEther("10"),
      ethers.parseEther("5"),
      0,
      0,
      deployer.getAddress(),
      Date.now(),
    );

    // generate trade fees and check fee accumulation in pairFees
    let pairFees = await pair.fees();
    let cleoBal = await c.shadow.balanceOf(pairFees);
    let wethBal = await c.weth.balanceOf(pairFees);
    let _cleoBal;
    let _wethBal;

    for (let i = 0; i < 5; i++) {
      await c.router.swapExactTokensForTokensSimple(
        ethers.parseEther("5"),
        0,
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
        deployer.getAddress(),
        Date.now(),
      );
      _cleoBal = await c.shadow.balanceOf(pairFees);
      //expect(_cleoBal).greaterThan(cleoBal);
      cleoBal = _cleoBal;

      await c.router.swapExactTokensForTokensSimple(
        ethers.parseEther("5"),
        0,
        c.weth.getAddress(),
        c.shadow.getAddress(),
        false,
        deployer.getAddress(),
        Date.now(),
      );
      _wethBal = await c.weth.balanceOf(pairFees);
      //expect(_wethBal).greaterThan(wethBal);
      wethBal = _wethBal;
    }

    await pair.approve(gauge.getAddress(), ethers.MaxUint256);
    await gauge.depositAll(1);

    await time.increase(WEEK);
    await c.minter.updatePeriod();

    await c.voter.distribute(gauge.getAddress());

    expect(await c.shadow.balanceOf(feeDistributor.getAddress())).equal(
      cleoBal,
    );
    expect(await c.weth.balanceOf(feeDistributor.getAddress())).equal(wethBal);

    let total =
      (await c.shadow.balanceOf(gauge.getAddress())) +
      (await c.xShadow.balanceOf(gauge.getAddress()));
    let rps = total / 604800n;
    await time.increase(1);
    let earned =
      (await gauge.earned(
        c.shadow.getAddress(),
        deployer.getAddress(),
      )) + (await gauge.earned(c.xShadow.getAddress(), deployer.getAddress()));
    expect(earned).lessThanOrEqual(rps); // small rounding diff is acceptable, as long as not too far

    cleoBal = await c.shadow.balanceOf(pairFees);
    wethBal = await c.weth.balanceOf(pairFees);
    // generate more trading fees
    for (let i = 0; i < 5; i++) {
      await c.router.swapExactTokensForTokensSimple(
        ethers.parseEther("5"),
        0,
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
        deployer.getAddress(),
        Date.now(),
      );
      _cleoBal = await c.shadow.balanceOf(pairFees);
      //expect(_cleoBal).greaterThan(cleoBal);
      cleoBal = _cleoBal;

      await c.router.swapExactTokensForTokensSimple(
        ethers.parseEther("5"),
        0,
        c.weth.getAddress(),
        c.shadow.getAddress(),
        false,
        deployer.getAddress(),
        Date.now(),
      );
      _wethBal = await c.weth.balanceOf(pairFees);
      //expect(_wethBal).greaterThan(wethBal);
      wethBal = _wethBal;
    }

    let feeDistBal0 = await c.shadow.balanceOf(
      feeDistributor.getAddress(),
    );
    let feeDistBal1 = await c.weth.balanceOf(feeDistributor.getAddress());

    const _pairFees = (await ethers.getContractAt(
      "PairFees",
      pairFees,
    )) as PairFees;

    // tests with _pairFees.claimFeesFor(), and pair.claimFees() passed
    await gauge.claimFees();
    expect(
      (await c.shadow.balanceOf(feeDistributor.getAddress())) -
        feeDistBal0,
    ).equal(cleoBal);

    expect(
      (await c.weth.balanceOf(feeDistributor.getAddress())) - feeDistBal1,
    ).equal(wethBal);

    await feeDistributor.getReward(1, [
      c.shadow.getAddress(),
      c.weth.getAddress(),
    ]);
    await feeDistributor
      .connect(user)
      .getReward(2, [c.shadow.getAddress(), c.weth.getAddress()]);
    await feeDistributor
      .connect(user2)
      .getReward(3, [c.shadow.getAddress(), c.weth.getAddress()]);
    await feeDistributor
      .connect(user3)
      .getReward(4, [c.shadow.getAddress(), c.weth.getAddress()]);

    await c.usdc.approve(feeDistributor.getAddress(), ethers.MaxUint256);
    await feeDistributor.incentivize(
      c.usdc.getAddress(),
      ethers.parseUnits("100", 6),
    );

    for (let i = 1; i < 5; i++) {
      await c.voter.poke(i);
    }

    await time.increase(604800);
    await c.minter.updatePeriod();
    await c.voter.distributeAllUnchecked();
  });

  it("Should have no issues with v2 pairs", async function () {
    await c.factory.setFeeProtocol(6);
    expect(await c.nfpManager.votingEscrow()).equal(
      c.votingEscrow.getAddress(),
    );
    await c.factory.createPool(
      c.shadow.getAddress(),
      c.weth.getAddress(),
      10000,
      79228162514264337593543950336n,
    );

    await c.shadow.approve(
      c.nfpManager.getAddress(),
      ethers.MaxUint256,
    );
    await c.weth.approve(c.nfpManager.getAddress(), ethers.MaxUint256);

    const [tokenA, tokenB] =
      c.shadow.getAddress() < c.weth.getAddress()
        ? [c.shadow.getAddress(), c.weth.getAddress()]
        : [c.weth.getAddress(), c.shadow.getAddress()];

    let params;
    params = {
      token0: tokenA,
      token1: tokenB,
      fee: 10000,
      tickLower: -200,
      tickUpper: 200,
      amount0Desired: ethers.parseEther("100000"),
      amount1Desired: ethers.parseEther("100000"),
      amount0Min: 0,
      amount1Min: 0,
      recipient: deployer.getAddress(),
      deadline: Date.now(),
    };
    await c.nfpManager.mint(params);

    const position = await c.nfpManager.positions(1);
    const v2Pool = await ethers.getContractAt(
      "ClPool",
      await c.factory.getPool(position.token0, position.token1, position.fee),
    );
    await c.voter.createCLGauge(
      c.shadow.getAddress(),
      c.weth.getAddress(),
      10000,
    );
    const v2Gauge = await ethers.getContractAt(
      "GaugeV2",
      await c.voter.gauges(v2Pool.getAddress()),
    );
    const v2FeeDist = await ethers.getContractAt(
      "FeeDistributor",
      await c.voter.feeDistributors(v2Gauge.getAddress()),
    );

    await expect(c.nfpManager.switchAttachment(1, 1)).to.not.be.reverted;

    await c.voter.vote(1, [v2Pool.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user)
      .vote(2, [v2Pool.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user2)
      .vote(3, [v2Pool.getAddress()], [ethers.parseEther("1")]);
    await c.voter
      .connect(user3)
      .vote(4, [v2Pool.getAddress()], [ethers.parseEther("1")]);

    let swapParams0: ISwapRouter.ExactInputSingleParamsStruct;
    swapParams0 = {
      tokenIn: c.shadow.getAddress(),
      tokenOut: c.weth.getAddress(),
      fee: 10000,
      recipient: deployer.getAddress(),
      deadline: Date.now(),
      amountIn: ethers.parseEther("1"),
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };

    let swapParams1: ISwapRouter.ExactInputSingleParamsStruct;
    swapParams1 = {
      tokenIn: c.weth.getAddress(),
      tokenOut: c.shadow.getAddress(),
      fee: 10000,
      recipient: deployer.getAddress(),
      deadline: Date.now(),
      amountIn: ethers.parseEther("1"),
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };

    await c.shadow.approve(
      c.swapRouter.getAddress(),
      ethers.MaxUint256,
    );
    await c.weth.approve(c.swapRouter.getAddress(), ethers.MaxUint256);

    for (let i = 0; i < 5; i++) {
      await c.swapRouter.exactInputSingle(swapParams0);
      await c.swapRouter.exactInputSingle(swapParams1);
    }
    console.log(await v2Pool.slot0());
    let t = await time.latest();
    t = (t / WEEK) * WEEK;
    await time.increaseTo(t + WEEK);
    await c.minter.updatePeriod();
    await c.voter.distributeAllUnchecked();

    await c.nfpManager.switchAttachment(1, 1);

    await expect(c.feeCollector.collectProtocolFees(v2Pool.getAddress())).to.not
      .be.reverted;

    let period = await v2FeeDist.getPeriod();
    expect(
      await v2FeeDist.rewardSupply(period, c.shadow.getAddress()),
    ).greaterThan(0);

    expect(
      await v2FeeDist.rewardSupply(period, c.weth.getAddress()),
    ).greaterThan(0);

    console.log(await c.shadow.balanceOf(v2Gauge.getAddress()));

    await time.increase(604800);
    expect(
      await v2Gauge.earned(c.shadow.getAddress(), 1),
    ).lessThanOrEqual(await c.shadow.balanceOf(v2Gauge.getAddress()));

    console.log(await v2Gauge.positionInfo(1));
  });
});
