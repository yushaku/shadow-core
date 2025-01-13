// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title EmissionsToken contract for Shadow
/// @dev standard mintable ERC20 built for vote-governance emissions
contract Shadow is ERC20, ERC20Burnable, ERC20Permit {
    error NOT_MINTER();
    /// @notice minter contract address
    address public minter;

    constructor(
        address _minter
    ) ERC20("Shadow", "SHADOW") ERC20Permit("Shadow") {
        minter = _minter;
    }

    /// @notice mint function called by minter weekly
    /// @param to the address to mint to
    /// @param amount amount of tokens
    function mint(address to, uint256 amount) public {
        require(msg.sender == minter, NOT_MINTER());
        _mint(to, amount);
    }
}
