// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FeeDistributor} from "contracts/legacy/FeeDistributor.sol";
import {IFeeDistributorFactory} from "contracts/interfaces/IFeeDistributorFactory.sol";

contract FeeDistributorFactory is IFeeDistributorFactory {
	address public lastFeeDistributor;

	function createFeeDistributor(address feeRecipient) external returns (address) {
		lastFeeDistributor = address(new FeeDistributor(msg.sender, feeRecipient));

		return lastFeeDistributor;
	}
}
