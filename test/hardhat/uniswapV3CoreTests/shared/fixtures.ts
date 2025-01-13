import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
    impersonateAccount,
    setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import {
    MockTimeClPool,
    MockTimeClPoolFactory,
    TestERC20,
    ClPoolFactory,
    TestClPoolCallee,
    TestClPoolRouter,
    TransparentUpgradeableProxy,
    TransparentUpgradeableProxy__factory,
    GaugeV2,
    FeeDistributor,
    MockTimeNonfungiblePositionManager,
} from "./../../../typechain-types";

import { TestDeploy, testDeploy } from "../../../../utils/testDeployment";
import { FEES_TO_TICK_SPACINGS } from "../../../../utils/constants";
import { e } from "../../../../utils/helpers";

interface FactoryFixture {
    factory: MockTimeClPoolFactory;
}

interface TokensFixture {
    token0: TestERC20;
    token1: TestERC20;
    token2: TestERC20;
}
interface TaxTokensFixture {
    taxToken0: TestERC20;
    taxToken1: TestERC20;
    taxToken2: TestERC20;
}

async function tokensFixture(): Promise<TokensFixture> {
    const tokenFactory = await ethers.getContractFactory(
        "contracts/v2/test/TestERC20.sol:TestERC20"
    );
    const tokenA = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;
    const tokenB = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;
    const tokenC = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;

    const [token0, token1, token2] = [tokenA, tokenB, tokenC].sort(
        (tokenA, tokenB) =>
            tokenA.address.toLowerCase() < tokenB.address.toLowerCase() ? -1 : 1
    );

    return { token0, token1, token2 };
}

async function feeOnTransferTokensFixture(): Promise<TokensFixture> {
    const tokenFactory = await ethers.getContractFactory(
        "contracts/v2/test/FeeOnTransferTestERC20.sol:FeeOnTransferTestERC20"
    );
    const tokenA = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;
    const tokenB = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;
    const tokenC = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255)
    )) as TestERC20;

    const [token0, token1, token2] = [tokenA, tokenB, tokenC].sort(
        (tokenA, tokenB) =>
            tokenA.address.toLowerCase() < tokenB.address.toLowerCase() ? -1 : 1
    );

    return { token0, token1, token2 };
}

type TokensAndFactoryFixture = FactoryFixture &
    TokensFixture &
    TaxTokensFixture;

interface PoolFixture extends TokensAndFactoryFixture {
    swapTargetCallee: TestClPoolCallee;
    swapTargetRouter: TestClPoolRouter;
    createPool(
        fee: number,
        sqrtPriceX96: BigNumber,
        tickSpacing?: number,
        firstToken?: TestERC20,
        secondToken?: TestERC20
    ): Promise<MockTimeClPool>;
    createNormalPool(
        fee: number,
        sqrtPriceX96: BigNumber,
        firstToken?: TestERC20,
        secondToken?: TestERC20
    ): Promise<MockTimeClPool>;
    createGauge(
        poolAddress: string
    ): Promise<{ gauge: GaugeV2; feeDistributor: FeeDistributor }>;
    c: TestDeploy;
}

// Monday, October 5, 2020 9:00:00 AM GMT-05:00
export const TEST_POOL_START_TIME = 1601906400;
export const TEST_POOL_START_PERIOD_TIME = 1601510400;
export const SECONDS_PER_LIQUIDITY_INIT =
    "545100501377799618628145949242437061247919718400"; // 1601906400 * 2 ** 128
export const SECONDS_PER_LIQUIDITY_PERIOD_INIT =
    "544965749560498926996614452897894081036183142400"; // 1601510400 * 2 ** 128

export async function poolFixture(): Promise<PoolFixture> {
    const c = await testDeploy();

    const { token0, token1, token2 } = await tokensFixture();

    const {
        token0: taxToken0,
        token1: taxToken1,
        token2: taxToken2,
    } = await feeOnTransferTokensFixture();

    // change implmentations to the Mock Time test contracts

    const MockTimeOracle = await ethers.getContractFactory("MockTimeOracle");
    const MockTimeTick = await ethers.getContractFactory("MockTimeTick");
    const MockTimeProtocolActions = await ethers.getContractFactory(
        "MockTimeProtocolActions"
    );

    const mockTimeOracle = await MockTimeOracle.deploy();
    const mockTimeTick = await MockTimeTick.deploy();
    const mockTimeProtocolActions = await MockTimeProtocolActions.deploy();

    const MockTimePosition = await ethers.getContractFactory(
        "MockTimePosition",
        { libraries: { MockTimeOracle: mockTimeOracle.address } }
    );
    const mockTimePosition = await MockTimePosition.deploy();

    const MockTimeClPool = await ethers.getContractFactory("MockTimeClPool", {
        libraries: {
            MockTimeOracle: mockTimeOracle.address,
            MockTimeTick: mockTimeTick.address,
            MockTimePosition: mockTimePosition.address,
            MockTimeProtocolActions: mockTimeProtocolActions.address,
        },
    });

    const MockTimeClPoolFactory = await ethers.getContractFactory(
        "MockTimeClPoolFactory"
    );

    const mockTimeClPoolFactory = await MockTimeClPoolFactory.deploy();

    const MockTimeGaugeV2 = await ethers.getContractFactory("MockTimeGaugeV2");

    const mockTimeGaugeV2 = await MockTimeGaugeV2.deploy();

    const factoryProxy = await ethers.getContractAt(
        "TransparentUpgradeableProxy",
        c.factory.address
    );

    await impersonateAccount(c.proxyAdmin.address);
    await setBalance(c.proxyAdmin.address, e(1000));

    const proxyAdmin = await ethers.getSigner(c.proxyAdmin.address);

    await factoryProxy
        .connect(proxyAdmin)
        .upgradeTo(mockTimeClPoolFactory.address);

    const mockTimeClPool = await MockTimeClPool.deploy();

    const factory = MockTimeClPoolFactory.attach(
        factoryProxy.address
    ) as MockTimeClPoolFactory;

    await factory.setImplementation(mockTimeClPool.address);

    // const owner = (await ethers.getSigners())[0];
    // await factory.setFeeCollector(owner.address);

    await c.gaugeV2Factory.setImplementation(mockTimeGaugeV2.address);

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

    // deploy more proxies to hold the test contracts
    const contractDeployer = c.contractDeployer;

    const deployerDeployedLength = (
        await contractDeployer.deployedContractsLength()
    ).toNumber();
    const salts = [];
    const newTestContractsLength = 2;
    for (
        let i = deployerDeployedLength;
        i < deployerDeployedLength + newTestContractsLength;
        i++
    ) {
        salts.push(deployerDeployedLength + i);
    }

    await contractDeployer.deployMany(
        TransparentUpgradeableProxy__factory.bytecode,
        salts
    );

    const proxiesAddresses = (
        await contractDeployer.getDeployedContracts()
    ).slice(
        deployerDeployedLength,
        deployerDeployedLength + newTestContractsLength
    );
    const proxies: TransparentUpgradeableProxy[] = [];

    for (let i = 0; i < newTestContractsLength; i++) {
        proxies.push(
            await ethers.getContractAt(
                "TransparentUpgradeableProxy",
                proxiesAddresses[i]
            )
        );
    }

    // Deploy and attach the new test contracts to the proxies

    const calleeContractFactory = await ethers.getContractFactory(
        "TestClPoolCallee"
    );
    const routerContractFactory = await ethers.getContractFactory(
        "TestClPoolRouter"
    );

    const swapTargetCalleeImp =
        (await calleeContractFactory.deploy()) as TestClPoolCallee;
    const swapTargetRouterImp =
        (await routerContractFactory.deploy()) as TestClPoolRouter;

    await proxies[0].initialize(
        swapTargetCalleeImp.address,
        c.proxyAdmin.address,
        "0x"
    );
    await proxies[1].initialize(
        swapTargetRouterImp.address,
        c.proxyAdmin.address,
        "0x"
    );

    const swapTargetCallee = await ethers.getContractAt(
        "TestClPoolCallee",
        proxies[0].address
    );
    const swapTargetRouter = await ethers.getContractAt(
        "TestClPoolRouter",
        proxies[1].address
    );

    return {
        token0,
        token1,
        token2,
        factory,
        taxToken0,
        taxToken1,
        taxToken2,
        swapTargetCallee,
        swapTargetRouter,
        createPool: async (
            fee,
            sqrtPriceX96,
            tickSpacing?,
            firstToken = token0,
            secondToken = token1
        ) => {
            tickSpacing = tickSpacing ?? FEES_TO_TICK_SPACINGS[fee];
            const tx = await factory[
                "createPool(address,address,uint24,int24,uint160)"
            ](
                firstToken.address,
                secondToken.address,
                fee,
                tickSpacing,
                sqrtPriceX96
            );

            const receipt = await tx.wait();
            // event order would change if pool is initialized
            const poolAddress = receipt.events?.[0].args?.pool as string
            console.log("poolAddress: ", poolAddress)
                

            return MockTimeClPool.attach(poolAddress) as MockTimeClPool;
        },
        // normal pools use correct salt values so periphery can find them
        createNormalPool: async (
            fee,
            sqrtPriceX96,
            firstToken = token0,
            secondToken = token1
        ) => {
            const tx = await factory[
                "createPool(address,address,uint24,uint160)"
            ](firstToken.address, secondToken.address, fee, sqrtPriceX96);

            const receipt = await tx.wait();
            const poolAddress = receipt.events?.[0].args?.pool as string;
            console.log(poolAddress);

            return MockTimeClPool.attach(poolAddress) as MockTimeClPool;
        },
        createGauge: async (poolAddress: string) => {
            const adminAddress = await c.voter.governor();
            await impersonateAccount(adminAddress);
            const admin = await ethers.getSigner(adminAddress);
            await setBalance(adminAddress, e(1000));

            const pool = await ethers.getContractAt(
                "MockTimeClPool",
                poolAddress
            );
            const token0 = await pool.token0();
            const token1 = await pool.token1();
            const fee = await pool.fee();
            await c.voter.connect(admin).whitelist(token0);
            await c.voter.connect(admin).whitelist(token1);

            await c.voter.createCLGauge(token0, token1, fee);

            const gaugeAddress = await c.voter.gauges(poolAddress);
            const gauge = (await ethers.getContractAt(
                "GaugeV2",
                gaugeAddress
            )) as GaugeV2;
            const feeDistributorAddress = await c.voter.feeDistributors(
                gauge.address
            );

            const feeDistributor = (await ethers.getContractAt(
                "FeeDistributor",
                feeDistributorAddress
            )) as FeeDistributor;

            return { gauge, feeDistributor };
        },
        c,
    };
}
