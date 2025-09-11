// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Pair} from "contracts/legacy/Pair.sol";
import {RamsesV3Pool} from "contracts/CL/core/RamsesV3Pool.sol";
import "contracts/universalRouter/UniversalRouter.sol";

import "./Helper.s.sol";

contract DeployURouterScript is Script {
	Helper.Config public config;
	Helper public helper;

	constructor() {
		helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function run() public returns (address) {
		address _v2Factory = helper.readAddress("PairFactory");
		address _v3Factory = helper.readAddress("CLPoolFactory");
		address _v3NFTPositionManager = helper.readAddress("NFPManager");

		if (
			_v2Factory == address(0) ||
			_v3Factory == address(0) ||
			_v3NFTPositionManager == address(0)
		) revert("Core Contracts not deployed");

		return _deploy(_v2Factory, _v3Factory, _v3NFTPositionManager);
	}

	function forTest(
		address _v2Factory,
		address _v3Factory,
		address _v3NFTPositionManager
	) public returns (address) {
		return _deploy(_v2Factory, _v3Factory, _v3NFTPositionManager);
	}

	function _deploy(
		address _v2Factory,
		address _v3Factory,
		address _v3NFTPositionManager
	) internal returns (address) {
		vm.startBroadcast(config.deployer);

		RouterParameters memory params = RouterParameters({
			permit2: config.permit2,
			weth9: config.WETH,
			v2Factory: _v2Factory,
			v3Factory: _v3Factory,
			pairInitCodeHash: keccak256(type(Pair).creationCode),
			poolInitCodeHash: keccak256(type(RamsesV3Pool).creationCode),
			v4PoolManager: config.v4PoolManager,
			v3NFTPositionManager: _v3NFTPositionManager,
			v4PositionManager: config.v4PositionManager
		});

		UniversalRouter router = new UniversalRouter(params);

		vm.stopBroadcast();

		return (address(router));
	}
}
