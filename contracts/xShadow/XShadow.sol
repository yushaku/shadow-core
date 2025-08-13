// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVoter} from "../interfaces/IVoter.sol";
import {IRamsesV3Pool} from "../CL/core/interfaces/IRamsesV3Pool.sol";
import {IXShadow} from "../interfaces/IXShadow.sol";
import {IVoteModule} from "../interfaces/IVoteModule.sol";

contract XShadow is ERC20, IXShadow, Pausable {
	using EnumerableSet for EnumerableSet.AddressSet;
	uint256 public constant BASIS = 10_000;
	uint256 public constant SLASHING_PENALTY = 5000;
	uint256 public constant MIN_VEST = 14 days;
	uint256 public constant MAX_VEST = 180 days;

	address public immutable MINTER;
	address public immutable ACCESS_HUB;
	address public immutable VOTE_MODULE;
	IERC20 public immutable SHADOW;
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
		address _shadow,
		address _voter,
		address _operator,
		address _accessHub,
		address _voteModule,
		address _minter
	) ERC20("xShadow", "xSHADOW") {
		SHADOW = IERC20(_shadow);
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

	function convertEmissionsToken(uint256 _amount) external whenNotPaused {
		/// @dev ensure the _amount is > 0
		require(_amount != 0, ZERO());
		/// @dev transfer from the caller to this address
		SHADOW.transferFrom(msg.sender, address(this), _amount);
		/// @dev mint the xSHADOW to the caller
		_mint(msg.sender, _amount);
		/// @dev emit an event for conversion
		emit Converted(msg.sender, _amount);
	}

	function rebase() external whenNotPaused {
		/// @dev gate to minter and call it on epoch flips
		require(msg.sender == MINTER, NOT_MINTER());
		/// @dev fetch the current period
		uint256 period = VOTER.getPeriod();
		/// @dev if it's a new period (epoch)
		if (
			period > lastDistributedPeriod &&
			/// @dev if the rebase is greater than the Basis
			pendingRebase >= BASIS
		) {
			/// @dev PvP rebase notified to the voteModule staking contract to stream to xSHADOW
			/// @dev fetch the current period from voter
			lastDistributedPeriod = period;
			/// @dev store the rebase
			uint256 _temp = pendingRebase;
			/// @dev zero it out
			pendingRebase = 0;
			/// @dev approve SHADOW transferring to voteModule
			SHADOW.approve(VOTE_MODULE, _temp);
			/// @dev notify the SHADOW rebase
			IVoteModule(VOTE_MODULE).notifyRewardAmount(_temp);
			emit Rebase(msg.sender, _temp);
		}
	}

	function exit(uint256 _amount) external whenNotPaused returns (uint256 _exitedAmount) {
		/// @dev cannot exit a 0 amount
		require(_amount != 0, ZERO());
		/// @dev if it's at least 2 wei it will give a penalty
		uint256 penalty = ((_amount * SLASHING_PENALTY) / BASIS);
		uint256 exitAmount = _amount - penalty;

		/// @dev burn the xShadow from the caller's address
		_burn(msg.sender, _amount);

		/// @dev store the rebase earned from the penalty
		pendingRebase += penalty;

		/// @dev transfer the exitAmount to the caller
		SHADOW.transfer(msg.sender, exitAmount);
		/// @dev emit actual exited amount
		emit InstantExit(msg.sender, exitAmount);
		return exitAmount;
	}

	function createVest(uint256 _amount) external whenNotPaused {
		/// @dev ensure not 0
		require(_amount != 0, ZERO());
		/// @dev preemptive burn
		_burn(msg.sender, _amount);
		/// @dev fetch total length of vests
		uint256 vestLength = vestInfo[msg.sender].length;
		/// @dev push new position
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
			SHADOW.transfer(msg.sender, _amount);
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
			SHADOW.transfer(msg.sender, exitedAmount);
			emit ExitVesting(msg.sender, _vestID, _amount);
		}
	}

	/*****************************************************************/
	// Permissions functions,
	// timelock/operator gated
	/*****************************************************************/

	function operatorRedeem(uint256 _amount) external onlyGovernance {
		_burn(operator, _amount);
		SHADOW.transfer(operator, _amount);
		emit XShadowRedeemed(address(this), _amount);
	}

	function rescueTrappedTokens(
		address[] calldata _tokens,
		uint256[] calldata _amounts
	) external onlyGovernance {
		for (uint256 i = 0; i < _tokens.length; ++i) {
			/// @dev cant fetch the underlying
			require(_tokens[i] != address(SHADOW), CANT_RESCUE());
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
	// Getter functions
	/*****************************************************************/

	/// @dev simply returns the balance of the underlying
	function getBalanceResiding() public view returns (uint256 _amount) {
		return SHADOW.balanceOf(address(this));
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

	function shadow() external view returns (address) {
		return address(SHADOW);
	}
}
