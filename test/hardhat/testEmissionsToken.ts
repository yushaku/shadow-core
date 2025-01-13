import { ethers } from "hardhat";
import { Shadow } from "../typechain-types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
describe("Shadow", function () {
    async function deploy() {
        const [deployer, user] = await ethers.getSigners();

        const shadow = (await ethers.deployContract("Shadow", [
            deployer.address,
        ])) as Shadow;

        return { deployer, user, shadow };
    }

    it("Should return the proper name, symbol and decimals", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        expect(await shadow.name()).to.equal("CLEOPATRA");
        expect(await shadow.symbol()).to.equal("CLEO");
        expect(await shadow.decimals()).to.equal(18);
    });

    it("Should have no balances in the beginning", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        expect(await shadow.balanceOf(deployer.address)).to.equal(0);
        expect(await shadow.balanceOf(user.address)).to.equal(0);
        expect(await shadow.totalSupply()).to.equal(0);
    });

    it("Should mint the proper amounts", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        expect(await shadow.mint(deployer.address, amount)).to.not.be.reverted;
        expect(await shadow.balanceOf(deployer.address)).to.equal(amount);
        expect(await shadow.totalSupply()).to.equal(amount);
    });

    it("Should not allow unauthorized addresses to mint", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        await expect(shadow.connect(user).mint(user.address, amount)).to.be
            .reverted;
    });

    it("Should handle change of minter properly", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        await expect(shadow.setMinter(user.address)).to.not.be.reverted;
        await expect(shadow.mint(deployer.address, amount)).to.be.reverted;
        await expect(shadow.connect(user).mint(user.address, amount)).to.not.be
            .reverted;
        expect(await shadow.balanceOf(user.address)).to.equal(amount);
        expect(await shadow.balanceOf(deployer.address)).to.equal(0);
    });

    it("Should mint to the proper receiver", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        await shadow.mint(user.address, amount);
        expect(await shadow.balanceOf(user.address)).to.equal(amount);
        expect(await shadow.balanceOf(deployer.address)).to.equal(0);
    });

    it("Should transfer tokens properly", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = 100;
        await shadow.mint(deployer.address, amount);
        await expect(
            shadow.transfer(user.address, amount)
        ).to.changeTokenBalances(shadow, [deployer, user], [-amount, amount]);
        expect(await shadow.balanceOf(deployer.address)).to.equal(0);
        expect(await shadow.balanceOf(user.address)).to.equal(100);
        await expect(
            shadow.connect(user).transfer(deployer.address, amount)
        ).to.changeTokenBalances(shadow, [user, deployer], [-amount, amount]);
        expect(await shadow.balanceOf(user.address)).to.equal(0);
        expect(await shadow.balanceOf(deployer.address)).to.equal(100);
    });

    it("Should not allow transferFrom without approval", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        await shadow.mint(deployer.address, amount);
        await expect(
            shadow
                .connect(user)
                .transferFrom(deployer.address, user.address, amount)
        ).to.be.reverted;
    });

    it("Should allow transferFrom with approvals", async function () {
        const { deployer, user, shadow } = await loadFixture(deploy);

        const amount = ethers.parseEther("100");
        await shadow.mint(deployer.address, amount);
        await shadow.approve(user.address, amount);

        expect(await shadow.allowance(deployer.address, user.address)).to.equal(
            amount
        );
        expect(
            await shadow
                .connect(user)
                .transferFrom(deployer.address, user.address, amount)
        );
        expect(await shadow.balanceOf(deployer.address)).to.equal(0);
        expect(await shadow.balanceOf(user.address)).to.equal(amount);
        expect(await shadow.allowance(deployer.address, user.address)).to.equal(
            0
        );
    });
});
