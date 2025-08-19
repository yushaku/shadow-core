// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	uint8 public immutable DECIMALS;

	constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
		DECIMALS = _decimals;
	}

	function mint(address to, uint256 amount) external {
		_mint(to, amount);
	}

	function decimals() public view virtual override returns (uint8) {
		return DECIMALS;
	}
}
