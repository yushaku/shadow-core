import { expect } from "chai";
import {
  loadFixture,
  mine,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expandTo18Decimals, encodePrice } from "./hardhat/shared/utilities";
import { Token, UniswapV2Factory, UniswapV2Pair } from "../typechain-types";
import { ContractTransactionReceipt } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

const MINIMUM_LIQUIDITY = 10n ** 3n;

const overrides = {
  gasLimit: 9999999,
};

describe("UniswapV2Pair", function () {
  let factory: UniswapV2Factory;
  let token0: Token;
  let token1: Token;
  let pair: UniswapV2Pair;
  let wallet: HardhatEthersSigner;
  let other: HardhatEthersSigner;

  async function deploy() {
    const Factory = await ethers.getContractFactory("UniswapV2Factory");
    factory = await Factory.deploy();

    const ERC20 = await ethers.getContractFactory("Token");

    token0 = await ERC20.deploy("token0", "token0");

    token1 = await ERC20.deploy("token1", "token1");

    [token0, token1] =
      (await token0.getAddress()) < (await token1.getAddress())
        ? [token0, token1]
        : [token1, token0];

    await factory.createPair(token0.getAddress(), token1.getAddress());
    pair = await ethers.getContractAt("UniswapV2Pair", await factory.pair());
    [wallet, other] = await ethers.getSigners();
  }
  beforeEach(async () => {
    await loadFixture(deploy);
  });

  it("mint", async function () {
    const token0Amount = expandTo18Decimals(1);
    const token1Amount = expandTo18Decimals(4);
    await token0.transfer(await pair.getAddress(), token0Amount);
    await token1.transfer(await pair.getAddress(), token1Amount);

    const expectedLiquidity = expandTo18Decimals(2);
    await expect(pair.mint(wallet.address, overrides))
      .to.emit(pair, "Transfer")
      .withArgs(
        ethers.ZeroAddress,
        "0x000000000000000000000000000000000000dEaD",
        MINIMUM_LIQUIDITY,
      )
      .to.emit(pair, "Transfer")
      .withArgs(
        ethers.ZeroAddress,
        wallet.address,
        expectedLiquidity - MINIMUM_LIQUIDITY,
      )
      .to.emit(pair, "Sync")
      .withArgs(token0Amount, token1Amount)
      .to.emit(pair, "Mint")
      .withArgs(wallet.address, token0Amount, token1Amount);

    expect(await pair.totalSupply()).to.eq(expectedLiquidity);
    expect(await pair.balanceOf(wallet.address)).to.eq(
      expectedLiquidity - MINIMUM_LIQUIDITY,
    );
    expect(await token0.balanceOf(await pair.getAddress())).to.eq(token0Amount);
    expect(await token1.balanceOf(await pair.getAddress())).to.eq(token1Amount);
    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount);
    expect(reserves[1]).to.eq(token1Amount);
  });

  async function addLiquidity(token0Amount: bigint, token1Amount: bigint) {
    await token0.transfer(await pair.getAddress(), token0Amount);
    await token1.transfer(await pair.getAddress(), token1Amount);
    await pair.mint(wallet.address, overrides);
  }
  const swapTestCases: bigint[][] = [
    [1, 5, 10, 1662497915624478906n],
    [1, 10, 5, 453305446940074565n],

    [2, 5, 10, 2851015155847869602n],
    [2, 10, 5, 831248957812239453n],

    [1, 10, 10, 906610893880149131n],
    [1, 100, 100, 987158034397061298n],
    [1, 1000, 1000, 996006981039903216n],
  ].map((a) =>
    a.map((n) => (typeof n === "bigint" ? n : expandTo18Decimals(n))),
  );
  swapTestCases.forEach((swapTestCase, i) => {
    it(`getInputPrice:${i}`, async () => {
      const [swapAmount, token0Amount, token1Amount, expectedOutputAmount] =
        swapTestCase;
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(await pair.getAddress(), swapAmount);
      await expect(
        pair.swap(
          0,
          expectedOutputAmount + 1n,
          wallet.address,
          "0x",
          overrides,
        ),
      ).to.be.revertedWithCustomError(pair, "K");
      await pair.swap(0, expectedOutputAmount, wallet.address, "0x", overrides);
    });
  });

  const optimisticTestCases: bigint[][] = [
    [997000000000000000n, 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .997)
    [997000000000000000n, 10, 5, 1],
    [997000000000000000n, 5, 5, 1],
    [1, 5, 5, 1003009027081243732n], // given amountOut, amountIn = ceiling(amountOut / .997)
  ].map((a) =>
    a.map((n) => (typeof n === "bigint" ? n : expandTo18Decimals(n))),
  );
  optimisticTestCases.forEach((optimisticTestCase, i) => {
    it(`optimistic:${i}`, async () => {
      const [outputAmount, token0Amount, token1Amount, inputAmount] =
        optimisticTestCase;
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(await pair.getAddress(), inputAmount);
      await expect(
        pair.swap(outputAmount + 1n, 0, wallet.address, "0x", overrides),
      ).to.be.revertedWithCustomError(pair, "K");
      await pair.swap(outputAmount, 0, wallet.address, "0x", overrides);
    });
  });

  it("swap:token0", async () => {
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = 1662497915624478906n;
    await token0.transfer(await pair.getAddress(), swapAmount);
    await expect(
      pair.swap(0, expectedOutputAmount, wallet.address, "0x", overrides),
    )
      .to.emit(token1, "Transfer")
      .withArgs(await pair.getAddress(), wallet.address, expectedOutputAmount)
      .to.emit(pair, "Sync")
      .withArgs(token0Amount + swapAmount, token1Amount - expectedOutputAmount)
      .to.emit(pair, "Swap")
      .withArgs(
        wallet.address,
        swapAmount,
        0,
        0,
        expectedOutputAmount,
        wallet.address,
      );

    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount + swapAmount);
    expect(reserves[1]).to.eq(token1Amount - expectedOutputAmount);
    expect(await token0.balanceOf(await pair.getAddress())).to.eq(
      token0Amount + swapAmount,
    );
    expect(await token1.balanceOf(await pair.getAddress())).to.eq(
      token1Amount - expectedOutputAmount,
    );
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(
      totalSupplyToken0 - token0Amount - swapAmount,
    );
    expect(await token1.balanceOf(wallet.address)).to.eq(
      totalSupplyToken1 - token1Amount + expectedOutputAmount,
    );
  });

  it("swap:token1", async () => {
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = 453305446940074565n;
    await token1.transfer(await pair.getAddress(), swapAmount);
    await expect(
      pair.swap(expectedOutputAmount, 0, wallet.address, "0x", overrides),
    )
      .to.emit(token0, "Transfer")
      .withArgs(await pair.getAddress(), wallet.address, expectedOutputAmount)
      .to.emit(pair, "Sync")
      .withArgs(token0Amount - expectedOutputAmount, token1Amount + swapAmount)
      .to.emit(pair, "Swap")
      .withArgs(
        wallet.address,
        0,
        swapAmount,
        expectedOutputAmount,
        0,
        wallet.address,
      );

    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount - expectedOutputAmount);
    expect(reserves[1]).to.eq(token1Amount + swapAmount);
    expect(await token0.balanceOf(await pair.getAddress())).to.eq(
      token0Amount - expectedOutputAmount,
    );
    expect(await token1.balanceOf(await pair.getAddress())).to.eq(
      token1Amount + swapAmount,
    );
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(
      totalSupplyToken0 - token0Amount + expectedOutputAmount,
    );
    expect(await token1.balanceOf(wallet.address)).to.eq(
      totalSupplyToken1 - token1Amount - swapAmount,
    );
  });

  it("swap:gas", async () => {
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    await mine();

    await pair.sync(overrides);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = 453305446940074565n;
    await token1.transfer(await pair.getAddress(), swapAmount);
    await mine();

    const tx = await pair.swap(
      expectedOutputAmount,
      0,
      wallet.address,
      "0x",
      overrides,
    );
    const receipt = (await tx.wait()) as ContractTransactionReceipt;
    expect(receipt.gasUsed).to.eq(73462);
  });

  it("burn", async () => {
    const token0Amount = expandTo18Decimals(3);
    const token1Amount = expandTo18Decimals(3);
    await addLiquidity(token0Amount, token1Amount);

    const expectedLiquidity = expandTo18Decimals(3);
    await pair.transfer(
      await pair.getAddress(),
      expectedLiquidity - MINIMUM_LIQUIDITY,
    );
    await expect(pair.burn(wallet.address, overrides))
      .to.emit(pair, "Transfer")
      .withArgs(
        await pair.getAddress(),
        ethers.ZeroAddress,
        expectedLiquidity - MINIMUM_LIQUIDITY,
      )
      .to.emit(token0, "Transfer")
      .withArgs(await pair.getAddress(), wallet.address, token0Amount - 1000n)
      .to.emit(token1, "Transfer")
      .withArgs(await pair.getAddress(), wallet.address, token1Amount - 1000n)
      .to.emit(pair, "Sync")
      .withArgs(1000n, 1000n)
      .to.emit(pair, "Burn")
      .withArgs(
        wallet.address,
        token0Amount - 1000n,
        token1Amount - 1000n,
        wallet.address,
      );

    expect(await pair.balanceOf(wallet.address)).to.eq(0);
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
    expect(await token0.balanceOf(await pair.getAddress())).to.eq(1000);
    expect(await token1.balanceOf(await pair.getAddress())).to.eq(1000);
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(
      totalSupplyToken0 - 1000n,
    );
    expect(await token1.balanceOf(wallet.address)).to.eq(
      totalSupplyToken1 - 1000n,
    );
  });

  it("price{0,1}CumulativeLast", async () => {
    const token0Amount = expandTo18Decimals(3);
    const token1Amount = expandTo18Decimals(3);
    await addLiquidity(token0Amount, token1Amount);

    const blockTimestamp = (await pair.getReserves())[2];
    await time.setNextBlockTimestamp(blockTimestamp + 1n);
    await pair.sync(overrides);

    const initialPrice = encodePrice(token0Amount, token1Amount);
    expect(await pair.price0CumulativeLast()).to.eq(initialPrice[0]);
    expect(await pair.price1CumulativeLast()).to.eq(initialPrice[1]);
    expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 1n);

    const swapAmount = expandTo18Decimals(3);
    await token0.transfer(await pair.getAddress(), swapAmount);
    await time.setNextBlockTimestamp(blockTimestamp + 10n);
    // swap to a new price eagerly instead of syncing
    await pair.swap(0, expandTo18Decimals(1), wallet.address, "0x", overrides); // make the price nice

    expect(await pair.price0CumulativeLast()).to.eq(initialPrice[0] * 10n);
    expect(await pair.price1CumulativeLast()).to.eq(initialPrice[1] * 10n);
    expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 10n);

    await time.setNextBlockTimestamp(blockTimestamp + 20n);
    await pair.sync(overrides);

    const newPrice = encodePrice(expandTo18Decimals(6), expandTo18Decimals(2));
    expect(await pair.price0CumulativeLast()).to.eq(
      initialPrice[0] * 10n + newPrice[0] * 10n,
    );
    expect(await pair.price1CumulativeLast()).to.eq(
      initialPrice[1] * 10n + newPrice[1] * 10n,
    );
    expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 20n);
  });

  it("feeTo:off", async () => {
    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = 996006981039903216n;
    await token1.transfer(await pair.getAddress(), swapAmount);
    await pair.swap(expectedOutputAmount, 0, wallet.address, "0x", overrides);

    const expectedLiquidity = expandTo18Decimals(1000);
    await pair.transfer(
      await pair.getAddress(),
      expectedLiquidity - MINIMUM_LIQUIDITY,
    );
    await pair.burn(wallet.address, overrides);
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
  });

  it("feeTo:on", async () => {
    await factory.setFeeTo(other.address);

    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = 996006981039903216n;
    await token1.transfer(await pair.getAddress(), swapAmount);
    await pair.swap(expectedOutputAmount, 0, wallet.address, "0x", overrides);

    const expectedLiquidity = expandTo18Decimals(1000);
    await pair.transfer(
      await pair.getAddress(),
      expectedLiquidity - MINIMUM_LIQUIDITY,
    );
    await pair.burn(wallet.address, overrides);
    expect(await pair.totalSupply()).to.eq(
      MINIMUM_LIQUIDITY + 249750499251388n,
    );
    expect(await pair.balanceOf(other.address)).to.eq(249750499251388n);

    // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
    // ...because the initial liquidity amounts were equal
    expect(await token0.balanceOf(await pair.getAddress())).to.eq(
      1000n + 249501683697445n,
    );
    expect(await token1.balanceOf(await pair.getAddress())).to.eq(
      1000n + 250000187312969n,
    );
  });

  it("test fee", async function () {
    const token0Amount = expandTo18Decimals(100);
    const token1Amount = expandTo18Decimals(100);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount =
      (expandTo18Decimals(100) * 10n ** 18n) / expandTo18Decimals(110);
    (expectedOutputAmount * 99n) / 100n;
    await token1.transfer(await pair.getAddress(), swapAmount);

    const tx = await pair.swap(
      expectedOutputAmount,
      0,
      wallet.address,
      "0x",
      overrides,
    );
    console.log(await pair.getReserves());
    const receipt = (await tx.wait()) as ContractTransactionReceipt;
    //expect(receipt.gasUsed).to.eq(73462);
  });
});
