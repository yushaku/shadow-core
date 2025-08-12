import { ethers } from "hardhat";
import { BigNumber, constants, Contract, ContractTransaction } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import {
  IWETH9,
  MockTimeNonfungiblePositionManager,
  MockTimeSwapRouter,
  PairFlash,
  IClPool,
  TestERC20Metadata,
  ClPoolFactory,
  NFTDescriptor,
  Quoter,
  SwapRouter,
  ClPool,
} from "./../../typechain-types";
import { TestERC20 } from "../../typechain-types/contracts/v2-periphery/test";
import completeFixture from "./shared/completeFixture";
import { FeeAmount, MaxUint128, TICK_SPACINGS } from "./shared/constants";
import { encodePriceSqrt } from "./shared/encodePriceSqrt";
import snapshotGasCost from "./shared/snapshotGasCost";

import { expect } from "./shared/expect";
import { getMaxTick, getMinTick } from "./shared/ticks";
import { computePoolAddress } from "./shared/computePoolAddress";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("PairFlash test", () => {
  let flash: PairFlash;
  let nft: MockTimeNonfungiblePositionManager;
  let token0: TestERC20;
  let token1: TestERC20;
  let factory: ClPoolFactory;
  let quoter: Quoter;

  let wallets;
  let wallet: SignerWithAddress;

  before("grabs signers", async () => {
    wallets = await ethers.getSigners();
    wallet = wallets[0];
  });

  async function createPool(
    tokenAddressA: string,
    tokenAddressB: string,
    fee: FeeAmount,
    price: BigNumber,
  ) {
    if (tokenAddressA.toLowerCase() > tokenAddressB.toLowerCase())
      [tokenAddressA, tokenAddressB] = [tokenAddressB, tokenAddressA];

    await factory.createPool(tokenAddressA, tokenAddressB, fee, price);

    const liquidityParams = {
      token0: tokenAddressA,
      token1: tokenAddressB,
      fee: fee,
      tickLower: getMinTick(TICK_SPACINGS[fee]),
      tickUpper: getMaxTick(TICK_SPACINGS[fee]),
      recipient: wallet.address,
      amount0Desired: 1000000,
      amount1Desired: 1000000,
      amount0Min: 0,
      amount1Min: 0,
      deadline: 1,
    };

    return nft.mint(liquidityParams);
  }

  const flashFixture = async () => {
    const { router, tokens, factory, weth9, nft, pairFlash, quoter } = await completeFixture();
    const token0 = tokens[0];
    const token1 = tokens[1];

    return {
      token0,
      token1,
      flash: pairFlash,
      factory,
      weth9,
      nft,
      quoter,
      router,
    };
  };

  beforeEach("load fixture", async () => {
    ({ factory, token0, token1, flash, nft, quoter } = await loadFixture(flashFixture));

    await token0.approve(nft.address, MaxUint128);
    await token1.approve(nft.address, MaxUint128);
    await createPool(token0.address, token1.address, FeeAmount.LOW, encodePriceSqrt(5, 10));
    await createPool(token0.address, token1.address, FeeAmount.MEDIUM, encodePriceSqrt(1, 1));
    await createPool(token0.address, token1.address, FeeAmount.HIGH, encodePriceSqrt(20, 10));
  });

  describe("flash", () => {
    it("test correct transfer events", async () => {
      //choose amountIn to test
      const amount0In = 1000;
      const amount1In = 1000;

      const fee0 = Math.ceil((amount0In * FeeAmount.MEDIUM) / 1000000);
      const fee1 = Math.ceil((amount1In * FeeAmount.MEDIUM) / 1000000);

      const flashParams = {
        token0: token0.address,
        token1: token1.address,
        fee1: FeeAmount.MEDIUM,
        amount0: amount0In,
        amount1: amount1In,
        fee2: FeeAmount.LOW,
        fee3: FeeAmount.HIGH,
      };
      // pool1 is the borrow pool
      const pool1 = computePoolAddress(
        factory.address,
        [token0.address, token1.address],
        FeeAmount.MEDIUM,
      );
      const pool2 = computePoolAddress(
        factory.address,
        [token0.address, token1.address],
        FeeAmount.LOW,
      );
      const pool3 = computePoolAddress(
        factory.address,
        [token0.address, token1.address],
        FeeAmount.HIGH,
      );

      const expectedAmountOut0 = await quoter.callStatic.quoteExactInputSingle(
        token1.address,
        token0.address,
        FeeAmount.LOW,
        amount1In,
        encodePriceSqrt(20, 10),
      );
      const expectedAmountOut1 = await quoter.callStatic.quoteExactInputSingle(
        token0.address,
        token1.address,
        FeeAmount.HIGH,
        amount0In,
        encodePriceSqrt(5, 10),
      );

      await expect(flash.initFlash(flashParams))
        .to.emit(token0, "Transfer")
        .withArgs(pool1, flash.address, amount0In)
        .to.emit(token1, "Transfer")
        .withArgs(pool1, flash.address, amount1In)
        .to.emit(token0, "Transfer")
        .withArgs(pool2, flash.address, expectedAmountOut0)
        .to.emit(token1, "Transfer")
        .withArgs(pool3, flash.address, expectedAmountOut1)
        .to.emit(token0, "Transfer")
        .withArgs(flash.address, wallet.address, expectedAmountOut0.toNumber() - amount0In - fee0)
        .to.emit(token1, "Transfer")
        .withArgs(flash.address, wallet.address, expectedAmountOut1.toNumber() - amount1In - fee1);
    });

    it("gas", async () => {
      const amount0In = 1000;
      const amount1In = 1000;

      const flashParams = {
        token0: token0.address,
        token1: token1.address,
        fee1: FeeAmount.MEDIUM,
        amount0: amount0In,
        amount1: amount1In,
        fee2: FeeAmount.LOW,
        fee3: FeeAmount.HIGH,
      };
      await snapshotGasCost(flash.initFlash(flashParams));
    });
  });
});
