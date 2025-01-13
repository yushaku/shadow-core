import { Contract, Wallet } from "ethers";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import completeFixture from "./shared/completeFixture";
import { expect } from "./shared/expect";
import { ClPoolFactory, TestCallbackValidation } from "./../../typechain-types";
import { TestERC20 } from "./../../typechain-types/contracts/v2-periphery/test/TestERC20";
import { FeeAmount } from "./shared/constants";

describe("CallbackValidation", () => {
    let nonpairAddr: Wallet, wallets: Wallet[];

    async function callbackValidationFixture(): Promise<{
        callbackValidation: TestCallbackValidation;
        tokens: [TestERC20, TestERC20];
        factory: ClPoolFactory;
    }> {
        const { factory } = await completeFixture();
        const tokenFactory = await ethers.getContractFactory(
            "contracts/v2-periphery/test/TestERC20.sol:TestERC20"
        );
        const callbackValidationFactory = await ethers.getContractFactory(
            "TestCallbackValidation"
        );
        const tokens: [TestERC20, TestERC20] = [
            (await tokenFactory.deploy(
                ethers.MaxUint256 / 2n
            )) as TestERC20, // do not use maxu256 to avoid overflowing
            (await tokenFactory.deploy(
                ethers.MaxUint256 / 2n
            )) as TestERC20,
        ];
        const callbackValidation =
            (await callbackValidationFactory.deploy()) as TestCallbackValidation;

        return {
            tokens,
            callbackValidation,
            factory,
        };
    }

    let callbackValidation: TestCallbackValidation;
    let tokens: [TestERC20, TestERC20];
    let factory: Contract;

    before("create fixture loader", async () => {
        [nonpairAddr, ...wallets] = await (ethers as any).getSigners();
    });

    beforeEach("load fixture", async () => {
        ({ callbackValidation, tokens, factory } = await loadFixture(
            callbackValidationFixture
        ));
    });

    it("reverts when called from an address other than the associated ClPool", async () => {
        expect(
            callbackValidation
                .connect(nonpairAddr)
                .verifyCallback(
                    factory.address,
                    tokens[0].address,
                    tokens[1].address,
                    FeeAmount.MEDIUM
                )
        ).to.be.reverted;
    });
});
