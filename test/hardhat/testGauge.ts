import {
  time,
  loadFixture,
  mine,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import {
  Gauge,
  MockPairTwo,
  MockVoter,
  MockVotingEscrow,
  TestERC20,
  RamsesTransparentUpgradeableProxy,
} from "../typechain-types";

describe("Gauge", function () {
  let deployer: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let pair: MockPairTwo;
  let gauge: Gauge;
  let ve: MockVotingEscrow;
  let voter: MockVoter;
  let reward: TestERC20;
  let rewardTwo: TestERC20;
  async function deploy() {
    [deployer, user] = await ethers.getSigners();

    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin");
    const proxyAdmin = await ProxyAdmin.deploy(deployer.address);

    const Pair = await ethers.getContractFactory("MockPairTwo");
    pair = await Pair.deploy();

    await pair.mint(deployer.address, ethers.parseEther("1"));
    await pair.mint(user.address, ethers.parseEther("1"));
    const Ve = await ethers.getContractFactory("MockVotingEscrow");
    ve = await Ve.deploy();
    await ve.initialize(deployer.address);

    const Voter = await ethers.getContractFactory("MockVoter");
    voter = await Voter.deploy();

    const Reward = await ethers.getContractFactory(
      "contracts/mock/ERC20.sol:TestERC20",
    );

    reward = (await Reward.deploy("Test", "Reward")) as TestERC20;

    rewardTwo = (await Reward.deploy("TestTwo", "RewardTwo")) as TestERC20;

    const Gauge = await ethers.getContractFactory("Gauge");
    const Proxy = await ethers.getContractFactory(
      "RamsesTransparentUpgradeableProxy",
    );
    const proxy = await Proxy.deploy(proxyAdmin.getAddress());

    const _gauge = await Gauge.deploy();
    await proxyAdmin.upgradeAndCall(
      proxy.getAddress(),
      _gauge.getAddress(),
      "",
    );

    gauge = await ethers.getContractAt("Gauge", await proxy.getAddress());
    await gauge.initialize(
      pair.getAddress(),
      pair.getAddress(),
      ve.getAddress(),
      voter.getAddress(),
      true,
      [reward.getAddress(), rewardTwo.getAddress()],
    );

    await rewardTwo.approve(gauge.getAddress(), ethers.MaxUint256);
    await reward.approve(gauge.getAddress(), ethers.MaxUint256);
    await pair.approve(gauge.getAddress(), ethers.MaxUint256);
    await pair.connect(user).approve(gauge.getAddress(), ethers.MaxUint256);
  }

  beforeEach(async () => {
    await loadFixture(deploy);
  });
  it("Should not have any issues with notifyReward", async function () {
    const one = ethers.parseEther("1");
    let now = await time.latest();
    await expect(gauge.notifyRewardAmount(reward.getAddress(), one)).to.not.be
      .reverted;
    expect(await reward.balanceOf(gauge.getAddress())).equal(one);
    expect((await gauge.rewardData(reward.getAddress())).rewardRate).equal(
      one / 604800n,
    );
    expect((await gauge.rewardData(reward.getAddress())).periodFinish).equal(
      now + 604800 + 1,
    );
    expect(
      (await gauge.rewardData(reward.getAddress())).rewardPerTokenStored,
    ).equal(0);
    expect(await gauge.rewardPerToken(reward.getAddress())).equal(0);
    expect(
      (await gauge.rewardData(reward.getAddress())).lastUpdateTime,
    ).greaterThanOrEqual(now);
    now = await time.latest();
    await expect(gauge.notifyRewardAmount(reward.getAddress(), one / 2n)).to.be
      .reverted;
    await expect(gauge.notifyRewardAmount(reward.getAddress(), one + 1n)).to.not
      .be.reverted;
    expect(
      (await gauge.rewardData(reward.getAddress())).lastUpdateTime,
    ).greaterThanOrEqual(now);
    expect(
      (await gauge.rewardData(reward.getAddress())).rewardRate,
    ).lessThanOrEqual(one + one / 604800n);
    expect(await gauge.rewardsList()).contains(reward.getAddress());
  });

  it("Should not have any issues with deposits boosted", async function () {
    const one = ethers.parseEther("1");
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 1, [
        reward.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one);
    const derived = (one * 40n) / 100n;
    const adjusted = (one * one) / one + (one * 60n) / 100n;
    const derivedBalance = derived + adjusted;
    expect(await gauge.derivedBalance(deployer.address)).equal(derivedBalance);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance,
    );
    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      reward.getAddress(),
    );
  });

  it("Should not have any issues with withdraws boosted", async function () {
    const one = ethers.parseEther("1");
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);

    await expect(gauge.withdrawAll()).to.not.be.reverted;
    expect(await gauge.balanceOf(deployer.address)).equal(0);
    expect(await gauge.totalSupply()).equal(0);
    expect(await gauge.derivedBalance(deployer.address)).equal(0);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(0);
  });

  it("Should not have any issues with deposits unboosted", async function () {
    const one = ethers.parseEther("1");
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 0, [
        reward.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one);
    const derived = (one * 40n) / 100n;

    const derivedBalance = derived;
    expect(await gauge.derivedBalance(deployer.address)).equal(derivedBalance);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance,
    );
    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      reward.getAddress(),
    );
    await time.increase(604800);
  });

  it("Should not have any issues with withdraws unboosted", async function () {
    const one = ethers.parseEther("1");
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await gauge["deposit(uint256,uint256,address[])"](one, 0, [
      reward.getAddress(),
    ]);

    await expect(gauge.withdrawAll()).to.not.be.reverted;
    expect(await gauge.balanceOf(deployer.address)).equal(0);
    expect(await gauge.totalSupply()).equal(0);
    expect(await gauge.derivedBalance(deployer.address)).equal(0);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(0);
  });

  it("Should not have no issues with reward accounting unboosted", async function () {
    const one = ethers.parseEther("1");
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 0, [
        reward.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await time.increase(604800);
    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should have no issues with reward accounting boosted", async function () {
    const one = ethers.parseEther("1");
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 1, [
        reward.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await time.increase(604800);
    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should have no issues with reward accounting when notify is called before a deposit", async function () {
    const one = ethers.parseEther("1");
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 1, [
        reward.getAddress(),
      ]),
    ).to.not.be.reverted;
    await time.increase(604800);
    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should have no issues with reward accounting when deposit is made an epoch before notifying", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await time.increase(604801);
    await expect(gauge.notifyRewardAmount(reward.getAddress(), one)).to.not.be
      .reverted;
    await time.increase(604800);

    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should not have any issues with multiple deposits unboosted", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 0, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 0, [reward.getAddress()]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.balanceOf(user.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one + one);
    const derived = (one * 40n) / 100n;

    const derivedBalance = derived;
    expect(await gauge.derivedBalance(deployer.address)).equal(derivedBalance);
    expect(await gauge.derivedBalance(user.address)).equal(derivedBalance);

    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance + derivedBalance,
    );

    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      reward.getAddress(),
    );
    expect(await gauge.getRegisteredRewards(user.address)).contains(
      reward.getAddress(),
    );

    await time.increase(604800);
    let deployerEarned = await gauge.earned(
      reward.getAddress(),
      deployer.address,
    );
    let userEarned = await gauge.earned(reward.getAddress(), user.address);
    let deployerBalBefore = await reward.balanceOf(deployer.address);
    let userBalBefore = await reward.balanceOf(user.address);

    await gauge.getReward(deployer.address, [reward.getAddress()]);
    await gauge.connect(user).getReward(user.address, [reward.getAddress()]);
    let deployerBal =
      (await reward.balanceOf(deployer.address)) - deployerBalBefore;
    let userBal = (await reward.balanceOf(user.address)) - userBalBefore;
    expect(deployerEarned).equal(deployerBal);
    expect(userEarned).equal(userBal);

    expect(await gauge.withdrawAll()).to.not.be.reverted;
    expect(await gauge.connect(user).withdrawAll()).to.not.be.reverted;

    let deployerPairBal = await pair.balanceOf(deployer.address);
    let userPairBal = await pair.balanceOf(user.address);

    expect(deployerPairBal).equal(one);
    expect(userPairBal).equal(one);
    expect(await gauge.balanceOf(deployer.address)).equal(0);
    expect(await gauge.balanceOf(user.address)).equal(0);

    expect(await gauge.derivedBalance(deployer.address)).equal(0);
    expect(await gauge.derivedBalance(user.address)).equal(0);

    expect(await gauge.totalSupply()).equal(0);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(0);
  });

  it("Should not have any issues with multiple deposits boosted", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [reward.getAddress()]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.balanceOf(user.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one + one);
    const derived = (one * 40n) / 100n;

    let adjusted = (((one * one) / (one + one)) * 60n) / 100n;
    let derivedBalance = derived * adjusted;

    expect(await gauge.derivedBalances(deployer.address)).equal(derivedBalance);

    adjusted = one + (((one * one) / (one + one)) * 60n) / 100n;
    let userDerivedBalance = derived + adjusted;
    expect(await gauge.derivedBalances(user.address)).equal(userDerivedBalance);

    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance + userDerivedBalance,
    );

    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      await reward.getAddress(),
    );
    expect(await gauge.getRegisteredRewards(user.address)).contains(
      await reward.getAddress(),
    );

    let bal = await reward.balanceOf(deployer.address);

    await gauge.getReward(deployer.address, [reward.getAddress()]);
    bal = (await reward.balanceOf(deployer.address)) - bal;

    await time.increase(604800);
    let deployerEarned = await gauge.earned(
      reward.getAddress(),
      deployer.address,
    );
    let userEarned = await gauge.earned(reward.getAddress(), user.address);
    let deployerBalBefore = await reward.balanceOf(deployer.address);
    let userBalBefore = await reward.balanceOf(user.address);
    console.log(deployerEarned, userEarned);
    await gauge.getReward(deployer.address, [reward.getAddress()]);
    await gauge.connect(user).getReward(user.address, [reward.getAddress()]);
    let deployerBal =
      (await reward.balanceOf(deployer.address)) - deployerBalBefore;
    let userBal = (await reward.balanceOf(user.address)) - userBalBefore;
    expect(deployerEarned).equal(deployerBal);
    expect(userEarned).equal(userBal);
    expect(deployerBal + bal + userBal).lessThanOrEqual(one);
    expect(await gauge.withdrawAll()).to.not.be.reverted;
    expect(await gauge.connect(user).withdrawAll()).to.not.be.reverted;

    let deployerPairBal = await pair.balanceOf(deployer.address);
    let userPairBal = await pair.balanceOf(user.address);

    expect(deployerPairBal).equal(one);
    expect(userPairBal).equal(one);
    expect(await gauge.balanceOf(deployer.address)).equal(0);
    expect(await gauge.balanceOf(user.address)).equal(0);

    expect(await gauge.derivedBalance(deployer.address)).equal(0);
    expect(await gauge.derivedBalance(user.address)).equal(0);

    expect(await gauge.totalSupply()).equal(0);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(0);
  });

  it("Should not have any issues with deposits at different times", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 0, [
      reward.getAddress(),
    ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await time.increase(302400);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 0, [reward.getAddress()]);
    await time.increase(302400);

    let deployerEarned = await gauge.earned(
      reward.getAddress(),
      deployer.address,
    );
    let userEarned = await gauge.earned(reward.getAddress(), user.address);

    expect(deployerEarned + userEarned).lessThanOrEqual(one);
    expect(deployerEarned + userEarned).greaterThan((one * 99n) / 100n);

    let deployerBal = await reward.balanceOf(deployer.address);
    let userBal = await reward.balanceOf(user.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    await expect(
      gauge.connect(user).getReward(user.address, [reward.getAddress()]),
    ).to.not.be.reverted;

    deployerBal = (await reward.balanceOf(deployer.address)) - deployerBal;

    userBal = (await reward.balanceOf(user.address)) - userBal;

    expect(deployerBal + userBal).lessThanOrEqual(one);
    console.log(deployerBal, userBal);
  });

  it("Should not lose rewards when withdrawing", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 0, [
      reward.getAddress(),
    ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 0, [reward.getAddress()]);

    await gauge.withdrawAll();
    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    expect(earned).greaterThan(0);

    await time.increase(3600);
    await mine();
    expect(earned).equal(
      await gauge.earned(reward.getAddress(), deployer.address),
    );
  });

  it("Should not have any issues with multiple deposits and withdraws", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 0, [
      reward.getAddress(),
    ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);

    await time.increase(3600);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 0, [reward.getAddress()]);
    await gauge.withdraw(ethers.parseEther("0.5"));

    await time.increase(3600);
    let bal = await reward.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [reward.getAddress()]);
    bal = (await reward.balanceOf(deployer.address)) - bal;

    await gauge["deposit(uint256,uint256,address[])"](
      ethers.parseEther("0.5"),
      0,
      [reward.getAddress()],
    );

    await time.increase(597600);

    let deployerEarned = await gauge.earned(
      reward.getAddress(),
      deployer.address,
    );
    let userEarned = await gauge.earned(reward.getAddress(), user.address);

    expect(deployerEarned + userEarned).lessThanOrEqual(one);
    expect(deployerEarned + userEarned).greaterThan((one * 99n) / 100n);

    let deployerBal = await reward.balanceOf(deployer.address);
    let userBal = await reward.balanceOf(user.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    await expect(
      gauge.connect(user).getReward(user.address, [reward.getAddress()]),
    ).to.not.be.reverted;

    deployerBal = (await reward.balanceOf(deployer.address)) - deployerBal;

    userBal = (await reward.balanceOf(user.address)) - userBal;

    expect(deployerBal + userBal + bal).lessThanOrEqual(one);
    console.log(deployerBal, userBal);
  });

  it("Should not have no issues with multiple reward tokens", async function () {
    const one = ethers.parseEther("1");

    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 0, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await time.increase(604800);

    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);

    earned = await gauge.earned(rewardTwo.getAddress(), deployer.address);
    bal = await rewardTwo.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [rewardTwo.getAddress()])).to
      .not.be.reverted;
    balAfter = await rewardTwo.balanceOf(deployer.address);
    bal = balAfter - bal;
    console.log(bal);
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should have no issues with multiple reward tokens boosted", async function () {
    const one = ethers.parseEther("1");
    await expect(
      gauge["deposit(uint256,uint256,address[])"](one, 1, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]),
    ).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one);
    const derived = (one * 40n) / 100n;
    const adjusted = (((one * one) / (one + one)) * 60n) / 100n;
    const derivedBalance = derived + adjusted;

    expect(await gauge.derivedBalance(deployer.address)).equal(derivedBalance);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance,
    );

    expect(await gauge.derivedSupplyPerReward(rewardTwo.getAddress())).equal(
      derivedBalance,
    );

    await time.increase(604800);

    let earned = await gauge.earned(reward.getAddress(), deployer.address);
    let bal = await reward.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [reward.getAddress()])).to
      .not.be.reverted;
    let balAfter = await reward.balanceOf(deployer.address);
    bal = balAfter - bal;
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);

    earned = await gauge.earned(rewardTwo.getAddress(), deployer.address);
    bal = await rewardTwo.balanceOf(deployer.address);
    await expect(gauge.getReward(deployer.address, [rewardTwo.getAddress()])).to
      .not.be.reverted;
    balAfter = await rewardTwo.balanceOf(deployer.address);
    bal = balAfter - bal;
    console.log(bal);
    expect(earned).equal(bal);
    expect(earned).lessThanOrEqual(one);
    expect(earned).greaterThanOrEqual((one * 99n) / 100n);
  });

  it("Should not have any issues with multiple deposits and reward tokens boosted", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.balanceOf(user.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one + one);
    const derived = (one * 40n) / 100n;

    let adjusted = (((one * one) / (one + one)) * 60n) / 100n;
    let derivedBalance = derived + adjusted;

    expect(await gauge.derivedBalances(deployer.address)).equal(derivedBalance);

    adjusted = one + (((one * one) / (one + one)) * 60n) / 100n;
    let userDerivedBalance = derived + adjusted;
    expect(await gauge.derivedBalances(user.address)).equal(userDerivedBalance);

    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance + userDerivedBalance,
    );

    expect(await gauge.derivedSupplyPerReward(rewardTwo.getAddress())).equal(
      derivedBalance + userDerivedBalance,
    );

    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      reward.getAddress(),
    );

    expect(await gauge.getRegisteredRewards(deployer.address)).contains(
      await rewardTwo.getAddress(),
    );

    expect(await gauge.getRegisteredRewards(user.address)).contains(
      reward.getAddress(),
    );

    expect(await gauge.getRegisteredRewards(user.address)).contains(
      await rewardTwo.getAddress(),
    );

    let bal = await reward.balanceOf(deployer.address);

    await gauge.getReward(deployer.address, [reward.getAddress()]);
    bal = (await reward.balanceOf(deployer.address)) - bal;

    await time.increase(604800);
    let deployerEarned = await gauge.earned(
      reward.getAddress(),
      deployer.address,
    );
    let userEarned = await gauge.earned(reward.getAddress(), user.address);
    let deployerBalBefore = await reward.balanceOf(deployer.address);
    let userBalBefore = await reward.balanceOf(user.address);
    console.log(deployerEarned, userEarned);
    await gauge.getReward(deployer.address, [reward.getAddress()]);
    await gauge.connect(user).getReward(user.address, [reward.getAddress()]);
    let deployerBal =
      (await reward.balanceOf(deployer.address)) - deployerBalBefore;
    let userBal = (await reward.balanceOf(user.address)) - userBalBefore;
    expect(deployerEarned).equal(deployerBal);
    expect(userEarned).equal(userBal);
    expect(deployerBal + bal + userBal).lessThanOrEqual(one);
    expect(await gauge.withdrawAll()).to.not.be.reverted;
    expect(await gauge.connect(user).withdrawAll()).to.not.be.reverted;

    let deployerPairBal = await pair.balanceOf(deployer.address);
    let userPairBal = await pair.balanceOf(user.address);

    expect(deployerPairBal).equal(one);
    expect(userPairBal).equal(one);
    expect(await gauge.balanceOf(deployer.address)).equal(0);
    expect(await gauge.balanceOf(user.address)).equal(0);

    expect(await gauge.derivedBalance(deployer.address)).equal(0);
    expect(await gauge.derivedBalance(user.address)).equal(0);

    expect(await gauge.totalSupply()).equal(0);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(0);
  });

  it("Should not receive rewards if not in reward pool", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    expect(await gauge.derivedSupplyPerReward(rewardTwo.getAddress())).equal(0);

    await time.increase(604800);

    expect(await gauge.earned(rewardTwo.getAddress(), deployer.address)).equal(
      0,
    );
    let bal = await reward.balanceOf(deployer.address);
    let balTwo = await rewardTwo.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    bal = (await reward.balanceOf(deployer.address)) - bal;
    balTwo = (await rewardTwo.balanceOf(deployer.address)) - balTwo;
    expect(bal).lessThanOrEqual(one);
    expect(balTwo).equal(0);
    console.log(bal);
  });

  it("Should stop accruing rewards after exiting reward pool", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await time.increase(3600);
    await gauge.exitRewardPool(rewardTwo.getAddress());
    let earned = await gauge.earned(rewardTwo.getAddress(), deployer.address);
    console.log(earned);
    await time.increase(3600);
    let bal = await rewardTwo.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [rewardTwo.getAddress()]);
    bal = (await rewardTwo.balanceOf(deployer.address)) - bal;
    expect(await gauge.earned(rewardTwo.getAddress(), deployer.address)).equal(
      0,
    );
    await time.increase(3600);
    expect(await gauge.earned(rewardTwo.getAddress(), deployer.address)).equal(
      0,
    );
    bal = await rewardTwo.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [rewardTwo.getAddress()]);
    bal = (await rewardTwo.balanceOf(deployer.address)) - bal;
    expect(bal).equal(0);
  });

  it("Should start earning when joining a reward pool", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await time.increase(3600);
    expect(await gauge.earned(rewardTwo.getAddress(), deployer.address)).equal(
      0,
    );
    let bal = await rewardTwo.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [rewardTwo.getAddress()]);
    bal = (await rewardTwo.balanceOf(deployer.address)) - bal;
    expect(bal).equal(0);

    await gauge.joinRewardPool(rewardTwo.getAddress());
    await time.increase(604800);
    let earned = await gauge.earned(rewardTwo.getAddress(), deployer.address);
    bal = await rewardTwo.balanceOf(deployer.address);
    await gauge.getReward(deployer.address, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    bal = (await rewardTwo.balanceOf(deployer.address)) - bal;
    console.log(bal);
    expect(earned).equal(bal);
    console.log(await gauge.earned(rewardTwo.getAddress(), user.address));
  });

  it("Should not allow users to withdraw more than they have", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await expect(gauge.withdraw(one + 1000n)).to.be.reverted;
  });

  it("Should not allow users to take other users rewards", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await expect(
      gauge.getReward(user.address, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]),
    ).to.be.reverted;
  });

  it("Should allow voter to claim rewards for users", async function () {
    const one = ethers.parseEther("1");
    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    let _voter = await ethers.getImpersonatedSigner(await voter.getAddress());
    await setBalance(await voter.getAddress(), ethers.MaxUint256);
    await expect(
      gauge
        .connect(_voter)
        .getReward(user.address, [reward.getAddress(), rewardTwo.getAddress()]),
    ).to.not.be.reverted;
  });

  it("Should not have any issues with deposits after notify", async function () {
    const one = ethers.parseEther("1");

    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    await time.increase(3600);

    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);

    console.log(await gauge.earned(reward.getAddress(), deployer.address));
    console.log(await gauge.earned(rewardTwo.getAddress(), deployer.address));
    console.log(await gauge.earned(reward.getAddress(), user.address));
    console.log(await gauge.earned(rewardTwo.getAddress(), user.address));

    await time.increase(604800);
    await expect(
      gauge.getReward(deployer.address, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]),
    ).to.not.be.reverted;
    await expect(
      gauge
        .connect(user)
        .getReward(user.address, [reward.getAddress(), rewardTwo.getAddress()]),
    ).to.not.be.reverted;
  });

  it("Should not have any issues with repetitive actions", async function () {
    const one = ethers.parseEther("1");

    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);

    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    let deployerBal = await reward.balanceOf(deployer.address);
    let deployerBalTwo = await rewardTwo.balanceOf(deployer.address);

    let userBal = await reward.balanceOf(user.address);
    let userBalTwo = await rewardTwo.balanceOf(user.address);

    for (let i = 0; i <= 7; i++) {
      expect(
        await gauge.getReward(deployer.address, [
          reward.getAddress(),
          rewardTwo.getAddress(),
        ]),
      ).to.not.be.reverted;
      expect(
        await gauge
          .connect(user)
          .getReward(user.address, [
            reward.getAddress(),
            rewardTwo.getAddress(),
          ]),
      ).to.not.be.reverted;
      await time.increase(86400);
    }

    console.log((await reward.balanceOf(deployer.address)) - deployerBal);
    console.log((await rewardTwo.balanceOf(deployer.address)) - deployerBalTwo);

    console.log((await reward.balanceOf(user.address)) - userBal);
    console.log((await rewardTwo.balanceOf(user.address)) - userBalTwo);
  });

  it("Should not have any issues with more repetitive actions", async function () {
    const one = ethers.parseEther("1");

    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);
    await gauge
      .connect(user)
      ["deposit(uint256,uint256,address[])"](one, 2, [
        reward.getAddress(),
        rewardTwo.getAddress(),
      ]);

    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    let deployerBal = await reward.balanceOf(deployer.address);
    let deployerBalTwo = await rewardTwo.balanceOf(deployer.address);

    let userBal = await reward.balanceOf(user.address);
    let userBalTwo = await rewardTwo.balanceOf(user.address);

    for (let i = 0; i <= 7; i++) {
      expect(await gauge.withdrawAll()).to.not.be.reverted;
      expect(await gauge.connect(user).withdrawAll()).to.not.be.reverted;

      expect(
        await gauge.getReward(deployer.address, [
          reward.getAddress(),
          rewardTwo.getAddress(),
        ]),
      ).to.not.be.reverted;
      expect(
        await gauge
          .connect(user)
          .getReward(user.address, [
            reward.getAddress(),
            rewardTwo.getAddress(),
          ]),
      ).to.not.be.reverted;

      expect(await gauge.depositAll(1)).to.not.be.reverted;
      expect(await gauge.connect(user).depositAll(2)).to.not.be.reverted;

      await time.increase(86400);
    }

    console.log((await reward.balanceOf(deployer.address)) - deployerBal);
    console.log((await rewardTwo.balanceOf(deployer.address)) - deployerBalTwo);

    console.log((await reward.balanceOf(user.address)) - userBal);
    console.log((await rewardTwo.balanceOf(user.address)) - userBalTwo);

    await gauge.withdrawAll();
    await gauge.connect(user).withdrawAll();
    console.log(await pair.balanceOf(deployer.address));
    console.log(await pair.balanceOf(user.address));
  });

  it("Should return registered rewards", async function () {
    const one = ethers.parseEther("1");
    expect(await gauge.getRegisteredRewards(deployer.address)).to.be.empty;

    await gauge["deposit(uint256,uint256,address[])"](one, 1, [
      reward.getAddress(),
      rewardTwo.getAddress(),
    ]);

    expect(await gauge.getRegisteredRewards(deployer.address)).to.have.members([
      await reward.getAddress(),
      await rewardTwo.getAddress(),
    ]);

    await gauge.exitRewardPool(reward.getAddress());

    expect(await gauge.getRegisteredRewards(deployer.address)).to.not.contain(
      reward.getAddress(),
    );

    await gauge.withdrawAll();

    expect(await gauge.getRegisteredRewards(deployer.address)).to.not.be.empty;

    await gauge.exitRewardPool(rewardTwo.getAddress());

    expect(await gauge.getRegisteredRewards(deployer.address)).to.be.empty;
  });

  it("Should not have any issues with auto join deposit func", async function () {
    const one = ethers.parseEther("1");
    await expect(gauge["deposit(uint256,uint256)"](one, 1)).to.not.be.reverted;
    await gauge.notifyRewardAmount(reward.getAddress(), one);
    await gauge.notifyRewardAmount(rewardTwo.getAddress(), one);

    expect(await gauge.balanceOf(deployer.address)).equal(one);
    expect(await gauge.totalSupply()).equal(one);
    const derived = (one * 40n) / 100n;
    const adjusted = (((one * one) / (one + one)) * 60n) / 100n;
    const derivedBalance = derived + adjusted;
    expect(await gauge.derivedBalance(deployer.address)).equal(derivedBalance);
    expect(await gauge.derivedSupplyPerReward(reward.getAddress())).equal(
      derivedBalance,
    );
    expect(await gauge.getRegisteredRewards(deployer.address)).to.have.members([
      await reward.getAddress(),
      await rewardTwo.getAddress(),
    ]);

    expect(await gauge.derivedSupplyPerReward(rewardTwo.getAddress())).equal(
      derivedBalance,
    );
  });
});
