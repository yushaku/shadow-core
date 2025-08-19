// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeRecipientFactory} from "contracts/interfaces/IFeeRecipientFactory.sol";
import {FeeRecipient} from "contracts/legacy/FeeRecipient.sol";

contract FeeRecipientFactory is IFeeRecipientFactory {
	address public immutable voter;

	address public lastFeeRecipient;
	address public treasury;
	address public accessHub;
	uint256 public feeToTreasury;

	mapping(address pair => address feeRecipient) public feeRecipientForPair;

	event SetFeeToTreasury(uint256 indexed feeToTreasury);

	modifier onlyGovernance() {
		require(msg.sender == accessHub);
		_;
	}

	constructor(address _treasury, address _voter, address _accessHub) {
		treasury = _treasury;
		voter = _voter;
		accessHub = _accessHub;
		/// @dev start at 8%
		feeToTreasury = 800;
	}

	/// @inheritdoc IFeeRecipientFactory
	function createFeeRecipient(address pair) external returns (address _feeRecipient) {
		require(msg.sender == voter, NOT_AUTHORIZED());

		_feeRecipient = address(new FeeRecipient(pair, msg.sender, address(this)));
		feeRecipientForPair[pair] = _feeRecipient;
		lastFeeRecipient = _feeRecipient;
	}

	/// @inheritdoc IFeeRecipientFactory
	function setFeeToTreasury(uint256 _feeToTreasury) external onlyGovernance {
		require(_feeToTreasury <= 10_000, INVALID_TREASURY_FEE());

		feeToTreasury = _feeToTreasury;
		emit SetFeeToTreasury(_feeToTreasury);
	}

	/// @inheritdoc IFeeRecipientFactory
	function setTreasury(address _treasury) external onlyGovernance {
		treasury = _treasury;
	}
}
