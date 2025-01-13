import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

import {
    expandTo18Decimals,
    encodePrice,
    MINIMUM_LIQUIDITY,
} from "./shared/utilities";
import { Pair, PairFactory, Token } from "./../typechain-types";
import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { Signer, AddressLike } from "ethers";

describe("Pair", () => {
    async function fixture() {
        const [wallet, other] = await ethers.getSigners();

        const AccessManager = await ethers.getContractFactory("AccessManager");
        const accessManager = await AccessManager.deploy(wallet.address);

        const PairFactory = await ethers.getContractFactory("PairFactory");
        const factory = await PairFactory.deploy(
            ethers.ZeroAddress,
            other.address,
            await accessManager.getAddress(),
            ethers.ZeroAddress,
        );
        const Pair = await ethers.getContractFactory("Pair");

        const ERC20 = await ethers.getContractFactory("Token");

        const tokenA = await ERC20.deploy(expandTo18Decimals(10000));
        const tokenB = await ERC20.deploy(expandTo18Decimals(10000));
        const [tokenAAddress, tokenBAddress] = (await Promise.all([
            tokenA.getAddress(),
            tokenB.getAddress(),
        ])) as [AddressLike, AddressLike];

        await factory.createPair(tokenAAddress, tokenBAddress, false);
        const pairAddress = await factory.getPair(
            tokenAAddress,
            tokenBAddress,
            false,
        );
        const pair = await ethers.getContractAt("Pair", pairAddress);

        const token0Address = await pair.token0();
        const token0 = tokenAAddress === token0Address ? tokenA : tokenB;
        const token1 = tokenAAddress === token0Address ? tokenB : tokenA;
        return { pair, token0, token1, wallet, other, factory };
    }

    it("mint", async () => {
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);
        const token0Amount = expandTo18Decimals(1);
        const token1Amount = expandTo18Decimals(4);
        await token0.transfer(await pair.getAddress(), token0Amount);
        await token1.transfer(await pair.getAddress(), token1Amount);

        const expectedLiquidity = expandTo18Decimals(2);
        await expect(pair.mint(wallet.address))
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
        expect(await token0.balanceOf(await pair.getAddress())).to.eq(
            token0Amount,
        );
        expect(await token1.balanceOf(await pair.getAddress())).to.eq(
            token1Amount,
        );
        const reserves = await pair.getReserves();
        expect(reserves[0]).to.eq(token0Amount);
        expect(reserves[1]).to.eq(token1Amount);
    });

    async function addLiquidity(
        token0: Token,
        token1: Token,
        pair: Pair,
        wallet: Signer,
        token0Amount: bigint,
        token1Amount: bigint,
    ) {
        const pairAddress = await pair.getAddress();
        await token0.transfer(pairAddress, token0Amount);
        await token1.transfer(pairAddress, token1Amount);
        await pair.mint(await wallet.getAddress());
    }

    const swapTestCases: bigint[][] = [
        [1, 5, 10, "1662497915624478906"],
        [1, 10, 5, "453305446940074565"],

        [2, 5, 10, "2851015155847869602"],
        [2, 10, 5, "831248957812239453"],

        [1, 10, 10, "906610893880149131"],
        [1, 100, 100, "987158034397061298"],
        [1, 1000, 1000, "996006981039903216"],
    ].map((a) =>
        a.map((n) =>
            typeof n === "string" ? BigInt(n) : expandTo18Decimals(n),
        ),
    );
    swapTestCases.forEach((swapTestCase, i) => {
        it(`getInputPrice:${i}`, async () => {
            const { pair, wallet, token0, token1 } = await loadFixture(fixture);

            const [
                swapAmount,
                token0Amount,
                token1Amount,
                expectedOutputAmount,
            ] = swapTestCase;
            await addLiquidity(
                token0,
                token1,
                pair,
                wallet,
                token0Amount,
                token1Amount,
            );
            await token0.transfer(await pair.getAddress(), swapAmount);
            await expect(
                pair.swap(0, expectedOutputAmount + 1n, wallet.address, "0x"),
            ).to.be.revertedWithCustomError(pair, "K");
            await pair.swap(0, expectedOutputAmount, wallet.address, "0x");
        });
    });

    const optimisticTestCases: bigint[][] = [
        ["997000000000000000", 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .997)
        ["997000000000000000", 10, 5, 1],
        ["997000000000000000", 5, 5, 1],
        [1, 5, 5, "1003009027081243731"], // given amountOut, amountIn = ceiling(amountOut / .997)
    ].map((a) =>
        a.map((n) =>
            typeof n === "string" ? BigInt(n) : expandTo18Decimals(n),
        ),
    );
    optimisticTestCases.forEach((optimisticTestCase, i) => {
        it(`optimistic:${i}`, async () => {
            const { pair, wallet, token0, token1 } = await loadFixture(fixture);

            const [outputAmount, token0Amount, token1Amount, inputAmount] =
                optimisticTestCase;
            await addLiquidity(
                token0,
                token1,
                pair,
                wallet,
                token0Amount,
                token1Amount,
            );
            await token0.transfer(await pair.getAddress(), inputAmount);
            await expect(
                pair.swap(outputAmount + 1n, 0n, wallet.address, "0x"),
            ).to.be.revertedWithCustomError(pair, "K");
            await pair.swap(outputAmount, 0, wallet.address, "0x");
        });
    });

    it("swap:token0", async () => {
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(5);
        const token1Amount = expandTo18Decimals(10);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const swapAmount = expandTo18Decimals(1);
        const expectedOutputAmount = 1662497915624478906n;
        await token0.transfer(await pair.getAddress(), swapAmount);
        await expect(pair.swap(0, expectedOutputAmount, wallet.address, "0x"))
            .to.emit(token1, "Transfer")
            .withArgs(
                await pair.getAddress(),
                wallet.address,
                expectedOutputAmount,
            )
            .to.emit(pair, "Sync")
            .withArgs(
                token0Amount + swapAmount,
                token1Amount - expectedOutputAmount,
            )
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
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(5);
        const token1Amount = expandTo18Decimals(10);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const swapAmount = expandTo18Decimals(1);
        const expectedOutputAmount = 453305446940074565n;
        await token1.transfer(await pair.getAddress(), swapAmount);
        await expect(pair.swap(expectedOutputAmount, 0, wallet.address, "0x"))
            .to.emit(token0, "Transfer")
            .withArgs(
                await pair.getAddress(),
                wallet.address,
                expectedOutputAmount,
            )
            .to.emit(pair, "Sync")
            .withArgs(
                token0Amount - expectedOutputAmount,
                token1Amount + swapAmount,
            )
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
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(5);
        const token1Amount = expandTo18Decimals(10);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        // ensure that setting price{0,1}CumulativeLast for the first time doesn't affect our gas math
        await ethers.provider.send("evm_mine", [
            (await wallet.provider.getBlock("latest"))!.timestamp + 1,
        ]);

        await time.setNextBlockTimestamp(
            (await wallet.provider.getBlock("latest"))!.timestamp + 1,
        );
        await pair.sync();

        const swapAmount = expandTo18Decimals(1);
        const expectedOutputAmount = 453305446940074565n;
        await token1.transfer(await pair.getAddress(), swapAmount);
        await time.setNextBlockTimestamp(
            (await wallet.provider.getBlock("latest"))!.timestamp + 1,
        );
        const tx = await pair.swap(
            expectedOutputAmount,
            0,
            wallet.address,
            "0x",
        );
        const receipt = await tx.wait();
        expect(receipt!.gasUsed).to.eq(85165);
    });

    it("burn", async () => {
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(3);
        const token1Amount = expandTo18Decimals(3);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const expectedLiquidity = expandTo18Decimals(3);
        await pair.transfer(
            await pair.getAddress(),
            expectedLiquidity - MINIMUM_LIQUIDITY,
        );
        await expect(pair.burn(wallet.address))
            .to.emit(pair, "Transfer")
            .withArgs(
                await pair.getAddress(),
                ethers.ZeroAddress,
                expectedLiquidity - MINIMUM_LIQUIDITY,
            )
            .to.emit(token0, "Transfer")
            .withArgs(
                await pair.getAddress(),
                wallet.address,
                token0Amount - 1000n,
            )
            .to.emit(token1, "Transfer")
            .withArgs(
                await pair.getAddress(),
                wallet.address,
                token1Amount - 1000n,
            )
            .to.emit(pair, "Sync")
            .withArgs(1000, 1000)
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

    it("reserve{0,1}CumulativeLast", async () => {
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(3);
        const token1Amount = expandTo18Decimals(3);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const blockTimestamp = (await pair.getReserves())[2];
        await time.setNextBlockTimestamp(blockTimestamp + 1n);
        await pair.sync();

        expect(await pair.reserve0CumulativeLast()).to.eq(token0Amount);
        expect(await pair.reserve1CumulativeLast()).to.eq(token1Amount);
        expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 1n);

        const swapAmount = expandTo18Decimals(3);
        await token0.transfer(await pair.getAddress(), swapAmount);

        let reserve0CumulativeLast = await pair.reserve0CumulativeLast();
        let reserve1CumulativeLast = await pair.reserve1CumulativeLast();
        let reserves = await pair.getReserves();
        await time.setNextBlockTimestamp(blockTimestamp + 10n);

        // swap to a new price eagerly instead of syncing
        await pair.swap(0, expandTo18Decimals(1), wallet.address, "0x"); // make the price nice

        expect(await pair.reserve0CumulativeLast()).to.eq(
            reserve0CumulativeLast + reserves._reserve0 * 9n,
        );
        expect(await pair.reserve1CumulativeLast()).to.eq(
            reserve1CumulativeLast + reserves._reserve1 * 9n,
        );
        expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 10n);

        reserve0CumulativeLast = await pair.reserve0CumulativeLast();
        reserve1CumulativeLast = await pair.reserve1CumulativeLast();
        reserves = await pair.getReserves();

        await time.setNextBlockTimestamp(blockTimestamp + 20n);
        await pair.sync();

        const newPrice = encodePrice(
            expandTo18Decimals(6),
            expandTo18Decimals(2),
        );
        expect(await pair.reserve0CumulativeLast()).to.eq(
            reserve0CumulativeLast + reserves._reserve0 * 10n,
        );
        expect(await pair.reserve1CumulativeLast()).to.eq(
            reserve1CumulativeLast + reserves._reserve1 * 10n,
        );
        expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 20n);
    });

    it("feeTo:off", async () => {
        const { pair, wallet, token0, token1 } = await loadFixture(fixture);

        const token0Amount = expandTo18Decimals(1000);
        const token1Amount = expandTo18Decimals(1000);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const swapAmount = expandTo18Decimals(1);
        const expectedOutputAmount = 996006981039903216n;
        await token1.transfer(await pair.getAddress(), swapAmount);
        await pair.swap(expectedOutputAmount, 0, wallet.address, "0x");

        const expectedLiquidity = expandTo18Decimals(1000);
        await pair.transfer(
            await pair.getAddress(),
            expectedLiquidity - MINIMUM_LIQUIDITY,
        );
        await pair.burn(wallet.address);
        expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
    });

    it("feeTo:on", async () => {
        const { pair, wallet, token0, token1, other, factory } =
            await loadFixture(fixture);

        await factory.setFeeRecipient(await pair.getAddress(), other.address);

        await factory.setPairFeeSplit(await pair.getAddress(), 10000n);

        const token0Amount = expandTo18Decimals(1000);
        const token1Amount = expandTo18Decimals(1000);
        await addLiquidity(
            token0,
            token1,
            pair,
            wallet,
            token0Amount,
            token1Amount,
        );

        const swapAmount = expandTo18Decimals(1);
        const expectedOutputAmount = 996006981039903216n;
        await token1.transfer(await pair.getAddress(), swapAmount);
        await pair.swap(expectedOutputAmount, 0, wallet.address, "0x");

        const expectedLiquidity = expandTo18Decimals(1000);
        await pair.transfer(
            await pair.getAddress(),
            expectedLiquidity - MINIMUM_LIQUIDITY,
        );

        const kLast = sqrt(await pair.kLast());

        const reserves = await pair.getReserves();
        const k = sqrt(reserves._reserve0 * reserves._reserve1);

        const feeGrowth = k - kLast;

        await pair.burn(wallet.address);
        expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY + feeGrowth);
        expect(await pair.balanceOf(other.address)).to.eq(feeGrowth);

        // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
        // ...because the initial liquidity amounts were equal
        expect(await token0.balanceOf(await pair.getAddress())).to.eq(
            1000n + 1497010102184673n,
        );
        expect(await token1.balanceOf(await pair.getAddress())).to.eq(
            1000n + 1500001123877809n,
        );
    });
});

function log2(value: bigint) {
    let result = 0n;
    if (value >> 128n > 0n) {
        value >>= 128n;
        result += 128n;
    }
    if (value >> 64n > 0n) {
        value >>= 64n;
        result += 64n;
    }
    if (value >> 32n > 0n) {
        value >>= 32n;
        result += 32n;
    }
    if (value >> 16n > 0n) {
        value >>= 16n;
        result += 16n;
    }
    if (value >> 8n > 0) {
        value >>= 8n;
        result += 8n;
    }
    if (value >> 4n > 0n) {
        value >>= 4n;
        result += 4n;
    }
    if (value >> 2n > 0) {
        value >>= 2n;
        result += 2n;
    }
    if (value >> 1n > 0n) {
        result += 1n;
    }
    return result;
}

function sqrt(a: bigint) {
    if (a == 0n) return 0n;

    let result = 1n << (log2(a) >> 1n);
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    result = (result + a / result) >> 1n;
    return result < a / result ? result : a / result;
}
