// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FeeDistributor} from "./../FeeDistributor.sol";

contract FeeDistributorFactory {
    address public lastFeeDistributor;

    function createFeeDistributor(
        address feeRecipient
    ) external returns (address) {
        lastFeeDistributor = address(
            new FeeDistributor(msg.sender, feeRecipient)
        );

        return lastFeeDistributor;
    }
}
