// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "script/Helper.s.sol";
import {Voter} from "contracts/Voter.sol";

/**
 * @title UniversalRouterSwapTest
 * @notice Integration tests for the UniversalRouterSwap contract using mainnet fork.
 * @dev To run: "forge test --fork-url bsc test/integration/voter.it.sol -vvv"
 */
contract VoterTest is Test {
  Helper public helper;
  Voter public voter;

  function setUp() public {
    helper = new Helper();
    address voterAddress = helper.readAddress("Voter");
    voter = Voter(voterAddress);
  }

  function testConstructor() public view {
    address clFactory = voter.clFactory();
    address cLPoolFactory = helper.readAddress("CLPoolFactory");
    assertEq(clFactory, cLPoolFactory);
  }
}

