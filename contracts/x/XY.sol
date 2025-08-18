// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IXY} from "contracts/interfaces/IXY.sol";
import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";

/**
 * @title XY
 * @notice is the voting escrow token for the Yushaku ecosystem.
 * @dev 1 YSK = 1 xYushaku
 */
contract XY is IXY, ERC20, Pausable {
	using EnumerableSet for EnumerableSet.AddressSet;
	uint256 public constant BASIS = 10_000;
	uint256 public constant SLASHING_PENALTY = 5000;
	uint256 public constant MIN_VEST = 14 days;
	uint256 public constant MAX_VEST = 180 days;

	address public immutable MINTER;
	address public immutable ACCESS_HUB;
	address public immutable VOTE_MODULE;
	IERC20 public immutable YSK;
	IVoter public immutable VOTER;

	address public operator;

	EnumerableSet.AddressSet exempt;
	EnumerableSet.AddressSet exemptTo;

	uint256 public lastDistributedPeriod;
	uint256 public pendingRebase;

	mapping(address => VestPosition[]) public vestInfo;

	modifier onlyGovernance() {
		require(msg.sender == ACCESS_HUB, IVoter.NOT_AUTHORIZED(msg.sender));
		_;
	}

	constructor(
		address _ysk,
		address _voter,
		address _operator,
		address _accessHub,
		address _voteModule,
		address _minter
	) ERC20("xYushaku", "xY") {
		YSK = IERC20(_ysk);
		VOTER = IVoter(_voter);
		MINTER = _minter;
		operator = _operator;
		ACCESS_HUB = _accessHub;
		VOTE_MODULE = _voteModule;

		/// @dev exempt voter, operator, and the vote module
		exempt.add(_voter);
		exempt.add(operator);
		exempt.add(VOTE_MODULE);

		exemptTo.add(VOTE_MODULE);

		/// @dev grab current period from voter
		lastDistributedPeriod = IVoter(_voter).getPeriod();
	}

	function pause() external onlyGovernance {
		_pause();
	}

	function unpause() external onlyGovernance {
		_unpause();
	}

	/*****************************************************************/
	// ERC20 Overrides and Helpers
	/*****************************************************************/

	function _update(address from, address to, uint256 value) internal override {
		/* cases we account for:
		 *
		 * minting and burning
		 * if the "to" is part of the special exemptions
		 * withdraw and deposit calls
		 * if "from" is a gauge or feeDist
		 *
		 */

		uint8 _u;
		if (_isExempted(from, to)) {
			_u = 1;
		} else if (VOTER.isGauge(from) || VOTER.isFeeDistributor(from)) {
			/// @dev add to the exempt set
			exempt.add(from);
			_u = 1;
		}
		/// @dev if all previous checks are passed
		require(_u == 1, NOT_WHITELISTED(from));
		/// @dev call parent function
		super._update(from, to, value);
	}

	/// @dev internal check for the transfer whitelist
	function _isExempted(address _from, address _to) internal view returns (bool) {
		return (exempt.contains(_from) ||
			_from == address(0) ||
			_to == address(0) ||
			exemptTo.contains(_to));
	}

	/*****************************************************************/
	// General use functions
	/*****************************************************************/

	/// @notice converts 1 YSK to 1 xYushaku
	/// @param _amount amount of YSK to convert
	function convertEmissionsToken(uint256 _amount) external whenNotPaused {
		if (_amount == 0) revert ZERO();

		YSK.transferFrom(msg.sender, address(this), _amount);
		_mint(msg.sender, _amount);
		emit Converted(msg.sender, _amount);
	}

	function rebase() external whenNotPaused {
		require(msg.sender == MINTER, NOT_MINTER());

		uint256 period = VOTER.getPeriod();
		if (period > lastDistributedPeriod && pendingRebase >= BASIS) {
			lastDistributedPeriod = period;
			uint256 _temp = pendingRebase;
			pendingRebase = 0;
			emit Rebase(msg.sender, _temp);

			YSK.approve(VOTE_MODULE, _temp);
			IVoteModule(VOTE_MODULE).notifyRewardAmount(_temp);
		}
	}

	function exit(uint256 _amount) external whenNotPaused returns (uint256 exitAmount) {
		if (_amount == 0) revert ZERO();
		_burn(msg.sender, _amount);

		/// @dev if it's at least 2 wei it will give a penalty
		uint256 penalty = ((_amount * SLASHING_PENALTY) / BASIS);
		pendingRebase += penalty;

		exitAmount = _amount - penalty;
		YSK.transfer(msg.sender, exitAmount);

		emit InstantExit(msg.sender, exitAmount);
	}

	function createVest(uint256 _amount) external whenNotPaused {
		if (_amount == 0) revert ZERO();
		_burn(msg.sender, _amount);

		uint256 vestLength = vestInfo[msg.sender].length;
		vestInfo[msg.sender].push(
			VestPosition(_amount, block.timestamp, block.timestamp + MAX_VEST, vestLength)
		);

		emit NewVest(msg.sender, vestLength, _amount);
	}

	function exitVest(uint256 _vestID) external whenNotPaused {
		VestPosition storage _vest = vestInfo[msg.sender][_vestID];
		require(_vest.amount != 0, NO_VEST());

		/// @dev store amount in the vest and start time
		uint256 _amount = _vest.amount;
		uint256 _start = _vest.start;
		/// @dev zero out the amount before anything else as a safety measure
		_vest.amount = 0;

		/// @dev case: vest has not crossed the minimum vesting threshold
		/// @dev mint cancelled xShadow back to msg.sender
		if (block.timestamp < _start + MIN_VEST) {
			_mint(msg.sender, _amount);
			emit CancelVesting(msg.sender, _vestID, _amount);
		}
		/// @dev case: vest is complete
		/// @dev send liquid Shadow to msg.sender
		else if (_vest.maxEnd <= block.timestamp) {
			YSK.transfer(msg.sender, _amount);
			emit ExitVesting(msg.sender, _vestID, _amount);
		}
		/// @dev case: vest is in progress
		/// @dev calculate % earned based on length of time that has vested
		/// @dev linear calculations
		else {
			/// @dev the base to start at (50%)
			uint256 base = (_amount * (SLASHING_PENALTY)) / BASIS;
			/// @dev calculate the extra earned via vesting
			uint256 vestEarned = ((_amount *
				(BASIS - SLASHING_PENALTY) *
				(block.timestamp - _start)) / MAX_VEST) / BASIS;

			uint256 exitedAmount = base + vestEarned;
			/// @dev add to the existing pendingRebases
			pendingRebase += (_amount - exitedAmount);
			/// @dev transfer underlying to the sender after penalties removed
			YSK.transfer(msg.sender, exitedAmount);
			emit ExitVesting(msg.sender, _vestID, _amount);
		}
	}

	/*****************************************************************/
	/* Permissions functions */
	/* timelock/operator gated */
	/*****************************************************************/

	function operatorRedeem(uint256 _amount) external onlyGovernance {
		_burn(operator, _amount);
		YSK.transfer(operator, _amount);
		emit XYskRedeemed(address(this), _amount);
	}

	function rescueTrappedTokens(
		address[] calldata _tokens,
		uint256[] calldata _amounts
	) external onlyGovernance {
		for (uint256 i = 0; i < _tokens.length; ++i) {
			/// @dev cant fetch the underlying
			require(_tokens[i] != address(YSK), CANT_RESCUE());
			IERC20(_tokens[i]).transfer(operator, _amounts[i]);
		}
	}

	function migrateOperator(address _operator) external onlyGovernance {
		/// @dev ensure operator is different
		require(operator != _operator, NO_CHANGE());
		emit NewOperator(operator, _operator);
		operator = _operator;
	}

	function setExemption(
		address[] calldata _exemptee,
		bool[] calldata _exempt
	) external onlyGovernance {
		/// @dev ensure arrays of same length
		require(_exemptee.length == _exempt.length, ARRAY_LENGTHS());
		/// @dev loop through all and attempt add/remove based on status
		for (uint256 i = 0; i < _exempt.length; ++i) {
			bool success = _exempt[i] ? exempt.add(_exemptee[i]) : exempt.remove(_exemptee[i]);
			/// @dev emit : (who, status, success)
			emit Exemption(_exemptee[i], _exempt[i], success);
		}
	}

	function setExemptionTo(
		address[] calldata _exemptee,
		bool[] calldata _exempt
	) external onlyGovernance {
		/// @dev ensure arrays of same length
		require(_exemptee.length == _exempt.length, ARRAY_LENGTHS());

		/// @dev loop through all and attempt add/remove based on status
		for (uint256 i = 0; i < _exempt.length; ++i) {
			bool success = _exempt[i] ? exemptTo.add(_exemptee[i]) : exemptTo.remove(_exemptee[i]);

			/// @dev emit : (who, status, success)
			emit Exemption(_exemptee[i], _exempt[i], success);
		}
	}

	/*****************************************************************/
	/* View functions */
	/*****************************************************************/

	/// @dev simply returns the balance of the underlying
	function getBalanceResiding() public view returns (uint256 _amount) {
		return YSK.balanceOf(address(this));
	}

	function usersTotalVests(address _who) public view returns (uint256 _length) {
		return vestInfo[_who].length;
	}

	function getVestInfo(address _who, uint256 _vestID) public view returns (VestPosition memory) {
		return vestInfo[_who][_vestID];
	}

	function isExempt(address _who) external view returns (bool _exempt) {
		return exempt.contains(_who);
	}
}
