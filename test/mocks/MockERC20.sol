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


contract TaxToken is MockERC20 {
    uint256 public constant TAX_RATE = 100; // 1% tax
    uint256 public constant TAX_DENOMINATOR = 10_000;

    constructor() MockERC20("TaxtToken", "TXT", 18) {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * TAX_RATE) / TAX_DENOMINATOR;
        uint256 amountAfterTax = amount - tax;
        super.transfer(address(this), tax);
        return super.transfer(to, amountAfterTax);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * TAX_RATE) / TAX_DENOMINATOR;
        uint256 amountAfterTax = amount - tax;
        super.transferFrom(from, address(this), tax);
        return super.transferFrom(from, to, amountAfterTax);
    }
}

