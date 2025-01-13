import {
  loadFixture,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { TestDeploy, testDeploy } from "../utils/testDeployment";
import { Gauge, Pair } from "../typechain-types";
import { createPair } from "../utils/helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("WhitelistOperator", function () {
  let c: TestDeploy;
  let pair: Pair, gauge: Gauge;
  let randomAddress: HardhatEthersSigner;
  let randomAddressTwo = "0x0000008650dABD27fFAd2D6ca7A1F6fE8A16f557";
  const operatorRole =
    "0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929";
  const token = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";

  before(async () => {
    c = await loadFixture(testDeploy);
    await c.voter.setWhitelistOperator(c.commandCenter.getAddress());
    [pair, gauge] = await createPair(c);
    randomAddress = await ethers.getImpersonatedSigner(
      "0xCF2C2fdc9A5A6fa2fc237DC3f5D14dd9b49F66A3",
    );
    await setBalance(await randomAddress.getAddress(), ethers.MaxUint256);
  });

  it("Should be an active operator for voter and xShadow", async function () {
    expect(await c.commandCenter.isActive()).true;
  });

  it("Should allow xShadow whitelisting", async function () {
    await expect(c.commandCenter.whitelistAddress(randomAddress.getAddress()))
      .to.not.be.reverted;
    expect(await c.xShadow.isWhitelisted(randomAddress.getAddress())).true;
  });

  it("Should allow removing xShadow whitelists", async function () {
    await expect(
      c.commandCenter.removeWhitelistedAddress(randomAddress.getAddress()),
    ).to.not.be.reverted;
    expect(await c.xShadow.isWhitelisted(randomAddress.getAddress())).false;
  });

  it("Should not fail when batch whitelisting / blacklisting", async function () {
    await expect(
      c.commandCenter.batchAddWhitelist([
        randomAddress.getAddress(),
        randomAddressTwo,
      ]),
    ).to.not.be.reverted;
    expect(await c.xShadow.isWhitelisted(randomAddress.getAddress())).true;
    expect(await c.xShadow.isWhitelisted(randomAddressTwo)).true;
    await expect(
      c.commandCenter.batchRemoveWhitelist([
        randomAddress.getAddress(),
        randomAddressTwo,
      ]),
    ).to.not.be.reverted;
    expect(await c.xShadow.isWhitelisted(randomAddress.getAddress())).false;
    expect(await c.xShadow.isWhitelisted(randomAddressTwo)).false;
  });

  it("Should allow setting xShadow ratio", async function () {
    let ratio = await c.voter.xRatio();
    await expect(c.commandCenter.setDefaultRatio(ratio + 1n)).to.not.be
      .reverted;
    ratio = ratio + 1n;
    expect(await c.voter.xRatio()).equal(ratio);
  });

  it("Should allow setting gaugeXRaRatios", async function () {
    let ratio = await c.voter.gaugeXRatio(gauge.getAddress());
    await expect(
      c.commandCenter.setGaugeRatios(
        [gauge.getAddress()],
        [ratio + 1n],
      ),
    ).to.not.be.reverted;
    ratio = ratio + 1n;
    expect(await c.voter.gaugeXRatio(gauge.getAddress())).equal(ratio);
  });

  it("Should allow setting gaugeXRaRatios by pair address", async function () {
    let ratio = await c.voter.gaugeXRatio(gauge.getAddress());
    await expect(
      c.commandCenter.setGaugeRatiosByPair(
        [pair.getAddress()],
        [ratio + 1n],
      ),
    ).to.not.be.reverted;
    ratio = ratio + 1n;
    expect(await c.voter.gaugeXRatio(gauge.getAddress())).equal(ratio);
  });

  it("Should allow whitelisting tokens for gauge creation", async function () {
    expect(await c.voter.isWhitelisted(token)).false;
    expect(await c.voter.isForbidden(token)).false;
    await expect(c.commandCenter.whitelistToken(token)).to.not.be.reverted;
    expect(await c.voter.isWhitelisted(token)).true;
  });

  it("Should allow forbidding tokens from gauge creation", async function () {
    await expect(c.commandCenter.forbidToken(token, true)).to.not.be.reverted;
    expect(await c.voter.isForbidden(token)).true;
  });

  it("Should allow adding new operators", async function () {
    expect(
      await c.commandCenter.hasRole(operatorRole, randomAddress.getAddress()),
    ).false;
    await expect(
      c.commandCenter.grantRole(operatorRole, randomAddress.getAddress()),
    ).to.not.be.reverted;
    expect(
      await c.commandCenter.hasRole(operatorRole, randomAddress.getAddress()),
    ).true;
  });

  it("Should allow new operator to interact", async function () {
    // only testing one function
    await expect(
      c.commandCenter.connect(randomAddress).whitelistAddress(randomAddressTwo),
    ).to.not.be.reverted;
  });

  it("Should not allow operator to grant roles", async function () {
    await expect(
      c.commandCenter
        .connect(randomAddress)
        .grantRole(operatorRole, randomAddressTwo),
    ).to.be.reverted;
  });

  it("Should not allow operator to interact when role is revoked", async function () {
    await expect(
      c.commandCenter.revokeRole(operatorRole, randomAddress.getAddress()),
    ).to.not.be.reverted;
    await expect(
      c.commandCenter
        .connect(randomAddress)
        .removeWhitelistedAddress(randomAddressTwo),
    ).to.be.reverted;
  });

  it("Should return the proper xRaRatioByGauge and pair", async function () {
    const ratio = await c.voter.gaugeXRatio(gauge.getAddress());
    expect(await c.commandCenter.getRatioByGauge(gauge.getAddress())).equal(
      ratio,
    );
    expect(await c.commandCenter.getRatioByPair(pair.getAddress())).equal(
      ratio,
    );
  });
});
