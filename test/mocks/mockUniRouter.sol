// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {ERC721} from "solmate/src/tokens/ERC721.sol";
import {ERC6909} from "@uniswap/v4-core/src/ERC6909.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract ExampleModule {
	event ExampleModuleEvent(string message);

	error CauseRevert();

	function logEvent() public {
		emit ExampleModuleEvent("testEvent");
	}

	function causeRevert() public pure {
		revert CauseRevert();
	}
}

// this contract only exists to pull PositionManager and PoolManager into the hardhat build pipeline
// so that typechain artifacts are generated for it
abstract contract ImportsForTypechain is PositionManager, PoolManager {
	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC6909, ERC721) returns (bool) {
		return super.supportsInterface(interfaceId);
	}
}

contract MintableERC20 is ERC20 {
	constructor(uint256 amountToMint) ERC20("test", "TEST", 18) {
		mint(msg.sender, amountToMint);
	}

	function mint(address to, uint256 amount) public {
		balanceOf[to] += amount;
		totalSupply += amount;
	}
}

contract ReenteringWETH is ERC20 {
	error NotAllowedReenter();

	address universalRouter;
	bytes data;

	constructor() ERC20("ReenteringWETH", "RW", 18) {}

	function setParameters(address _universalRouter, bytes memory _data) external {
		universalRouter = _universalRouter;
		data = _data;
	}

	function deposit() public payable {
		(bool success, ) = universalRouter.call(data);
		if (!success) revert NotAllowedReenter();
	}
}

contract TestCustomErrors {
	// adding so that hardhat knows this custom signature selector for external contracts
	error InvalidSignature();
	error UnsafeCast();
}
