// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IFeeDistributor} from "contracts/interfaces/IFeeDistributor.sol";
import {IFeeRecipient} from "contracts/interfaces/IFeeRecipient.sol";
import {IFeeRecipientFactory} from "contracts/interfaces/IFeeRecipientFactory.sol";

/**
 * @notice Pair Fees contract is used as a 1:1 PAIR relationship to split out fees,
 * this ensures that the curve does not need to be modified for LP shares
 */
contract FeeRecipient is IFeeRecipient {
	address public immutable FEE_RECIPIENT_FACTORY;
	address public immutable PAIR;
	address public immutable VOTER;

	address public feeDistributor;

	constructor(address _pair, address _voter, address _feeRecipientFactory) {
		PAIR = _pair;
		VOTER = _voter;
		FEE_RECIPIENT_FACTORY = _feeRecipientFactory;
	}

	/**
	 * @dev only called by the voter.sol
	 * @notice initialize the FeeRecipient contract and approve the LP tokens to the feeDist, gated to VOTER
	 * @param _feeDistributor the feeDistributor contract address
	 */
	function initialize(address _feeDistributor) external {
		require(msg.sender == VOTER, NOT_AUTHORIZED());

		feeDistributor = _feeDistributor;
		IERC20(PAIR).approve(_feeDistributor, type(uint256).max);
	}

	/**
	 * @dev only called by the voter.sol
	 * @notice notifies the fees
	 * it will share the fees to treasury + FeeDistributor
	 */
	function notifyFees() external {
		require(msg.sender == VOTER, NOT_AUTHORIZED());

		uint256 amount = IERC20(PAIR).balanceOf(address(this));
		if (amount == 0) return;

		uint256 feeToTreasury = IFeeRecipientFactory(FEE_RECIPIENT_FACTORY).feeToTreasury();
		if (feeToTreasury > 0) {
			address treasury = IFeeRecipientFactory(FEE_RECIPIENT_FACTORY).treasury();
			uint256 amountToTreasury = (amount * feeToTreasury) / 10_000;
			amount -= amountToTreasury;
			IERC20(PAIR).transfer(treasury, amountToTreasury);
		}

		if (amount > 0) {
			IFeeDistributor(feeDistributor).notifyRewardAmount(PAIR, amount);
		}
	}
}
