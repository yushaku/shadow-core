// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20Extended} from "./interfaces/IERC20Extended.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IVoter} from "./interfaces/IVoter.sol";

contract Minter is IMinter {
	uint256 public weeklyEmissions;
	/// @notice controls emissions growth or decay
	uint256 public emissionsMultiplier;

	uint256 public firstPeriod;
	uint256 public activePeriod;
	uint256 public lastMultiplierUpdate;

	/// @notice basis invariant 10_000 = 100%
	uint256 public constant BASIS = 10_000;
	/// @notice max deviation of 20% per epoch
	uint256 public constant MAX_DEVIATION = 2_000;
	/// @notice initial supply of 3m YSK
	uint256 public constant INITIAL_SUPPLY = 3_000_000 * 1e18;
	/// @notice max supply of 10m YSK
	uint256 public constant MAX_SUPPLY = 10_000_000 * 1e18;

	address public operator;
	address public accessHub;
	address public voter;
	address public xYSK;
	IERC20Extended public ysk;

	modifier onlyGovernance() {
		require(msg.sender == accessHub, NOT_AUTHORIZED(msg.sender));
		_;
	}

	constructor(address _accessHub, address _operator) {
		accessHub = _accessHub;
		operator = _operator;
	}

	/***************************************************************************************/
	/* User Functions */
	/***************************************************************************************/

	/// @inheritdoc IMinter
	function updatePeriod() external returns (uint256 period) {
		if (firstPeriod == 0) revert EMISSIONS_NOT_STARTED();

		period = activePeriod;
		/// @dev if >= Thursday 0 UTC
		if (getPeriod() > period) {
			period = getPeriod();
			activePeriod = period;

			uint256 _weeklyEmissions = calculateWeeklyEmissions();
			weeklyEmissions = _weeklyEmissions;

			/// @dev if supply cap was not already hit
			if (weeklyEmissions > 0) {
				/// @dev mint EMISSIONS to this contract
				ysk.mint(address(this), _weeklyEmissions);
				ysk.approve(voter, _weeklyEmissions);

				/// @dev notify EMISSIONS to the voter contract
				IVoter(voter).notifyRewardAmount(_weeklyEmissions);
				bytes memory data = abi.encodeWithSignature("rebase()");
				(bool success, ) = xYSK.call(data);
				if (!success) emit RebaseUnsuccessful(block.timestamp, activePeriod);

				/// @dev emit the weekly emissions minted
				emit Mint(msg.sender, _weeklyEmissions);
			}
		}
	}

	/***************************************************************************************/
	/* Authorized Functions */
	/***************************************************************************************/

	/// @inheritdoc IMinter
	function kickoff(
		address _ysk,
		address _voter,
		uint256 _initialWeeklyEmissions,
		uint256 _initialMultiplier,
		address _xYSK
	) external {
		if (msg.sender != operator) revert NOT_AUTHORIZED(msg.sender);

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
	function startEmissions() external {
		require(msg.sender == operator, NOT_AUTHORIZED(msg.sender));
		require(firstPeriod == 0, STARTED());

		activePeriod = getPeriod();
		lastMultiplierUpdate = activePeriod - 1;
		firstPeriod = activePeriod;

		ysk.mint(operator, weeklyEmissions);
	}

	/// @inheritdoc IMinter
	function updateEmissionsMultiplier(uint256 _emissionsMultiplier) external onlyGovernance {
		require(lastMultiplierUpdate != activePeriod, SAME_PERIOD());
		require(emissionsMultiplier != _emissionsMultiplier, NO_CHANGE());

		/// @dev set the last update to the current period
		lastMultiplierUpdate = activePeriod;

		uint256 deviation;
		deviation = emissionsMultiplier > _emissionsMultiplier
			? (emissionsMultiplier - _emissionsMultiplier)
			: (_emissionsMultiplier - emissionsMultiplier);

		/// @dev require deviation is not above 20% per epoch
		require(deviation <= MAX_DEVIATION, TOO_HIGH());
		emissionsMultiplier = _emissionsMultiplier;

		emit EmissionsMultiplierUpdated(_emissionsMultiplier);
	}

	/**
	 * @notice transfer the operator to a new address
	 * @param _newOperator the new operator
	 */
	function transferOperator(address _newOperator) external {
		if (operator != _newOperator) revert NOT_AUTHORIZED(msg.sender);
		operator = _newOperator;
		emit SetOperator(_newOperator);
	}

	/***************************************************************************************/
	/* View Functions */
	/***************************************************************************************/

	/**
	 * @notice calculates the emissions to be sent to the voter
	 * @return the amount of emissions for the week
	 */
	function calculateWeeklyEmissions() public view returns (uint256) {
		uint256 _weeklyEmissions = (weeklyEmissions * emissionsMultiplier) / BASIS;

		if (_weeklyEmissions == 0) return 0;
		if (ysk.totalSupply() + _weeklyEmissions > MAX_SUPPLY) {
			_weeklyEmissions = MAX_SUPPLY - ysk.totalSupply();
		}

		return _weeklyEmissions;
	}

	function getPeriod() public view returns (uint256) {
		return block.timestamp / 1 weeks;
	}

	function getEpoch() public view returns (uint256 _epoch) {
		return getPeriod() - firstPeriod;
	}
}
