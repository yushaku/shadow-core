import {
  loadFixture,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { TestDeploy, testDeploy } from "../../utils/testDeployment";
import {
  FeeDistributor,
  Gauge,
  MockFeeDistributor,
  MockGauge,
  MockPair,
  Pair,
  PairBeaconProxy__factory,
  Pair__factory,
} from "../typechain-types";
import { createPair } from "../../utils/helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Factories", function () {
  let c: TestDeploy;
  let pair: Pair;
  let gauge: Gauge;
  let feeDistributor: FeeDistributor;
  let pairTwo: Pair;
  let gaugeTwo: Gauge;
  let feeDistributorTwo: FeeDistributor;
  let deployer: HardhatEthersSigner;
  let randomAddress: HardhatEthersSigner;
  const codeHash = ethers.keccak256(PairBeaconProxy__factory.bytecode);
  before(async () => {
    [deployer, randomAddress] = await ethers.getSigners();
    c = await loadFixture(testDeploy);

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

    await c.pairFactory.createPair(
      c.usdc.getAddress(),
      c.weth.getAddress(),
      false,
    );
    pairTwo = await ethers.getContractAt(
      "Pair",
      await c.pairFactory.getPair(
        c.usdc.getAddress(),
        c.weth.getAddress(),
        false,
      ),
    );
    await c.voter.createGauge(pairTwo.getAddress());
    gaugeTwo = await ethers.getContractAt(
      "Gauge",
      await c.voter.gauges(pairTwo.getAddress()),
    );
    feeDistributorTwo = await ethers.getContractAt(
      "FeeDistributor",
      await c.voter.feeDistributors(gaugeTwo.getAddress()),
    );
  });

  it("Should return the correct initCodeHash for pairFactory", async function () {
    expect(await c.pairFactory.pairCodeHash()).equal(codeHash);
  });

  it("Should return correct pair address in pairFor", async function () {
    expect(
      await c.router.pairFor(
        c.shadow.getAddress(),
        c.weth.getAddress(),
        false,
      ),
    ).equal(await pair.getAddress());
    expect(
      await c.router.pairFor(c.usdc.getAddress(), c.weth.getAddress(), false),
    ).equal(await pairTwo.getAddress());
  });

  it("Should have a new address for each new feeDistributor and gauge", async function () {
    // It would revert if factory tries to redeploy in the same address but just to be sure
    expect(await gauge.getAddress()).not.equal(await gaugeTwo.getAddress());
    expect(await feeDistributor.getAddress()).not.equal(
      await feeDistributorTwo.getAddress(),
    );
  });

  it("Should store the correct gauge and feeDistributor addresses", async function () {
    expect(await gauge.getAddress()).equal(
      await c.voter.gauges(pair.getAddress()),
    );
    expect(await feeDistributor.getAddress()).equal(
      await c.voter.feeDistributors(gauge.getAddress()),
    );
    expect(await gaugeTwo.getAddress()).equal(
      await c.voter.gauges(pairTwo.getAddress()),
    );
    expect(await feeDistributorTwo.getAddress()).equal(
      await c.voter.feeDistributors(gaugeTwo.getAddress()),
    );
  });
});
