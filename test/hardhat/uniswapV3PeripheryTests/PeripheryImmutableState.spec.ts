import { Contract } from "ethers";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

import { PeripheryImmutableStateTest, IWETH9 } from "./../../typechain-types";
import { expect } from "./shared/expect";
import { v2RouterFixture } from "./shared/externalFixtures";

describe("PeripheryImmutableState", () => {
    const nonfungiblePositionManagerFixture: () => Promise<{
        weth9: IWETH9;
        factory: Contract;
        state: PeripheryImmutableStateTest;
    }> = async () => {
        const { weth9, factory } = await v2RouterFixture();

        const stateFactory = await ethers.getContractFactory(
            "PeripheryImmutableStateTest"
        );
        const state =
            (await stateFactory.deploy()) as PeripheryImmutableStateTest;
        await state.initialize(factory.address, weth9.address);

        return {
            weth9,
            factory,
            state,
        };
    };

    let factory: Contract;
    let weth9: IWETH9;
    let state: PeripheryImmutableStateTest;

    beforeEach("load fixture", async () => {
        ({ state, weth9, factory } = await loadFixture(
            nonfungiblePositionManagerFixture
        ));
    });

    it("bytecode size", async () => {
        expect(
            ((await state.provider.getCode(state.address)).length - 2) / 2
        ).to.matchSnapshot();
    });

    describe("#WETH9", () => {
        it("points to WETH9", async () => {
            expect(await state.WETH9()).to.eq(weth9.address);
        });
    });

    describe("#factory", () => {
        it("points to v3 core factory", async () => {
            expect(await state.factory()).to.eq(factory.address);
        });
    });
});
