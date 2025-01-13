import { Wallet } from "ethers";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ClPoolFactory } from "../../typechain-types";
import { expect } from "./shared/expect";
import snapshotGasCost from "./shared/snapshotGasCost";

import {
  encodePriceSqrt,
  FeeAmount,
  getCreate2Address,
  TICK_SPACINGS,
} from "./shared/utilities";
import { testDeploy } from "../../../utils/testDeployment";

const TEST_ADDRESSES: [string, string] = [
  "0x1000000000000000000000000000000000000000",
  "0x2000000000000000000000000000000000000000",
];

describe("ClPoolFactory", () => {
  let wallet: Wallet, other: Wallet;

  let factory: ClPoolFactory;
  let poolBytecode: string;

  before("create fixture loader", async () => {
    [wallet, other] = await (ethers as any).getSigners();
  });

  before("load pool bytecode", async () => {
    poolBytecode = (await ethers.getContractFactory("ClBeaconProxy")).bytecode;
  });

  beforeEach("deploy factory", async () => {
    const c = await loadFixture(testDeploy);
    factory = c.factory;
  });

  it("owner is deployer", async () => {
    expect(await factory.owner()).to.eq(wallet.address);
  });

  it("factory bytecode size", async () => {
    expect(
      ((await ethers.provider.getCode(factory.getAddress())).length - 2) / 2
    ).to.matchSnapshot();
  });

  it("pool bytecode size", async () => {
    await factory.createPool(
      TEST_ADDRESSES[0],
      TEST_ADDRESSES[1],
      FeeAmount.MEDIUM,
      encodePriceSqrt(1n, 1n).toString()
    );
    const poolAddress = getCreate2Address(
      await factory.getAddress(),
      TEST_ADDRESSES,
      FeeAmount.MEDIUM,
      poolBytecode
    );
    expect(
      ((await ethers.provider.getCode(poolAddress)).length - 2) / 2
    ).to.matchSnapshot();
  });

  it("initial enabled fee amounts", async () => {
    expect(await factory.feeAmountTickSpacing(FeeAmount.LOW)).to.eq(
      TICK_SPACINGS[FeeAmount.LOW]
    );
    expect(await factory.feeAmountTickSpacing(FeeAmount.MEDIUM)).to.eq(
      TICK_SPACINGS[FeeAmount.MEDIUM]
    );
    expect(await factory.feeAmountTickSpacing(FeeAmount.HIGH)).to.eq(
      TICK_SPACINGS[FeeAmount.HIGH]
    );
  });

  async function createAndCheckPool(
    tokens: [string, string],
    feeAmount: FeeAmount,
    tickSpacing: number = TICK_SPACINGS[feeAmount]
  ) {
    const create2Address = getCreate2Address(
      await factory.getAddress(),
      tokens,
      feeAmount,
      poolBytecode
    );
    const create = factory.createPool(
      tokens[0],
      tokens[1],
      feeAmount,
      encodePriceSqrt(1n, 1n).toString()
    );

    await expect(create)
      .to.emit(factory, "PoolCreated")
      .withArgs(
        TEST_ADDRESSES[0],
        TEST_ADDRESSES[1],
        feeAmount,
        tickSpacing,
        create2Address
      );

    await expect(
      factory.createPool(
        tokens[0],
        tokens[1],
        feeAmount,
        encodePriceSqrt(1n, 1n).toString()
      )
    ).to.be.reverted;
    await expect(
      factory.createPool(
        tokens[1],
        tokens[0],
        BigInt(feeAmount),
        encodePriceSqrt(1n, 1n).toString()
      )
    ).to.be.reverted;
    expect(
      await factory.getPool(tokens[0], tokens[1], feeAmount),
      "getPool in order"
    ).to.eq(create2Address);
    expect(
      await factory.getPool(tokens[1], tokens[0], feeAmount),
      "getPool in reverse"
    ).to.eq(create2Address);

    const pool = await ethers.getContractAt("ClPool", create2Address);
    expect(await pool.factory(), "pool factory address").to.eq(
      await factory.getAddress()
    );
    expect(await pool.token0(), "pool token0").to.eq(TEST_ADDRESSES[0]);
    expect(await pool.token1(), "pool token1").to.eq(TEST_ADDRESSES[1]);
    expect(await pool.fee(), "pool fee").to.eq(feeAmount);
    expect(await pool.tickSpacing(), "pool tick spacing").to.eq(tickSpacing);
  }

  describe("#createPool", () => {
    it("succeeds for low fee pool", async () => {
      await createAndCheckPool(TEST_ADDRESSES, FeeAmount.LOW);
    });

    it("succeeds for medium fee pool", async () => {
      await createAndCheckPool(TEST_ADDRESSES, FeeAmount.MEDIUM);
    });
    it("succeeds for high fee pool", async () => {
      await createAndCheckPool(TEST_ADDRESSES, FeeAmount.HIGH);
    });

    it("succeeds if tokens are passed in reverse", async () => {
      await createAndCheckPool(
        [TEST_ADDRESSES[1], TEST_ADDRESSES[0]],
        FeeAmount.MEDIUM
      );
    });

    it("fails if token a == token b", async () => {
      await expect(
        factory.createPool(
          TEST_ADDRESSES[0],
          TEST_ADDRESSES[0],
          FeeAmount.LOW,
          encodePriceSqrt(1n, 1n).toString()
        )
      ).to.be.reverted;
    });

    it("fails if token a is 0 or token b is 0", async () => {
      await expect(
        factory.createPool(
          TEST_ADDRESSES[0],
          ethers.ZeroAddress,
          FeeAmount.LOW,
          encodePriceSqrt(1n, 1n).toString()
        )
      ).to.be.reverted;
      await expect(
        factory.createPool(
          ethers.ZeroAddress,
          TEST_ADDRESSES[0],
          FeeAmount.LOW,
          encodePriceSqrt(1n, 1n).toString()
        )
      ).to.be.reverted;
      await expect(
        factory.createPool(
          ethers.ZeroAddress,
          ethers.ZeroAddress,
          FeeAmount.LOW,
          encodePriceSqrt(1n, 1n).toString()
        )
      ).to.be.revertedWith("IT");
    });

    it("fails if fee amount is not enabled", async () => {
      await expect(
        factory.createPool(
          TEST_ADDRESSES[0],
          TEST_ADDRESSES[1],
          250,
          encodePriceSqrt(1n, 1n).toString()
        )
      ).to.be.reverted;
    });

    it("gas", async () => {
      await snapshotGasCost(
        factory.createPool(
          TEST_ADDRESSES[0],
          TEST_ADDRESSES[1],
          FeeAmount.MEDIUM,
          encodePriceSqrt(1n, 1n).toString()
        )
      );
    });
  });

  describe("#setOwner", () => {
    it("fails if caller is not owner", async () => {
      await expect(factory.connect(other).setOwner(wallet.address)).to.be
        .reverted;
    });

    it("updates owner", async () => {
      await factory.setOwner(other.address);
      expect(await factory.owner()).to.eq(other.address);
    });

    it("emits event", async () => {
      await expect(factory.setOwner(other.address))
        .to.emit(factory, "OwnerChanged")
        .withArgs(wallet.address, other.address);
    });

    it("cannot be called by original owner", async () => {
      await factory.setOwner(other.address);
      await expect(factory.setOwner(wallet.address)).to.be.reverted;
    });
  });

  describe("#enableFeeAmount", () => {
    it("fails if caller is not owner", async () => {
      await expect(factory.connect(other).enableFeeAmount(100, 2)).to.be
        .reverted;
    });
    it("fails if fee is too great", async () => {
      await expect(factory.enableFeeAmount(1000000, 10)).to.be.reverted;
    });
    it("fails if tick spacing is too small", async () => {
      await expect(factory.enableFeeAmount(500, 0)).to.be.reverted;
    });
    it("fails if tick spacing is too large", async () => {
      await expect(factory.enableFeeAmount(500, 16834)).to.be.reverted;
    });
    it("fails if already initialized", async () => {
      await factory.enableFeeAmount(99, 5);
      await expect(factory.enableFeeAmount(99, 10)).to.be.reverted;
    });
    it("sets the fee amount in the mapping", async () => {
      await factory.enableFeeAmount(99, 5);
      expect(await factory.feeAmountTickSpacing(99)).to.eq(5);
    });
    it("emits an event", async () => {
      await expect(factory.enableFeeAmount(99, 5))
        .to.emit(factory, "FeeAmountEnabled")
        .withArgs(99, 5);
    });
    it("enables pool creation", async () => {
      await factory.enableFeeAmount(250, 15);
      await createAndCheckPool(
        [TEST_ADDRESSES[0], TEST_ADDRESSES[1]],
        //@ts-ignore:  Argument of type '250' is not assignable to parameter of type 'FeeAmount'.
        250,
        15
      );
    });
  });
});
