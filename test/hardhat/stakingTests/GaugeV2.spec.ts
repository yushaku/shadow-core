import { Decimal } from "decimal.js";
import {
  BigNumberish,
  Wallet,
  ContractTransactionResponse,
  ContractTransactionReceipt,
  LogDescription
} from "ethers";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import helpers from "@nomicfoundation/hardhat-network-helpers";
import {
  FeeDistributor,
  GaugeV2,
  IClPool,
  MockTimeClPool,
  TestERC20,
  TestClPoolCallee,
} from "../../typechain-types";
import { expect } from "../uniswapV3CoreTests/shared/expect";
import { poolFixture } from "../uniswapV3CoreTests/shared/fixtures";
import {
  formatPrice,
  formatTokenAmount,
} from "../uniswapV3CoreTests/shared/format";
import {
  createPoolFunctions,
  encodePriceSqrt,
  expandTo18Decimals,
  FeeAmount,
  getMaxLiquidityPerTick,
  getMaxTick,
  getMinTick,
  MAX_SQRT_RATIO,
  MaxUint128,
  MIN_SQRT_RATIO,
  TICK_SPACINGS,
} from "../uniswapV3CoreTests/shared/utilities";
import exp from "constants";
import { TestDeploy } from "../../../utils/testDeployment";
import { positionHash, setERC20Balance } from "../../../utils/helpers";

Decimal.config({ toExpNeg: -500, toExpPos: 500 });

const WEEK = 86400 * 7;

const Q96 = 2n ** 96n;

interface BaseSwapTestCase {
  zeroForOne: boolean;
  sqrtPriceLimit?: bigint;
  advanceTime?: number;
}
interface SwapExact0For1TestCase extends BaseSwapTestCase {
  zeroForOne: true;
  exactOut: false;
  amount0: bigint;
  sqrtPriceLimit?: bigint;
}
interface SwapExact1For0TestCase extends BaseSwapTestCase {
  zeroForOne: false;
  exactOut: false;
  amount1: bigint;
  sqrtPriceLimit?: bigint;
}
interface Swap0ForExact1TestCase extends BaseSwapTestCase {
  zeroForOne: true;
  exactOut: true;
  amount1: bigint;
  sqrtPriceLimit?: bigint;
}
interface Swap1ForExact0TestCase extends BaseSwapTestCase {
  zeroForOne: false;
  exactOut: true;
  amount0: bigint;
  sqrtPriceLimit?: bigint;
}
interface SwapToHigherPrice extends BaseSwapTestCase {
  zeroForOne: false;
  sqrtPriceLimit: bigint;
  advanceTime?: number;
}
interface SwapToLowerPrice extends BaseSwapTestCase {
  zeroForOne: true;
  sqrtPriceLimit: bigint;
  advanceTime?: number;
}
type SwapTestCase =
  | SwapExact0For1TestCase
  | Swap0ForExact1TestCase
  | SwapExact1For0TestCase
  | Swap1ForExact0TestCase
  | SwapToHigherPrice
  | SwapToLowerPrice;

function swapCaseToDescription(testCase: SwapTestCase): string {
  const priceClause = testCase?.sqrtPriceLimit
    ? ` to price ${formatPrice(testCase.sqrtPriceLimit)}`
    : "";

  if (testCase.zeroForOne) {
    return `swap token0 for token1${priceClause} after ${testCase?.advanceTime} seconds`;
  } else {
    return `swap token1 for token0${priceClause} after ${testCase?.advanceTime} seconds`;
  }
}

type PoolFunctions = ReturnType<typeof createPoolFunctions>;

// can't use address zero because the ERC20 token does not allow it
const SWAP_RECIPIENT_ADDRESS = ethers.ZeroAddress.slice(0, -1) + "1";
const POSITION_PROCEEDS_OUTPUT_ADDRESS = ethers.ZeroAddress.slice(0, -1) + "2";

async function executeSwap(
  pool: MockTimeClPool,
  testCase: SwapTestCase,
  poolFunctions: PoolFunctions,
): Promise<ContractTransactionResponse> {
  let swap: ContractTransactionResponse;
  if ("exactOut" in testCase) {
    if (testCase.exactOut) {
      if (testCase.zeroForOne) {
        swap = await poolFunctions.swap0ForExact1(
          testCase.amount1,
          SWAP_RECIPIENT_ADDRESS,
          testCase.sqrtPriceLimit,
        );
      } else {
        swap = await poolFunctions.swap1ForExact0(
          testCase.amount0,
          SWAP_RECIPIENT_ADDRESS,
          testCase.sqrtPriceLimit,
        );
      }
    } else {
      if (testCase.zeroForOne) {
        swap = await poolFunctions.swapExact0For1(
          testCase.amount0,
          SWAP_RECIPIENT_ADDRESS,
          testCase.sqrtPriceLimit,
        );
      } else {
        swap = await poolFunctions.swapExact1For0(
          testCase.amount1,
          SWAP_RECIPIENT_ADDRESS,
          testCase.sqrtPriceLimit,
        );
      }
    }
  } else {
    if (testCase.zeroForOne) {
      swap = await poolFunctions.swapToLowerPrice(
        testCase.sqrtPriceLimit,
        SWAP_RECIPIENT_ADDRESS,
      );
    } else {
      swap = await poolFunctions.swapToHigherPrice(
        testCase.sqrtPriceLimit,
        SWAP_RECIPIENT_ADDRESS,
      );
    }
  }
  return swap;
}

interface Position {
  tickLower: bigint;
  tickUpper: bigint;
  liquidity: bigint;
}

interface PoolTestCase {
  description: string;
  feeAmount: number;
  tickSpacing: bigint;
  startingPrice: bigint;
  positions: Position[];
  swapTests?: SwapTestCase[];
}

const TEST_POOLS: PoolTestCase[] = [
  {
    description: "low fee, 1:1 price, 2e18 max range liquidity",
    feeAmount: FeeAmount.LOW,
    tickSpacing: TICK_SPACINGS[FeeAmount.LOW],
    startingPrice: BigInt(encodePriceSqrt(1n, 1n).toString()),
    positions: [
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.LOW]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.LOW]),
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
  {
    description:
      "medium fee, 1:1 price, additional liquidity around current price",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(1n, 1n).toString()),
    positions: [
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: -TICK_SPACINGS[FeeAmount.MEDIUM],
        liquidity: expandTo18Decimals(2n),
      },
      {
        tickLower: TICK_SPACINGS[FeeAmount.MEDIUM],
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
  {
    description: "medium fee, token0 liquidity only",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(1n, 1n).toString()),
    positions: [
      {
        tickLower: 0n,
        tickUpper: 2000n * TICK_SPACINGS[FeeAmount.MEDIUM],
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
  {
    description: "medium fee, token1 liquidity only",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(1n, 1n).toString()),
    positions: [
      {
        tickLower: -2000n * TICK_SPACINGS[FeeAmount.MEDIUM],
        tickUpper: 0n,
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
  {
    description: "close to max price",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(2n ** 127n, 1n).toString()),
    positions: [
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
  {
    description: "close to min price",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(1n, 2n ** 127n).toString()),
    positions: [
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
    ],
  },
];

const nfps: {
  tokenId: BigNumberish;
  tickLower: BigNumberish;
  tickUpper: BigNumberish;
  liquidity: BigNumberish;
  amount0: BigNumberish;
  amount1: BigNumberish;
}[] = [];

const testNfps = [{ tokenId: 1 }];

describe("GaugeV2 tests", () => {
  let wallet: Wallet, other: Wallet;

  before("create fixture loader", async () => {
    [wallet, other] = await (ethers as any).getSigners();
  });

  const poolCase: PoolTestCase = {
    description:
      "medium fee, 1:1 price, additional liquidity around current price",
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: BigInt(encodePriceSqrt(1n, 1n).toString()),
    positions: [
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
      {
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: -TICK_SPACINGS[FeeAmount.MEDIUM] * 2n,
        liquidity: expandTo18Decimals(2n),
      },
      {
        tickLower: TICK_SPACINGS[FeeAmount.MEDIUM] * 2n,
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2n),
      },
    ],
    swapTests: [
      // swap arbitrary input to price
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(5n, 2n).toString()),
        zeroForOne: false,
        advanceTime: 3600,
      },
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(6n, 2n).toString()),
        zeroForOne: false,
        advanceTime: 3600,
      },
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(7n, 2n).toString()),
        zeroForOne: false,
        advanceTime: 3600,
      },
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(2n, 5n).toString()),
        zeroForOne: true,
        advanceTime: 3600,
      },
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(2n, 7n).toString()),
        zeroForOne: true,
        advanceTime: 3600,
      },
      {
        sqrtPriceLimit: BigInt(encodePriceSqrt(2n, 6n).toString()),
        zeroForOne: false,
        advanceTime: 3600,
      },
    ],
  };

  const writingSwaps: SwapTestCase[] = [
    {
      zeroForOne: true,
      exactOut: false,
      amount0: expandTo18Decimals(1n),
    },
    {
      zeroForOne: false,
      exactOut: false,
      amount1: expandTo18Decimals(1n),
    },
  ];

  describe(poolCase.description, () => {
    async function poolCaseFixture() {
      const {
        createNormalPool,
        createGauge,
        token0,
        token1,
        swapTargetCallee: swapTarget,
        c,
      } = await loadFixture(poolFixture);
      const pool = await createNormalPool(
        poolCase.feeAmount,
        poolCase.startingPrice,
      );
      const { gauge, feeDistributor } = await createGauge(
        await pool.getAddress(),
      );
      const poolFunctions = createPoolFunctions({
        swapTarget,
        token0,
        token1,
        pool,
        nfpManager: c.nfpManager,
      });
      await pool.initializeTime();
      //await pool["initialize(uint160)"](poolCase.startingPrice);
      // mint all positions normally and via NFP manager
      for (const position of poolCase.positions) {
        console.log("mint time", await pool.time());
        const tx = await poolFunctions.mint(
          wallet.address,
          position.tickLower,
          position.tickUpper,
          position.liquidity,
        );
        const mintReceipt = (await tx.wait()) as ContractTransactionReceipt;
        let parsedEvents:LogDescription[] = [];

        if (mintReceipt.logs) {
          for (let log of mintReceipt.logs) {
            try {
              // Attempt to parse each log using the contract's interface.
              // This is assuming 'pool' is your contract instance and it has an updated interface in ethers v6.
              const parsedLog = pool.interface.parseLog(log) as LogDescription;
              // Add the parsed log to your array if it matches the "Mint" event.
              if (parsedLog.name === "Mint") {
                parsedEvents.push(parsedLog);
              }
            } catch (error) {
              // If parsing fails, it's likely because the log is not from an expected event.
              // You can handle or ignore this error based on your needs.
              console.error("Error parsing log:", error);
            }
          }
        }

        const { amount0, amount1 } = parsedEvents[0].args;

        const nfpTx = await poolFunctions.mintViaNFP(
          wallet.address,
          position.tickLower,
          position.tickUpper,
          amount0,
          amount1,
        );
        const nfpReceipt = await nfpTx.wait();

        let nfpEvents = nfpReceipt.events?.map((event) => {
          let parsed;

          try {
            parsed = c.nfpManager.interface.parseLog(event);
          } catch {
            parsed = null;
          }

          return parsed;
        });

        nfpEvents = nfpEvents?.filter((event) => {
          return event?.name == "Transfer";
        });

        const nfpTokenId: BigNumberish = nfpEvents![0]!.args.tokenId;

        nfps.push({
          tokenId: nfpTokenId,
          tickLower: position.tickLower,
          tickUpper: position.tickUpper,
          liquidity: position.liquidity,
          amount0,
          amount1,
        });
      }

      const [poolBalance0, poolBalance1] = await Promise.all([
        token0.balanceOf(pool.address),
        token1.balanceOf(pool.address),
      ]);

      return {
        token0,
        token1,
        pool,
        gauge,
        feeDistributor,
        poolFunctions,
        poolBalance0,
        poolBalance1,
        swapTarget,
        c,
      };
    }

    async function compareSnapshot(period: BigNumberish) {
      const results = [];
      const liquidity = ethers.utils.formatEther(await pool.liquidity());
      const boostedLiquidity = ethers.utils.formatEther(
        await pool.boostedLiquidity(),
      );

      results.push({ liquidity, boostedLiquidity });
      for (const position of poolCase.positions) {
        const earned = await gauge[
          "periodEarned(uint256,address,address,uint256,int24,int24)"
        ](
          period,
          token0.address,
          wallet.address,
          0,
          position.tickLower,
          position.tickUpper,
        );

        const _results = {
          name: "direct position",
          tickLower: position.tickLower,
          tickUpper: position.tickUpper,
          earned: ethers.utils.formatEther(earned),
        };

        results.push(_results);
      }

      for (const nfp of nfps) {
        const earned = await gauge["periodEarned(uint256,address,uint256)"](
          period,
          token0.address,
          nfp.tokenId,
        );

        const _results = {
          name: `nfp tokenId ${nfp.tokenId}`,
          tickLower: nfp.tickLower,
          tickUpper: nfp.tickUpper,
          earned: ethers.utils.formatEther(earned),
        };

        results.push(_results);
      }

      expect(results).to.matchSnapshot("Positions earned");
    }

    let token0: TestERC20;
    let token1: TestERC20;

    let poolBalance0: BigNumber;
    let poolBalance1: BigNumber;

    let pool: MockTimeClPool;
    let gauge: GaugeV2;
    let feeDistributor: FeeDistributor;
    let swapTarget: TestClPoolCallee;
    let poolFunctions: PoolFunctions;
    let c: TestDeploy;

    let veNftTokenId: BigNumber;

    let positionInfo: Awaited<ReturnType<MockTimeClPool["positions"]>>;
    let boostInfo: Awaited<
      ReturnType<MockTimeClPool["boostInfos(uint256,bytes32)"]>
    >;
    let positionPeriodSecondsInRange: Awaited<
      ReturnType<MockTimeClPool["positionPeriodSecondsInRange"]>
    >;

    let periodInfo: Awaited<ReturnType<MockTimeClPool["periods"]>>;

    async function setUpRewards() {
      // set up rewards, each unboosted second is 1e18
      await token0.approve(gauge.address, ethers.constants.MaxUint256);
      await gauge.notifyRewardAmount(
        token0.address,
        expandTo18Decimals(WEEK / 0.4),
      );
    }

    before("load fixture", async () => {
      ({
        token0,
        token1,
        pool,
        gauge,
        feeDistributor,
        poolFunctions,
        poolBalance0,
        poolBalance1,
        swapTarget,
        c,
      } = await loadFixture(poolCaseFixture));

      await setUpRewards();
    });

    for (const testCase of poolCase.swapTests!) {
      it(swapCaseToDescription(testCase), async () => {
        // advance time before trade if defined
        if (testCase.advanceTime ?? 0 > 0) {
          await pool.advanceTime(testCase.advanceTime!);
        }
        // console.log("pool time", await pool.time());
        // console.log("before swap:", await pool.observe([0]));

        await executeSwap(pool, testCase, poolFunctions);

        // console.log("pool time", await pool.time());
        // console.log("after swap:", await pool.observe([0]));

        const period = (await pool.time()).div(WEEK);
        await compareSnapshot(period);
      });
    }

    it("positionInfo", async () => {
      const [liquidity] = await gauge.positionInfo(1);
      expect(liquidity).to.be.eq(poolCase.positions[0].liquidity);
    });

    describe("advance period, period earned should stay, new period earned should be 0", () => {
      let oldPeriod: BigNumber;
      let newPeriod: BigNumber;
      before(async () => {
        const lastTime = await pool.time();

        oldPeriod = lastTime.div(WEEK);
        newPeriod = oldPeriod.add(1);

        const delta = newPeriod.mul(WEEK).sub(lastTime);

        await pool.advanceTime(delta);
      });
      it("old period", async () => {
        await compareSnapshot(oldPeriod);
      });
      it("new period", async () => {
        // await expect(
        //     gauge.earned(token0.address, nfps[0].tokenId),
        //     "should revert before writing into the new period"
        // ).to.be.revertedWith("FTR");

        expect(
          await gauge["periodEarned(uint256,address,uint256)"](
            newPeriod,
            token0.address,
            nfps[0].tokenId,
          ),
          "untouched period should report 0",
        ).to.eq(0);

        // write something into the pool to advance period
        for (const swap of writingSwaps) {
          await executeSwap(pool, swap, poolFunctions);
        }

        await compareSnapshot(newPeriod);
      });
    });

    describe("test again in the new period", () => {
      before(async () => {
        // notify rewards for the new week
        await setUpRewards();
      });

      for (const testCase of poolCase.swapTests!) {
        it(swapCaseToDescription(testCase), async () => {
          // advance time before trade if defined
          if (testCase.advanceTime ?? 0 > 0) {
            await pool.advanceTime(testCase.advanceTime!);
          }
          console.log("pool time", await pool.time());
          console.log("before swap:", await pool.observe([0]));

          await executeSwap(pool, testCase, poolFunctions);

          console.log("pool time", await pool.time());
          console.log("after swap:", await pool.observe([0]));

          const period = (await pool.time()).div(WEEK);
          await compareSnapshot(period);
        });
      }
    });

    describe("test boosted", () => {
      before(
        "advance period to middle of week, make lock, attach lock",
        async () => {
          const lastTime = await pool.time();
          const oldPeriod = lastTime.div(WEEK);
          const newPeriod = oldPeriod.add(1);
          const delta = newPeriod
            .mul(WEEK)
            .sub(lastTime)
            .add(WEEK / 2);

          await pool.advanceTime(delta);

          // get some shadow and lock it
          await setERC20Balance(
            c.shadow.address,
            wallet.address,
            expandTo18Decimals(1000),
          );

          await c.shadow.approve(c.votingEscrow.address, MAX_UINT);
          veNftTokenId = await c.votingEscrow.callStatic.createLock(
            expandTo18Decimals(1000),
            86400 * 365 * 4,
          );
          await c.votingEscrow.createLock(
            expandTo18Decimals(1000),
            86400 * 365 * 4,
          );

          // make some swaps to write to pool
          for (const swap of writingSwaps) {
            await executeSwap(pool, swap, poolFunctions);
          }

          // attach the veRA to NFPs
          for (const nfp of nfps) {
            await c.nfpManager.switchAttachment(nfp.tokenId, veNftTokenId);
          }

          // notify rewards for the new week
          await setUpRewards();
        },
      );

      for (const testCase of poolCase.swapTests!) {
        it(swapCaseToDescription(testCase), async () => {
          // advance time before trade if defined
          if (testCase.advanceTime ?? 0 > 0) {
            await pool.advanceTime(testCase.advanceTime!);
          }

          await executeSwap(pool, testCase, poolFunctions);

          const period = (await pool.time()).div(WEEK);
          console.log(period);

          const [liquidity, boostedLiquidity, attachedVeNftId] =
            await gauge.positionInfo(1);

          expect(attachedVeNftId, "gauge reporting the wrong veNftTokenId").eq(
            veNftTokenId,
          );

          const _positionHash = positionHash(
            c.nfpManager.address,
            1,
            poolCase.positions[0].tickLower,
            poolCase.positions[0].tickUpper,
          );

          const boostInfo = await pool["boostInfos(uint256,bytes32)"](
            period,
            _positionHash,
          );

          expect(boostInfo.boostAmount).to.eq(
            BigNumber.from(poolCase.positions[0].liquidity).mul(3).div(2),
            "there should be full boost of 1.5x",
          );

          // console.log("boostInfo", boostInfo.boostAmount);
          // console.log("period", period);

          expect(liquidity).to.be.eq(poolCase.positions[0].liquidity);
          expect(boostedLiquidity).to.be.eq(boostInfo.boostAmount);
          // console.log(liquidity);
          // console.log(boostedLiquidity);

          await compareSnapshot(period);
        });
      }
    });

    describe("test boosted after a week", () => {
      before("advance period to start of week", async () => {
        const lastTime = await pool.time();
        const oldPeriod = lastTime.div(WEEK);
        const newPeriod = oldPeriod.add(1);
        const delta = newPeriod.mul(WEEK).sub(lastTime);

        await pool.advanceTime(delta);

        // make some swaps to write to pool
        for (const swap of writingSwaps) {
          await executeSwap(pool, swap, poolFunctions);
        }
      });

      it("earned should increase since boosted in range was only half a week", async () => {
        const period = (await pool.time()).div(WEEK).sub(1);
        await compareSnapshot(period);
      });
    });

    describe("get rewards", () => {
      it("getting rewards for tokenId NFPs", async () => {
        const rewards = [];
        for (const nfp of nfps) {
          const earned = await gauge.earned(token0.address, nfp.tokenId);

          const balanceBefore = await token0.balanceOf(wallet.address);

          await gauge["getReward(uint256,address[])"](nfp.tokenId, [
            token0.address,
          ]);

          const balanceAfter = await token0.balanceOf(wallet.address);

          const _rewards = balanceAfter.sub(balanceBefore);

          expect(_rewards).eq(earned, "earned and rewards mismatch");

          rewards.push({
            tokenId: nfp.tokenId.toString(),
            rewards: ethers.utils.formatEther(_rewards),
          });

          const earnedAfter = await gauge.earned(token0.address, nfp.tokenId);

          expect(earnedAfter).eq(0, "earned should be 0 after claiming");

          const period = (await pool.time()).div(WEEK).sub(1);

          expect(
            await gauge["periodEarned(uint256,address,uint256)"](
              period,
              token0.address,
              nfp.tokenId,
            ),
          ).eq(0, "period earned should be 0 after claiming");

          await gauge["getReward(uint256,address[])"](nfp.tokenId, [
            token0.address,
          ]);

          expect(await token0.balanceOf(wallet.address)).eq(
            balanceAfter,
            "rewards shouldn't increase",
          );
        }
        expect(rewards).to.matchSnapshot("rewards mismatch");
      });
    });
  });
});
