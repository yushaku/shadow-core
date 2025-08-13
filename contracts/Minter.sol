// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20Extended} from "./interfaces/IERC20Extended.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IVoter} from "./interfaces/IVoter.sol";

contract Minter is IMinter {
	/// @notice emissions value
	uint256 public weeklyEmissions;
	/// @notice controls emissions growth or decay
	uint256 public emissionsMultiplier;
	/// @notice unix timestamp of the first period
	uint256 public firstPeriod;
	/// @notice currently active unix timestamp of epoch start
	uint256 public activePeriod;
	/// @notice the last period the emissions multiplier was updated
	uint256 public lastMultiplierUpdate;

	/// @notice basis invariant 10_000 = 100%
	uint256 public constant BASIS = 10_000;
	/// @notice max deviation of 20% per epoch
	uint256 public constant MAX_DEVIATION = 2_000;
	/// @notice initial supply of 3m ysk
	uint256 public constant INITIAL_SUPPLY = 3_000_000 * 1e18;
	/// @notice max supply of 10m ysk
	uint256 public constant MAX_SUPPLY = 10_000_000 * 1e18;

	address public operator;
	address public accessHub;
	address public voter;
	address public xYSK;
	IERC20Extended public ysk;

	modifier onlyGovernance() {
		require(msg.sender == accessHub, IVoter.NOT_AUTHORIZED(msg.sender));
		_;
	}

	constructor(address _accessHub, address _operator) {
		accessHub = _accessHub;
		operator = _operator;
	}

	/// @inheritdoc IMinter
	function kickoff(
		address _ysk,
		address _voter,
		uint256 _initialWeeklyEmissions,
		uint256 _initialMultiplier,
		address _xYSK
	) external {
		if (msg.sender != operator) revert IVoter.NOT_AUTHORIZED(msg.sender);
		/// @dev ensure the emissions token isn't set yet
		if (address(ysk) != address(0)) revert STARTED();
		if (_xYSK == address(0)) revert INVALID_CONTRACT();
		if (_voter == address(0)) revert INVALID_CONTRACT();
		if (_ysk == address(0)) revert INVALID_CONTRACT();

		ysk = IERC20Extended(_ysk);
		xYSK = _xYSK;
		voter = _voter;
		weeklyEmissions = _initialWeeklyEmissions;
		emissionsMultiplier = _initialMultiplier;
		emit SetVoter(_voter);

		ysk.mint(operator, INITIAL_SUPPLY);
	}

	/// @inheritdoc IMinter
	function updatePeriod() external returns (uint256 period) {
		if (firstPeriod == 0) revert EMISSIONS_NOT_STARTED();

		period = activePeriod;
		/// @dev if >= Thursday 0 UTC
		if (getPeriod() > period) {
			/// @dev fetch the current period
			period = getPeriod();
			/// @dev set the active period to the new period
			activePeriod = period;
			/// @dev calculate the weekly emissions
			uint256 _weeklyEmissions = calculateWeeklyEmissions();
			/// @dev set global value to the above calculated emissions
			weeklyEmissions = _weeklyEmissions;
			/// @dev if supply cap was not already hit
			if (weeklyEmissions > 0) {
				/// @dev mint emissions to the Minter contract
				ysk.mint(address(this), _weeklyEmissions);
				/// @dev approvals for ysk on voter
				ysk.approve(voter, _weeklyEmissions);

				/// @dev notify emissions to the voter contract
				IVoter(voter).notifyRewardAmount(_weeklyEmissions);
				/// @dev fetch the data from encoding
				bytes memory data = abi.encodeWithSignature("rebase()");
				/// @dev call the rebase function
				(bool success, ) = xYSK.call(data);
				/// @dev if the rebase fails, emit to help with tracing
				/// @dev we do not revert as this can be intended behavior
				if (!success) emit RebaseUnsuccessful(block.timestamp, activePeriod);
				/// @dev emit the weekly emissions minted
				emit Mint(msg.sender, _weeklyEmissions);
			}
		}
	}

	/// @inheritdoc IMinter
	function startEmissions() external {
		/// @dev ensure only the operator can start the emissions
		require(msg.sender == operator, IVoter.NOT_AUTHORIZED(msg.sender));
		/// @dev ensure epoch 0 has not started yet
		require(firstPeriod == 0, STARTED());
		/// @dev set the active period to the current
		activePeriod = getPeriod();
		/// @dev set the last update as the last period so emissions can be updated once if needed
		lastMultiplierUpdate = activePeriod - 1;
		/// @dev set the first period to the active period
		firstPeriod = activePeriod;
		/// @dev mints the epoch 0 emissions for manual distribution
		ysk.mint(operator, weeklyEmissions);
	}

	/// @inheritdoc IMinter
	function updateEmissionsMultiplier(uint256 _emissionsMultiplier) external onlyGovernance {
		/// @dev ensure that the last time the multiplier was updated was not the same period
		require(lastMultiplierUpdate != activePeriod, SAME_PERIOD());

		/// @dev set the last update to the current period
		lastMultiplierUpdate = activePeriod;
		/// @dev ensure the multiplier actually is diff
		require(emissionsMultiplier != _emissionsMultiplier, NO_CHANGE());
		/// @dev placeholder for deviation
		uint256 deviation;
		/// @dev check which way to subtract
		deviation = emissionsMultiplier > _emissionsMultiplier
			? (emissionsMultiplier - _emissionsMultiplier)
			: (_emissionsMultiplier - emissionsMultiplier);
		/// @dev require deviation is not above 20% per epoch
		require(deviation <= MAX_DEVIATION, TOO_HIGH());
		/// @dev set new values
		emissionsMultiplier = _emissionsMultiplier;

		emit EmissionsMultiplierUpdated(_emissionsMultiplier);
	}

	/// @inheritdoc IMinter
	function calculateWeeklyEmissions() public view returns (uint256) {
		/// @dev fetch proposed emissions
		uint256 _weeklyEmissions = (weeklyEmissions * emissionsMultiplier) / BASIS;
		/// @dev if it's zero
		if (_weeklyEmissions == 0) return 0;
		/// @dev if minting goes over the max supply
		if (ysk.totalSupply() + _weeklyEmissions > MAX_SUPPLY) {
			/// @dev update value to difference
			_weeklyEmissions = MAX_SUPPLY - ysk.totalSupply();
		}
		return _weeklyEmissions;
	}

	function getPeriod() public view returns (uint256 period) {
		period = block.timestamp / 1 weeks;
	}

	function getEpoch() public view returns (uint256 _epoch) {
		return getPeriod() - firstPeriod;
	}
}
