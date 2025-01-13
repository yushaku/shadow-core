import { ethers } from "hardhat";
import {
    setBalance,
    impersonateAccount,
} from "@nomicfoundation/hardhat-network-helpers";
import { e } from "../../../../utils/helpers";
import { v2RouterFixture } from "./externalFixtures";
import { constants } from "ethers";
import {
    IWETH9,
    MockTimeNonfungiblePositionManager,
    MockTimeSwapRouter,
    NonfungibleTokenPositionDescriptor,
    PairFlash,
    Quoter,
    QuoterV2,
    ClPoolFactory,
} from "./../../../typechain-types";
import { TestERC20 } from "../../../typechain-types/contracts/v2-periphery/test/TestERC20";
import { TestDeploy } from "../../../../utils/testDeployment";

async function completeFixture(): Promise<{
    weth9: IWETH9;
    factory: ClPoolFactory;
    router: MockTimeSwapRouter;
    nft: MockTimeNonfungiblePositionManager;
    nftDescriptor: NonfungibleTokenPositionDescriptor;
    pairFlash: PairFlash;
    quoter: Quoter;
    quoterV2: QuoterV2;
    tokens: [TestERC20, TestERC20, TestERC20];
    c: TestDeploy;
}> {
    const {
        weth9,
        factory,
        router,
        nftDescriptor,
        proxyAdminAddress,
        pairFlash,
        quoter,
        quoterV2,
        c,
    } = await v2RouterFixture();

    const tokenFactory = await ethers.getContractFactory(
        "contracts/v2-periphery/test/TestERC20.sol:TestERC20"
    );
    const tokens: [TestERC20, TestERC20, TestERC20] = [
        (await tokenFactory.deploy(constants.MaxUint256.div(2))) as TestERC20, // do not use maxu256 to avoid overflowing
        (await tokenFactory.deploy(constants.MaxUint256.div(2))) as TestERC20,
        (await tokenFactory.deploy(constants.MaxUint256.div(2))) as TestERC20,
    ];

    // upgrade nftProxy to mock contract

    await impersonateAccount(proxyAdminAddress);
    await setBalance(proxyAdminAddress, e(1000));

    const proxyAdmin = await ethers.getSigner(proxyAdminAddress);

    const nftProxy = await ethers.getContractAt(
        "TransparentUpgradeableProxy",
        c.nfpManager.address
    );

    const PositionManagerAux = await ethers.getContractFactory(
        "PositionManagerAux"
    );

    const PoolInitializer = await ethers.getContractFactory("PoolInitializer");

    const positionManagerAux = await PositionManagerAux.deploy();

    const poolInitializer = await PoolInitializer.deploy();

    const MockNfpManager = await ethers.getContractFactory(
        "MockTimeNonfungiblePositionManager",
        {
            libraries: {
                PositionManagerAux: positionManagerAux.address,
                PoolInitializer: poolInitializer.address,
            },
        }
    );

    const mockNftImp =
        (await MockNfpManager.deploy()) as MockTimeNonfungiblePositionManager;
    const nft = MockNfpManager.attach(nftProxy.address);
    await nftProxy.connect(proxyAdmin).upgradeTo(mockNftImp.address);

    await nft.setVotingEscrow(c.votingEscrow.address);

    tokens.sort((a, b) =>
        a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1
    );

    return {
        weth9,
        factory,
        router,
        tokens,
        nft,
        nftDescriptor,
        pairFlash,
        quoter,
        quoterV2,
        c,
    };
}

export default completeFixture;
