import { Decimal } from "decimal.js";
import { BigNumber, BigNumberish, ContractTransaction, Wallet } from "ethers";
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
import { MAX_UINT } from "../../../utils/constants";

Decimal.config({ toExpNeg: -500, toExpPos: 500 });

const { constants } = ethers;

const WEEK = 86400 * 7;

const Q96 = BigNumber.from(2).pow(96);

interface BaseSwapTestCase {
    zeroForOne: boolean;
    sqrtPriceLimit?: BigNumber;
    advanceTime?: number;
}
interface SwapExact0For1TestCase extends BaseSwapTestCase {
    zeroForOne: true;
    exactOut: false;
    amount0: BigNumberish;
    sqrtPriceLimit?: BigNumber;
}
interface SwapExact1For0TestCase extends BaseSwapTestCase {
    zeroForOne: false;
    exactOut: false;
    amount1: BigNumberish;
    sqrtPriceLimit?: BigNumber;
}
interface Swap0ForExact1TestCase extends BaseSwapTestCase {
    zeroForOne: true;
    exactOut: true;
    amount1: BigNumberish;
    sqrtPriceLimit?: BigNumber;
}
interface Swap1ForExact0TestCase extends BaseSwapTestCase {
    zeroForOne: false;
    exactOut: true;
    amount0: BigNumberish;
    sqrtPriceLimit?: BigNumber;
}
interface SwapToHigherPrice extends BaseSwapTestCase {
    zeroForOne: false;
    sqrtPriceLimit: BigNumber;
    advanceTime?: number;
}
interface SwapToLowerPrice extends BaseSwapTestCase {
    zeroForOne: true;
    sqrtPriceLimit: BigNumber;
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
const SWAP_RECIPIENT_ADDRESS = constants.AddressZero.slice(0, -1) + "1";
const POSITION_PROCEEDS_OUTPUT_ADDRESS =
    constants.AddressZero.slice(0, -1) + "2";

async function executeSwap(
    pool: MockTimeClPool,
    testCase: SwapTestCase,
    poolFunctions: PoolFunctions
): Promise<ContractTransaction> {
    let swap: ContractTransaction;
    if ("exactOut" in testCase) {
        if (testCase.exactOut) {
            if (testCase.zeroForOne) {
                swap = await poolFunctions.swap0ForExact1(
                    testCase.amount1,
                    SWAP_RECIPIENT_ADDRESS,
                    testCase.sqrtPriceLimit
                );
            } else {
                swap = await poolFunctions.swap1ForExact0(
                    testCase.amount0,
                    SWAP_RECIPIENT_ADDRESS,
                    testCase.sqrtPriceLimit
                );
            }
        } else {
            if (testCase.zeroForOne) {
                swap = await poolFunctions.swapExact0For1(
                    testCase.amount0,
                    SWAP_RECIPIENT_ADDRESS,
                    testCase.sqrtPriceLimit
                );
            } else {
                swap = await poolFunctions.swapExact1For0(
                    testCase.amount1,
                    SWAP_RECIPIENT_ADDRESS,
                    testCase.sqrtPriceLimit
                );
            }
        }
    } else {
        if (testCase.zeroForOne) {
            swap = await poolFunctions.swapToLowerPrice(
                testCase.sqrtPriceLimit,
                SWAP_RECIPIENT_ADDRESS
            );
        } else {
            swap = await poolFunctions.swapToHigherPrice(
                testCase.sqrtPriceLimit,
                SWAP_RECIPIENT_ADDRESS
            );
        }
    }
    return swap;
}

interface Position {
    tickLower: number;
    tickUpper: number;
    liquidity: BigNumberish;
}

interface PoolTestCase {
    description: string;
    feeAmount: number;
    tickSpacing: number;
    startingPrice: BigNumber;
    positions: Position[];
    swapTests?: SwapTestCase[];
}

const TEST_POOLS: PoolTestCase[] = [
    {
        description: "low fee, 1:1 price, 2e18 max range liquidity",
        feeAmount: FeeAmount.LOW,
        tickSpacing: TICK_SPACINGS[FeeAmount.LOW],
        startingPrice: encodePriceSqrt(1, 1),
        positions: [
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.LOW]),
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.LOW]),
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
    {
        description:
            "medium fee, 1:1 price, additional liquidity around current price",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(1, 1),
        positions: [
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                liquidity: expandTo18Decimals(2),
            },
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                tickUpper: -TICK_SPACINGS[FeeAmount.MEDIUM],
                liquidity: expandTo18Decimals(2),
            },
            {
                tickLower: TICK_SPACINGS[FeeAmount.MEDIUM],
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
    {
        description: "medium fee, token0 liquidity only",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(1, 1),
        positions: [
            {
                tickLower: 0,
                tickUpper: 2000 * TICK_SPACINGS[FeeAmount.MEDIUM],
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
    {
        description: "medium fee, token1 liquidity only",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(1, 1),
        positions: [
            {
                tickLower: -2000 * TICK_SPACINGS[FeeAmount.MEDIUM],
                tickUpper: 0,
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
    {
        description: "close to max price",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(BigNumber.from(2).pow(127), 1),
        positions: [
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
    {
        description: "close to min price",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(1, BigNumber.from(2).pow(127)),
        positions: [
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                liquidity: expandTo18Decimals(2),
            },
        ],
    },
];

describe("ClPool Seconds in Range Tests", () => {
    let wallet: Wallet, other: Wallet;

    before("create fixture loader", async () => {
        [wallet, other] = await (ethers as any).getSigners();
    });

    const poolCase: PoolTestCase = {
        description:
            "medium fee, 1:1 price, additional liquidity around current price",
        feeAmount: FeeAmount.MEDIUM,
        tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
        startingPrice: encodePriceSqrt(1, 1),
        positions: [
            {
                tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                liquidity: expandTo18Decimals(2),
            },
            // {
            //     tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
            //     tickUpper: -TICK_SPACINGS[FeeAmount.MEDIUM],
            //     liquidity: expandTo18Decimals(2),
            // },
            // {
            //     tickLower: TICK_SPACINGS[FeeAmount.MEDIUM],
            //     tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
            //     liquidity: expandTo18Decimals(2),
            // },
        ],
        swapTests: [
            // swap arbitrary input to price
            {
                sqrtPriceLimit: encodePriceSqrt(5, 2),
                zeroForOne: false,
            },
            {
                sqrtPriceLimit: encodePriceSqrt(2, 5),
                zeroForOne: true,
                advanceTime: WEEK,
            },
            // {
            //     sqrtPriceLimit: encodePriceSqrt(5, 2),
            //     zeroForOne: false,
            // },
            // {
            //     sqrtPriceLimit: encodePriceSqrt(2, 5),
            //     zeroForOne: true,
            // },
        ],
    };

    const writingSwaps: SwapTestCase[] = [
        {
            zeroForOne: true,
            exactOut: false,
            amount0: expandTo18Decimals(1),
        },
        {
            zeroForOne: false,
            exactOut: false,
            amount1: expandTo18Decimals(1),
        },
    ];

    describe(poolCase.description, () => {
        async function poolCaseFixture() {
            const {
                createPool,
                createNormalPool,
                createGauge,
                token0,
                token1,
                swapTargetCallee: swapTarget,
                c,
            } = await loadFixture(poolFixture);
            const pool = await createNormalPool(
                poolCase.feeAmount,
                poolCase.startingPrice
            );
            const { gauge, feeDistributor } = await createGauge(pool.address);
            const poolFunctions = createPoolFunctions({
                swapTarget,
                token0,
                token1,
                pool,
            });
            await pool.initializeTime();
            // mint all positions
            for (const position of poolCase.positions) {
                console.log("mint time", await pool.time());
                await poolFunctions.mint(
                    wallet.address,
                    position.tickLower,
                    position.tickUpper,
                    position.liquidity
                );
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
        });

        for (const testCase of poolCase.swapTests!) {
            it(swapCaseToDescription(testCase), async () => {
                // advance time before trade if defined
                if (testCase.advanceTime ?? 0 > 0) {
                    await pool.advanceTime(testCase.advanceTime!);
                }
                console.log("pool time", await pool.time());
                console.log("before swap:", await pool.observe([0]));

                const slot0 = await pool.slot0();
                const tx = await executeSwap(pool, testCase, poolFunctions);

                console.log("pool time", await pool.time());
                console.log("after swap:", await pool.observe([0]));

                const period = (await pool.time()).div(WEEK);
                const results = [];
                for (const position of poolCase.positions) {
                    const [secondsPerLiquidity, secondsPerBoostedLiquidity] =
                        await pool.periodCumulativesInside(
                            period,
                            position.tickLower,
                            position.tickUpper
                        );
                    const [secondsInRange, boostedSecondsInRange] =
                        await pool.positionPeriodSecondsInRange(
                            period,
                            wallet.address,
                            0,
                            position.tickLower,
                            position.tickUpper
                        );
                    const _results = {
                        tickLower: position.tickLower.toString(),
                        tickUpper: position.tickUpper.toString(),
                        secondsPerLiquidity: secondsPerLiquidity
                            .mul(position.liquidity)
                            .div(BigNumber.from(2).pow(128))
                            .toString(),
                        secondsPerBoostedLiquidity: secondsPerBoostedLiquidity
                            .mul(1)
                            .div(BigNumber.from(2).pow(128))
                            .toString(),
                        secondsInRange: BigNumber.from(secondsInRange)
                            .div(Q96)
                            .toString(),
                        boostedSecondsInRange: BigNumber.from(
                            boostedSecondsInRange
                        )
                            .div(Q96)
                            .toString(),
                    };
                    results.push(_results);
                }

                expect(results).to.matchSnapshot("Position seconds inside");
            });
        }

        it("secondsInRange results", async () => {
            const period = (await pool.time()).div(WEEK);

            const results = [];

            for (const position of poolCase.positions) {
                const [secondsPerLiquidity, secondsPerBoostedLiquidity] =
                    await pool.periodCumulativesInside(
                        period,
                        position.tickLower,
                        position.tickUpper
                    );
                const [
                    lastSecondsPerLiquidity,
                    lastSecondsPerBoostedLiquidity,
                ] = await pool.periodCumulativesInside(
                    period.sub(1),
                    position.tickLower,
                    position.tickUpper
                );

                const [secondsInRange, boostedSecondsInRange] =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );
                const [lastSecondsInRange, lastBoostedSecondsInRange] =
                    await pool.positionPeriodSecondsInRange(
                        period.sub(1),
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );
                const _results = {
                    tickLower: position.tickLower.toString(),
                    tickUpper: position.tickUpper.toString(),
                    secondsPerLiquidity: secondsPerLiquidity
                        .mul(position.liquidity)
                        .div(BigNumber.from(2).pow(128))
                        .toString(),
                    secondsPerBoostedLiquidity: secondsPerBoostedLiquidity
                        .mul(1)
                        .div(BigNumber.from(2).pow(128))
                        .toString(),
                    lastSecondsPerLiquidity: lastSecondsPerLiquidity
                        .mul(position.liquidity)
                        .div(BigNumber.from(2).pow(128))
                        .toString(),
                    lastSecondsPerBoostedLiquidity:
                        lastSecondsPerBoostedLiquidity
                            .mul(1)
                            .div(BigNumber.from(2).pow(128))
                            .toString(),
                    secondsInRange: BigNumber.from(secondsInRange)
                        .div(Q96)
                        .toString(),
                    boostedSecondsInRange: BigNumber.from(boostedSecondsInRange)
                        .div(Q96)
                        .toString(),
                    lastSecondsInRange: BigNumber.from(lastSecondsInRange)
                        .div(Q96)
                        .toString(),
                    lastBoostedSecondsInRange: BigNumber.from(
                        lastBoostedSecondsInRange
                    )
                        .div(Q96)
                        .toString(),
                };
                results.push(_results);
            }
            expect(results).to.matchSnapshot("Position seconds inside");
        });

        it("deposit some LP, should have seconds debt", async () => {
            const period = (await pool.time()).div(WEEK);

            const results = [];
            for (const position of poolCase.positions) {
                console.log("mint period", period);
                await poolFunctions.mint(
                    wallet.address,
                    position.tickLower,
                    position.tickUpper,
                    position.liquidity
                );

                const [secondsDebt, boostedSecondsDebt] =
                    await pool.positionPeriodDebt(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                const [secondsInRange, boostedSecondsInRange] =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                const _results = {
                    tickLower: position.tickLower.toString(),
                    tickUpper: position.tickUpper.toString(),
                    secondsDebt: secondsDebt.div(Q96).toString(),
                    boostedSecondsDebt: boostedSecondsDebt.div(Q96).toString(),
                    secondsInRange: BigNumber.from(secondsInRange)
                        .div(Q96)
                        .toString(),
                    boostedSecondsInRange: BigNumber.from(boostedSecondsInRange)
                        .div(Q96)
                        .toString(),
                };
                results.push(_results);
            }

            expect(results).to.matchSnapshot("Seconds debt");
        });

        it("remove some LP, should have less seconds debt", async () => {
            const period = (await pool.time()).div(WEEK);

            const results = [];
            for (const position of poolCase.positions) {
                console.log("burn period", period);
                await pool["burn(int24,int24,uint128)"](
                    position.tickLower,
                    position.tickUpper,
                    position.liquidity
                );

                const [secondsDebt, boostedSecondsDebt] =
                    await pool.positionPeriodDebt(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                const [secondsInRange, boostedSecondsInRange] =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                const _results = {
                    tickLower: position.tickLower.toString(),
                    tickUpper: position.tickUpper.toString(),
                    secondsDebt: secondsDebt.div(Q96).toString(),
                    boostedSecondsDebt: boostedSecondsDebt.div(Q96).toString(),
                    secondsInRange: BigNumber.from(secondsInRange)
                        .div(Q96)
                        .toString(),
                    boostedSecondsInRange: BigNumber.from(boostedSecondsInRange)
                        .div(Q96)
                        .toString(),
                };
                results.push(_results);
            }

            expect(results).to.matchSnapshot("Reduce seconds debt");
        });

        it("attach votingEscrow, veNftAttached should change, boosted seconds shouldn't change immediately", async () => {
            // get some shadow and lock it
            await setERC20Balance(
                c.shadow.address,
                wallet.address,
                expandTo18Decimals(1000)
            );

            await c.shadow.approve(c.votingEscrow.address, MAX_UINT);
            veNftTokenId = await c.votingEscrow.callStatic.createLock(
                expandTo18Decimals(1000),
                86400 * 365 * 4
            );
            await c.votingEscrow.createLock(
                expandTo18Decimals(1000),
                86400 * 365 * 4
            );
            const position = poolCase.positions[0];
            const period = (await pool.time()).div(WEEK);

            const _positionHash = positionHash(
                wallet.address,
                0,
                position.tickLower,
                position.tickUpper
            );

            const positionPeriodSecondsInRangeBefore =
                await pool.positionPeriodSecondsInRange(
                    period,
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

            const positionInfoBefore = await pool.positions(_positionHash);

            const boostInfoBefore = await pool["boostInfos(uint256,bytes32)"](
                period,
                _positionHash
            );

            expect(positionInfoBefore.attachedVeNftId).to.eq(
                0,
                "nothing should be no attached yet"
            );

            expect(boostInfoBefore.boostAmount).to.eq(
                0,
                "there should be no boost yet"
            );
            expect(boostInfoBefore.boostedSecondsDebtX96).to.eq(
                0,
                "there should be no boost debt yet"
            );
            expect(boostInfoBefore.veNftAmount).to.eq(
                0,
                "there should be no veNftAmount yet"
            );

            await pool["burn(uint256,int24,int24,uint128,uint256)"](
                0,
                position.tickLower,
                position.tickUpper,
                0,
                veNftTokenId
            );

            positionInfo = await pool.positions(_positionHash);

            expect(positionInfo.attachedVeNftId).to.eq(
                veNftTokenId,
                "attachedVeNftId should change"
            );

            Object.keys(positionInfo).forEach((key) => {
                if (
                    typeof key == "string" &&
                    key != "attachedVeNftId" &&
                    key != "5"
                ) {
                    // @ts-ignore key is implicitly any type
                    expect(positionInfo[key]).to.eq(
                        // @ts-ignore key os implicitly any type
                        positionInfoBefore[key],
                        `position info ${key} should remain the same`
                    );
                }
            });

            boostInfo = await pool["boostInfos(uint256,bytes32)"](
                period,
                _positionHash
            );

            expect(boostInfo.boostAmount).to.eq(
                positionInfo.liquidity.mul(3).div(2),
                "there should be full boost of 1.5x"
            );

            expect(boostInfo.veNftAmount).gt(0, "there should be veNftAmount");

            // Boosted seconds debt should be 0 because the position is not boosted before
            expect(boostInfo.boostedSecondsDebtX96).to.eq(0);

            expect(boostInfo.secondsDebtX96).to.eq(
                boostInfoBefore.secondsDebtX96,
                "seconds debt shouldn't change"
            );

            positionPeriodSecondsInRange =
                await pool.positionPeriodSecondsInRange(
                    period,
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

            expect(
                positionPeriodSecondsInRange.periodBoostedSecondsInsideX96
            ).to.eq(
                0,
                "periodBoostedSecondsInside should remain 0 until more time passes"
            );
            expect(positionPeriodSecondsInRange.periodSecondsInsideX96).to.eq(
                positionPeriodSecondsInRangeBefore.periodSecondsInsideX96,
                "periodSecondsInside shouldn't change"
            );

            const boostedLiquidity = await pool.boostedLiquidity();
            expect(boostedLiquidity).to.eq(
                boostInfo.boostAmount,
                "boostedLiquidity should increase"
            );
        });

        it("increase time by an hour, boosted seconds should increase by an hour", async () => {
            const position = poolCase.positions[0];
            const period = (await pool.time()).div(WEEK);

            const _positionHash = positionHash(
                wallet.address,
                0,
                position.tickLower,
                position.tickUpper
            );

            // record before states
            const positionPeriodSecondsInRangeBefore =
                positionPeriodSecondsInRange;

            const positionInfoBefore = positionInfo;

            const boostInfoBefore = boostInfo;

            await pool.advanceTime(3600);

            positionInfo = await pool.positions(_positionHash);

            Object.keys(positionInfo).forEach((key) => {
                // @ts-ignore key is implicitly any type
                expect(positionInfo[key]).to.eq(
                    // @ts-ignore key os implicitly any type
                    positionInfoBefore[key],
                    `position info ${key} should remain the same`
                );
            });

            boostInfo = await pool["boostInfos(uint256,bytes32)"](
                period,
                _positionHash
            );

            Object.keys(boostInfo).forEach((key) => {
                // @ts-ignore key is implicitly any type
                expect(boostInfo[key]).to.eq(
                    // @ts-ignore key os implicitly any type
                    boostInfoBefore[key],
                    `boost info ${key} should remain the same`
                );
            });

            positionPeriodSecondsInRange =
                await pool.positionPeriodSecondsInRange(
                    period,
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

            expect(
                positionPeriodSecondsInRange.periodBoostedSecondsInsideX96.div(
                    Q96
                )
            ).to.approximately(
                3600,
                1,
                "periodBoostedSecondsInside should be 3600"
            );
            expect(
                positionPeriodSecondsInRange.periodSecondsInsideX96.div(Q96)
            ).to.approximately(
                positionPeriodSecondsInRangeBefore.periodSecondsInsideX96
                    .div(Q96)
                    .add(3600),
                1,
                "periodSecondsInside should increase by 3600"
            );
        });

        it("increase time to the next period plus 1 day without advancing period, boosted seconds should increase until the end of period", async () => {
            const position = poolCase.positions[0];
            const period = (await pool.time()).div(WEEK);
            const poolTimeBefore = await pool.time();
            const poolTimeUntilNextPeriod = period
                .add(1)
                .mul(WEEK)
                .sub(poolTimeBefore);
            const timeToAdvance = poolTimeUntilNextPeriod.add(86400);

            const _positionHash = positionHash(
                wallet.address,
                0,
                position.tickLower,
                position.tickUpper
            );

            // record before states
            const positionPeriodSecondsInRangeBefore =
                positionPeriodSecondsInRange;

            const positionInfoBefore = positionInfo;

            const boostInfoBefore = boostInfo;

            await pool.advanceTime(timeToAdvance);

            positionInfo = await pool.positions(_positionHash);

            Object.keys(positionInfo).forEach((key) => {
                // @ts-ignore key is implicitly any type
                expect(positionInfo[key]).to.eq(
                    // @ts-ignore key os implicitly any type
                    positionInfoBefore[key],
                    `position info ${key} should remain the same`
                );
            });

            boostInfo = await pool["boostInfos(uint256,bytes32)"](
                period,
                _positionHash
            );

            Object.keys(boostInfo).forEach((key) => {
                // @ts-ignore key is implicitly any type
                expect(boostInfo[key]).to.eq(
                    // @ts-ignore key os implicitly any type
                    boostInfoBefore[key],
                    `boost info ${key} should remain the same before an action advances period`
                );
            });

            positionPeriodSecondsInRange =
                await pool.positionPeriodSecondsInRange(
                    period,
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

            expect(
                positionPeriodSecondsInRange.periodBoostedSecondsInsideX96.div(
                    Q96
                )
            ).to.approximately(
                poolTimeUntilNextPeriod.add(
                    positionPeriodSecondsInRangeBefore.periodBoostedSecondsInsideX96.div(
                        Q96
                    )
                ),
                1,
                "periodBoostedSecondsInside should increase until the end of period"
            );
            expect(
                positionPeriodSecondsInRange.periodSecondsInsideX96.div(Q96)
            ).to.approximately(
                poolTimeUntilNextPeriod.add(
                    positionPeriodSecondsInRangeBefore.periodSecondsInsideX96.div(
                        Q96
                    )
                ),
                1,
                "periodSecondsInside should increase until the end of period"
            );
        });

        // time = period + 1 days
        describe("advance period, boosted seconds should be 0 until attachment is renewed", () => {
            let position: Position;
            let period: BigNumber;
            let _positionHash: string;

            let positionPeriodSecondsInRangeBefore: typeof positionPeriodSecondsInRange;
            let positionInfoBefore: typeof positionInfo;
            let boostInfoBefore: typeof boostInfo;

            before(async () => {
                position = poolCase.positions[0];
                period = (await pool.time()).div(WEEK);
                _positionHash = positionHash(
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

                // record before states
                positionPeriodSecondsInRangeBefore =
                    positionPeriodSecondsInRange;

                positionInfoBefore = positionInfo;

                boostInfoBefore = boostInfo;

                // make some swaps to advance period
                for (const swap of poolCase.swapTests!) {
                    await executeSwap(pool, swap, poolFunctions);
                }
            });

            it("positionInfo", async () => {
                positionInfo = await pool.positions(_positionHash);

                Object.keys(positionInfo).forEach((key) => {
                    // @ts-ignore key is implicitly any type
                    expect(positionInfo[key]).to.eq(
                        // @ts-ignore key os implicitly any type
                        positionInfoBefore[key],
                        `position info ${key} should remain the same`
                    );
                });
            });

            it("boostInfo", async () => {
                boostInfo = await pool["boostInfos(uint256,bytes32)"](
                    period,
                    _positionHash
                );

                Object.keys(boostInfo).forEach((key) => {
                    // @ts-ignore key is implicitly any type
                    expect(boostInfo[key]).to.eq(
                        0,
                        `boost info ${key} should be 0 until the attachment is renewed`
                    );
                });
            });

            it("positionPeriodSecondsInRange", async () => {
                positionPeriodSecondsInRange =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );
            });

            it("periodSecondsInside", async () => {
                expect(
                    positionPeriodSecondsInRange.periodSecondsInsideX96.div(Q96)
                ).to.approximately(
                    86400,
                    1,
                    "periodSecondsInside should increase even if attachment isn't renewed"
                );
            });

            it("periodBoostedSecondsInside", async () => {
                expect(
                    positionPeriodSecondsInRange.periodBoostedSecondsInsideX96
                ).to.eq(
                    0,
                    "periodBoostedSecondsInside should be 0 before renewing attachment"
                );
            });
        });

        // time = period + 1 days
        describe("renew attachment, boosted seconds should be 0 until more time has passed", () => {
            let position: Position;
            let period: BigNumber;
            let _positionHash: string;

            let positionPeriodSecondsInRangeBefore: typeof positionPeriodSecondsInRange;
            let positionInfoBefore: typeof positionInfo;
            let boostInfoBefore: typeof boostInfo;

            before(async () => {
                position = poolCase.positions[0];
                period = (await pool.time()).div(WEEK);
                _positionHash = positionHash(
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

                // record before states
                positionPeriodSecondsInRangeBefore =
                    positionPeriodSecondsInRange;

                positionInfoBefore = positionInfo;

                boostInfoBefore = boostInfo;

                await pool["burn(uint256,int24,int24,uint128,uint256)"](
                    0,
                    position.tickLower,
                    position.tickUpper,
                    0,
                    veNftTokenId
                );
            });

            it("positionInfo", async () => {
                positionInfo = await pool.positions(_positionHash);

                expect(positionInfo.feeGrowthInside0LastX128).to.gt(
                    positionInfoBefore.feeGrowthInside0LastX128,
                    "feeGrowth0 didn't change"
                );

                expect(positionInfo.feeGrowthInside1LastX128).to.gt(
                    positionInfoBefore.feeGrowthInside0LastX128,
                    "feeGrowth1 didn't change"
                );

                expect(positionInfo.tokensOwed0).to.gt(
                    positionInfoBefore.tokensOwed0,
                    "tokensOwed0 didn't change"
                );

                expect(positionInfo.tokensOwed1).to.gt(
                    positionInfoBefore.tokensOwed1,
                    "tokensOwed0 didn't change"
                );

                Object.keys(positionInfo).forEach((key) => {
                    const mutatedFields = [
                        "feeGrowthInside0LastX128",
                        "feeGrowthInside1LastX128",
                        "tokensOwed0",
                        "tokensOwed1",
                    ];
                    if (!mutatedFields.includes(key) && isNaN(Number(key))) {
                        // @ts-ignore key is implicitly any type
                        expect(positionInfo[key]).to.eq(
                            // @ts-ignore key os implicitly any type
                            positionInfoBefore[key],
                            `position info ${key} should remain the same`
                        );
                    }
                });
            });

            it("boostInfo", async () => {
                boostInfo = await pool["boostInfos(uint256,bytes32)"](
                    period,
                    _positionHash
                );

                expect(boostInfo.boostAmount).to.eq(
                    positionInfo.liquidity.mul(3).div(2),
                    "boost amount mismatch"
                );

                expect(boostInfo.veNftAmount).to.gt(
                    0,
                    "veNft amount didn't increase"
                );

                expect(boostInfo.boostedSecondsDebtX96).to.eq(
                    0,
                    "boostedSecondsDebtX96 mismatch"
                );

                // secondsDebtX96 should be near -86400 since 1 day has passed since epoch change
                expect(boostInfo.secondsDebtX96).to.gte(
                    BigNumber.from(-86400).mul(Q96),
                    "secondsDebtX96 should be near 86400"
                );

                expect(boostInfo.secondsDebtX96).to.lt(
                    BigNumber.from(-86399).mul(Q96),
                    "secondsDebtX96 should be near 86400"
                );

                Object.keys(boostInfo).forEach((key) => {
                    const mutatedFields = [
                        "boostAmount",
                        "veNftAmount",
                        "boostedSecondsDebtX96",
                        "secondsDebtX96",
                    ];
                    if (!mutatedFields.includes(key) && isNaN(Number(key))) {
                        // @ts-ignore key is implicitly any type
                        expect(boostInfo[key]).to.eq(
                            // @ts-ignore key is implicitly any type
                            boostInfoBefore[key],
                            `boost info ${key} should be the same until more time has passed`
                        );
                    }
                });
            });

            it("positionPeriodSecondsInRange", async () => {
                positionPeriodSecondsInRange =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );
            });

            it("periodSecondsInside", async () => {
                expect(
                    positionPeriodSecondsInRange.periodSecondsInsideX96.div(Q96)
                ).to.approximately(
                    86400,
                    1,
                    "periodSecondsInside should increase even if attachment isn't renewed"
                );
            });

            it("periodBoostedSecondsInside", async () => {
                expect(
                    positionPeriodSecondsInRange.periodBoostedSecondsInsideX96
                ).to.eq(
                    0,
                    "periodBoostedSecondsInside should be 0 before renewing attachment"
                );
            });
        });

        // time = period + 1 days
        describe("mint an out of range position and attach, seconds and boosted seconds should be 0", () => {
            let position: Position;
            let period: BigNumber;
            let _positionHash: string;

            let positionPeriodSecondsInRangeBefore: typeof positionPeriodSecondsInRange;
            let positionInfoBefore: typeof positionInfo;
            let boostInfoBefore: typeof boostInfo;

            before(async () => {
                position = {
                    tickLower:
                        getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]) -
                        TICK_SPACINGS[FeeAmount.MEDIUM],
                    tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                    liquidity: expandTo18Decimals(2),
                };
                period = (await pool.time()).div(WEEK);
                _positionHash = positionHash(
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

                // record before states
                positionPeriodSecondsInRangeBefore =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                positionInfoBefore = await pool.positions(_positionHash);

                boostInfoBefore = await pool["boostInfos(uint256,bytes32)"](
                    period,
                    _positionHash
                );

                // mint
                await poolFunctions.mint(
                    wallet.address,
                    position.tickLower,
                    position.tickUpper,
                    position.liquidity
                );

                // attach veNft
                await pool["burn(uint256,int24,int24,uint128,uint256)"](
                    0,
                    position.tickLower,
                    position.tickUpper,
                    0,
                    veNftTokenId
                );
            });

            describe("positionInfo", () => {
                before("positionInfo", async () => {
                    positionInfo = await pool.positions(_positionHash);
                });

                it("liquidity", async () => {
                    expect(positionInfo.liquidity).to.eq(
                        position.liquidity,
                        "liquidity mismatch"
                    );
                });

                it("attachedVeNftId", async () => {
                    expect(positionInfo.attachedVeNftId).to.eq(
                        veNftTokenId,
                        "attachement mismatch"
                    );
                });

                it("unchanged", async () => {
                    Object.keys(positionInfo).forEach((key) => {
                        const mutatedFields = ["liquidity", "attachedVeNftId"];
                        if (
                            !mutatedFields.includes(key) &&
                            isNaN(Number(key))
                        ) {
                            // @ts-ignore key is implicitly any type
                            expect(positionInfo[key]).to.eq(
                                // @ts-ignore key os implicitly any type
                                positionInfoBefore[key],
                                `position info ${key} should remain the same`
                            );
                        }
                    });
                });
            });

            describe("boostInfo", () => {
                before(async () => {
                    boostInfo = await pool["boostInfos(uint256,bytes32)"](
                        period,
                        _positionHash
                    );
                });

                it("boostAmount", async () => {
                    // expect(boostInfo.boostAmount).to.eq(
                    //     positionInfo.liquidity.mul(3).div(2),
                    //     "boost amount mismatch"
                    // );

                    // boost amount now capped
                    expect(boostInfo.boostAmount.toString()).to.matchSnapshot(
                        "boost amount mismatch"
                    );
                });

                it("veNftAmount", async () => {
                    expect(boostInfo.veNftAmount).to.gt(
                        0,
                        "veNft should be attached"
                    );
                });

                it("secondsDebtX96", async () => {
                    expect(boostInfo.secondsDebtX96).to.eq(
                        0,
                        "there shouldn't be debt for fresh positions since it's activated with the correct seconds per liq"
                    );
                });

                it("boostedSecondsDebtX96", async () => {
                    expect(boostInfo.boostedSecondsDebtX96).to.eq(
                        0,
                        "there shouldn't be debt for fresh positions since it's activated with the correct seconds per liq"
                    );
                });
            });

            describe("positionPeriodSecondsInRange", () => {
                before(async () => {
                    positionPeriodSecondsInRange =
                        await pool.positionPeriodSecondsInRange(
                            period,
                            wallet.address,
                            0,
                            position.tickLower,
                            position.tickUpper
                        );
                });

                it("periodSecondsInside", async () => {
                    expect(
                        positionPeriodSecondsInRange.periodSecondsInsideX96
                    ).to.eq(0, "periodSecondsInside should be 0");
                });

                it("periodBoostedSecondsInside", async () => {
                    expect(
                        positionPeriodSecondsInRange.periodBoostedSecondsInsideX96
                    ).to.eq(0, "periodBoostedSecondsInside should be 0");
                });
            });
        });

        // time = period + 1 days
        describe("advance time, seconds and boosted seconds should be 0 for out of range position", () => {
            let position: Position;
            let period: BigNumber;
            let _positionHash: string;

            let positionPeriodSecondsInRangeBefore: typeof positionPeriodSecondsInRange;
            let positionInfoBefore: typeof positionInfo;
            let boostInfoBefore: typeof boostInfo;

            before(async () => {
                position = {
                    tickLower:
                        getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]) -
                        TICK_SPACINGS[FeeAmount.MEDIUM],
                    tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
                    liquidity: expandTo18Decimals(2),
                };
                period = (await pool.time()).div(WEEK);
                _positionHash = positionHash(
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

                // record before states
                positionPeriodSecondsInRangeBefore =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                positionInfoBefore = await pool.positions(_positionHash);

                boostInfoBefore = await pool["boostInfos(uint256,bytes32)"](
                    period,
                    _positionHash
                );

                await pool.advanceTime(86400);
            });

            describe("positionInfo", () => {
                before("positionInfo", async () => {
                    positionInfo = await pool.positions(_positionHash);
                });

                it("unchanged", async () => {
                    Object.keys(positionInfo).forEach((key) => {
                        if (isNaN(Number(key))) {
                            // @ts-ignore key is implicitly any type
                            expect(positionInfo[key]).to.eq(
                                // @ts-ignore key os implicitly any type
                                positionInfoBefore[key],
                                `position info ${key} should remain the same`
                            );
                        }
                    });
                });
            });

            describe("boostInfo", () => {
                before(async () => {
                    boostInfo = await pool["boostInfos(uint256,bytes32)"](
                        period,
                        _positionHash
                    );
                });

                it("unchanged", async () => {
                    Object.keys(boostInfo).forEach((key) => {
                        if (isNaN(Number(key))) {
                            // @ts-ignore key is implicitly any type
                            expect(boostInfo[key]).to.eq(
                                // @ts-ignore key os implicitly any type
                                boostInfoBefore[key],
                                `boost info ${key} should remain the same`
                            );
                        }
                    });
                });
            });

            describe("positionPeriodSecondsInRange", () => {
                before(async () => {
                    positionPeriodSecondsInRange =
                        await pool.positionPeriodSecondsInRange(
                            period,
                            wallet.address,
                            0,
                            position.tickLower,
                            position.tickUpper
                        );
                });

                it("periodSecondsInside", async () => {
                    expect(
                        positionPeriodSecondsInRange.periodSecondsInsideX96
                    ).to.eq(0, "periodSecondsInside should be 0");
                });

                it("periodBoostedSecondsInside", async () => {
                    expect(
                        positionPeriodSecondsInRange.periodBoostedSecondsInsideX96
                    ).to.eq(0, "periodBoostedSecondsInside should be 0");
                });
            });
        });

        // time = period + 2 days
        describe("burnt position shouldn't accrue seconds in range", () => {
            let position: Position;
            let period: BigNumber;
            let _positionHash: string;

            let positionPeriodSecondsInRangeBefore: typeof positionPeriodSecondsInRange;
            let positionInfoBefore: typeof positionInfo;
            let boostInfoBefore: typeof boostInfo;

            let burnTime: BigNumber;

            before("burn positions", async () => {
                position = poolCase.positions[0];
                period = (await pool.time()).div(WEEK);
                _positionHash = positionHash(
                    wallet.address,
                    0,
                    position.tickLower,
                    position.tickUpper
                );

                // record before states
                positionPeriodSecondsInRangeBefore =
                    await pool.positionPeriodSecondsInRange(
                        period,
                        wallet.address,
                        0,
                        position.tickLower,
                        position.tickUpper
                    );

                positionInfoBefore = await pool.positions(_positionHash);

                boostInfoBefore = await pool["boostInfos(uint256,bytes32)"](
                    period,
                    _positionHash
                );

                burnTime = await pool.time();

                await pool["burn(int24,int24,uint128)"](
                    position.tickLower,
                    position.tickUpper,
                    position.liquidity
                );

                await pool.advanceTime(86400);

                // make some swaps to write oracle
                for (const swap of writingSwaps) {
                    await executeSwap(pool, swap, poolFunctions);
                    // console.log(
                    //     "slot0 after burn and swap",
                    //     await pool.slot0()
                    // );
                    // console.log("liq", await pool.liquidity());
                    // console.log("boosted liq", await pool.boostedLiquidity());
                }
            });

            describe("positionInfo", () => {
                before("positionInfo", async () => {
                    positionInfo = await pool.positions(_positionHash);
                });

                it("liquidity", async () => {
                    expect(positionInfo.liquidity).to.eq(
                        0,
                        "liquidity mismatch"
                    );
                });

                it("attachedVeNftId", async () => {
                    expect(positionInfo.attachedVeNftId).to.eq(
                        0,
                        "attachement mismatch"
                    );
                });
            });

            describe("boostInfo", () => {
                before(async () => {
                    boostInfo = await pool["boostInfos(uint256,bytes32)"](
                        period,
                        _positionHash
                    );
                });

                it("boostAmount", async () => {
                    expect(boostInfo.boostAmount).to.eq(
                        0,
                        "boost amount mismatch"
                    );
                });

                it("veNftAmount", async () => {
                    expect(boostInfo.veNftAmount).to.eq(
                        0,
                        "veNft amount mismatch"
                    );
                });

                it("secondsDebtX96", async () => {
                    expect(boostInfo.secondsDebtX96.div(Q96)).to.approximately(
                        burnTime.sub(period.mul(WEEK)).mul(-1),
                        1,
                        "secondsDebtX96 should decrease because of the withdrawal"
                    );
                });

                it("boostedSecondsDebtX96", async () => {
                    expect(
                        boostInfo.boostedSecondsDebtX96.div(Q96)
                    ).to.approximately(
                        burnTime.sub(period.mul(WEEK)).sub(86400).mul(-1),
                        1,
                        "boostedSecondsDebtX96 should decrease because of the withdrawal"
                    );
                });
            });

            describe("positionPeriodSecondsInRange", () => {
                before(async () => {
                    positionPeriodSecondsInRange =
                        await pool.positionPeriodSecondsInRange(
                            period,
                            wallet.address,
                            0,
                            position.tickLower,
                            position.tickUpper
                        );
                });

                it("periodSecondsInside", async () => {
                    expect(
                        positionPeriodSecondsInRange.periodSecondsInsideX96.div(
                            Q96
                        )
                    ).to.approximately(
                        burnTime.sub(period.mul(WEEK)),
                        1,
                        "periodBoostedSecondsInside should be equal to how long it's been in the pool (It is the 3rd day since period change, but the position is only in range for 2 days)"
                    );
                });

                it("periodBoostedSecondsInside", async () => {
                    console.log(positionPeriodSecondsInRange);
                    expect(
                        positionPeriodSecondsInRange.periodBoostedSecondsInsideX96.div(
                            Q96
                        )
                    ).to.approximately(
                        burnTime.sub(period.mul(WEEK)).sub(86400),
                        1,
                        "periodSecondsInside should be equal to how long it's been in the pool (only 1 day in range)"
                    );
                });
            });
        });

        // time = period + 3 days
        describe("boosted in range", () => {
            let period: BigNumberish;

            before("advance period and check boosted in range", async () => {
                let time = await pool.time();

                period = time.div(WEEK);

                let delta = period.add(1).mul(WEEK).sub(time);

                await pool.advanceTime(delta);

                // make some swaps to write oracle
                for (const swap of writingSwaps) {
                    await executeSwap(pool, swap, poolFunctions);

                    // console.log(
                    //     "slot0 after burn and swap",
                    //     await pool.slot0()
                    // );
                    // console.log("liq", await pool.liquidity());
                    // console.log("boosted liq", await pool.boostedLiquidity());
                }

                // grab periodInfo after advancing period
                periodInfo = await pool.periods(period);
            });

            it("boosted in range", async () => {
                // boosted time should be 5 days, since the only in range position was only boosted for a day
                // 1 day from period + 1 day ~ period + 2 days
                // 4 days from period + 3 days ~ period + 7 days
                expect(periodInfo.boostedInRange).to.eq(
                    86400 * 5,
                    "boosted time should be exactly 5 days"
                );
            });
        });
    });
});
