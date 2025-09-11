// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {INonfungiblePositionManager} from "contracts/CL/periphery/interfaces/INonfungiblePositionManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

struct MigratorParameters {
	address v3PositionManager;
	address v4PositionManager;
}

/// @title Migrator Immutables
/// @notice Immutable state for liquidity-migration contracts
contract MigratorImmutables {
	INonfungiblePositionManager public immutable V3_POSITION_MANAGER;
	IPositionManager public immutable V4_POSITION_MANAGER;

	constructor(MigratorParameters memory params) {
		V3_POSITION_MANAGER = INonfungiblePositionManager(params.v3PositionManager);
		V4_POSITION_MANAGER = IPositionManager(params.v4PositionManager);
	}
}
