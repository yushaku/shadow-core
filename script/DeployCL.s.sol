// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Pair} from "contracts/legacy/Pair.sol";
import {RamsesV3Pool} from "contracts/CL/core/RamsesV3Pool.sol";
import {FeeCollector} from "contracts/CL/gauge/FeeCollector.sol";
import {ClGaugeFactory} from "contracts/CL/gauge/ClGaugeFactory.sol";
import {RamsesV3Factory} from "contracts/CL/core/RamsesV3Factory.sol";
import {RamsesV3PoolDeployer} from "contracts/CL/core/RamsesV3PoolDeployer.sol";
import {NonfungiblePositionManager} from "contracts/CL/periphery/NonfungiblePositionManager.sol";
import {NonfungibleTokenPositionDescriptor} from "contracts/CL/periphery/NonfungibleTokenPositionDescriptor.sol";
import {SwapRouter} from "contracts/CL/periphery/SwapRouter.sol";
import {UniversalRouter, RouterParameters} from "contracts/CL/universalRouter/UniversalRouter.sol";
import {QuoterV2} from "contracts/CL/periphery/lens/QuoterV2.sol";
import {TickLens} from "contracts/CL/periphery/lens/TickLens.sol";

import "./Helper.s.sol";

contract DeployCLScript is Script {
	Helper.Config public config;
	Helper public helper;

	constructor() {
		helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function run()
		public
		returns (address, address, address, address, address, address, address, address)
	{
		address accessHubAddress = helper.readAddress("AccessHub");
		address voterAddress = helper.readAddress("Voter");
		address pairFactoryAddress = helper.readAddress("PairFactory");
		address treasuryAddress = config.deployer;

		if (
			accessHubAddress == address(0) ||
			voterAddress == address(0) ||
			pairFactoryAddress == address(0)
		) revert("Core Contracts not deployed");

		return _deploy(accessHubAddress, voterAddress, treasuryAddress, pairFactoryAddress);
	}

	function forTest(
		address _accessHubAddress,
		address _voterAddress,
		address _treasuryAddress,
		address _pairFactoryAddress
	) public returns (address, address, address, address, address, address, address, address) {
		return _deploy(_accessHubAddress, _voterAddress, _treasuryAddress, _pairFactoryAddress);
	}

	function _deploy(
		address _accessHubAddress,
		address _voterAddress,
		address _treasuryAddress,
		address _pairFactoryAddress
	) internal returns (address, address, address, address, address, address, address, address) {
		vm.startBroadcast(config.deployer);

		RamsesV3Factory clPoolFactory = new RamsesV3Factory(
			address(_accessHubAddress),
			config.deployer
		);

		RamsesV3PoolDeployer clPoolDeployer = new RamsesV3PoolDeployer(address(clPoolFactory));

		clPoolFactory.initialize(address(clPoolDeployer));

		NonfungibleTokenPositionDescriptor nfpDescriptor = new NonfungibleTokenPositionDescriptor(
			config.WETH
		);

		NonfungiblePositionManager nfpManager = new NonfungiblePositionManager(
			address(clPoolDeployer),
			config.WETH,
			address(nfpDescriptor),
			address(_accessHubAddress)
		);

		SwapRouter swapRouter = new SwapRouter(address(clPoolDeployer), config.WETH);

		//TODO: update parameters in the future
		RouterParameters memory routerParameters = RouterParameters({
			permit2: config.permit2,
			weth9: config.WETH,
			seaportV1_5: address(0),
			seaportV1_4: address(0),
			openseaConduit: address(0),
			nftxZap: address(0),
			x2y2: address(0),
			foundation: address(0),
			sudoswap: address(0),
			elementMarket: address(0),
			nft20Zap: address(0),
			cryptopunks: address(0),
			looksRareV2: address(0),
			routerRewardsDistributor: address(0),
			looksRareRewardsDistributor: address(0),
			looksRareToken: address(0),
			v2Factory: _pairFactoryAddress,
			v3Factory: address(clPoolFactory),
			pairInitCodeHash: keccak256(type(Pair).creationCode),
			poolInitCodeHash: keccak256(type(RamsesV3Pool).creationCode)
		});
		UniversalRouter universalRouter = new UniversalRouter(routerParameters);

		FeeCollector clFeeCollector = new FeeCollector(
			address(_treasuryAddress),
			address(_voterAddress)
		);

		ClGaugeFactory clGaugeFactory = new ClGaugeFactory(
			address(nfpManager),
			address(_voterAddress),
			address(clFeeCollector)
		);

		QuoterV2 quoter = new QuoterV2(address(clPoolDeployer), config.WETH);

		TickLens tickLens = new TickLens();

		vm.stopBroadcast();

		return (
			address(clPoolFactory),
			address(clPoolDeployer),
			address(clGaugeFactory),
			address(clFeeCollector),
			address(nfpManager),
			address(nfpDescriptor),
			address(swapRouter),
			address(universalRouter)
		);
	}
}
