import { ethers } from "hardhat";
import {
  setBalance,
  impersonateAccount,
  loadFixture,
} from "@nomicfoundation/hardhat-network-helpers";
import { e } from "../../../../utils/helpers";
import {
  ClPoolFactory,
  IWETH9,
  MockTimeSwapRouter,
  NonfungiblePositionManager,
  NonfungibleTokenPositionDescriptor,
  PairFlash,
  Quoter,
  QuoterV2,
} from "./../../../typechain-types";

import { Contract } from "@ethersproject/contracts";
import { TestDeploy, testDeploy } from "../../../../utils/testDeployment";

export async function v1FactoryFixture(): Promise<{ factory: Contract }> {
  const c = await loadFixture(testDeploy);
  const { pairFactory: factory } = c;

  return { factory };
}

export async function v2RouterFixture(): Promise<{
  weth9: IWETH9;
  factory: ClPoolFactory;
  router: MockTimeSwapRouter;
  nftDescriptor: NonfungibleTokenPositionDescriptor;
  nft: NonfungiblePositionManager;
  proxyAdminAddress: string;
  pairFlash: PairFlash;
  quoter: Quoter;
  quoterV2: QuoterV2;
  c: TestDeploy;
}> {
  const c = await testDeploy();
  const factory = c.factory;
  const nftDescriptor = c.nftDescriptor;
  const nft = c.nfpManager;
  const proxyAdminAddress = c.proxyAdmin.getAddress();
  const pairFlash = c.pairFlash;
  const quoter = c.quoter;
  const quoterV2 = c.quoterV2;
  const weth9 = c.weth;

  // replace router with mock router

  await impersonateAccount(await c.proxyAdmin.getAddress());
  await setBalance(await c.proxyAdmin.getAddress(), e(1000));

  const proxyAdmin = await ethers.getSigner(await c.proxyAdmin.getAddress());

  const routerProxy = await ethers.getContractAt(
    "TransparentUpgradeableProxy",
    await c.swapRouter.getAddress()
  );

  const MockRouter = await ethers.getContractFactory("MockTimeSwapRouter");

  const mockRouterImp = (await MockRouter.deploy()) as MockTimeSwapRouter;

  await routerProxy.connect(proxyAdmin).up(mockRouterImp.address);

  const router = MockRouter.attach(c.swapRouter.address) as MockTimeSwapRouter;

  return {
    factory,
    weth9,
    router,
    nftDescriptor,
    nft,
    proxyAdminAddress,
    pairFlash,
    quoter,
    quoterV2,
    c,
  };
}
