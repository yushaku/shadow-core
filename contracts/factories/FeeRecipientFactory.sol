// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeRecipientFactory} from "../interfaces/IFeeRecipientFactory.sol";
import {FeeRecipient} from "./../FeeRecipient.sol";

contract FeeRecipientFactory is IFeeRecipientFactory {
    /// @inheritdoc IFeeRecipientFactory
    address public lastFeeRecipient;

    /// @inheritdoc IFeeRecipientFactory
    address public treasury;

    address public accessHub;

    address public immutable voter;

    /// @inheritdoc IFeeRecipientFactory
    uint256 public feeToTreasury;

    /// @inheritdoc IFeeRecipientFactory
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
    function createFeeRecipient(
        address pair
    ) external returns (address _feeRecipient) {
        /// @dev ensure caller is the voter
        require(msg.sender == voter, NOT_AUTHORIZED());
        /// @dev create a new feeRecipient
        _feeRecipient = address(
            new FeeRecipient(pair, msg.sender, address(this))
        );
        /// @dev dont need to ensure that a feeRecipient wasn't already made previously
        feeRecipientForPair[pair] = _feeRecipient;
        lastFeeRecipient = _feeRecipient;
    }
    /// @inheritdoc IFeeRecipientFactory
    function setFeeToTreasury(uint256 _feeToTreasury) external onlyGovernance {
        /// @dev ensure fee to treasury isn't too high
        require(_feeToTreasury <= 10_000, INVALID_TREASURY_FEE());
        feeToTreasury = _feeToTreasury;
        emit SetFeeToTreasury(_feeToTreasury);
    }

    /// @inheritdoc IFeeRecipientFactory
    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }
}
