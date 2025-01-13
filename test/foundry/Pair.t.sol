// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {Pair} from "../../contracts/Pair.sol";
import {PairFactory} from "../../contracts/factories/PairFactory.sol";
import {IPairCallee} from "../../contracts/interfaces/IPairCallee.sol";
import {IPair} from "../../contracts/interfaces/IPair.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract MockCallee is IPairCallee {
    function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        // Mock implementation for testing callbacks
    }
}

contract PairTest is TestBase {
    Pair public pair;
    PairFactory public pairFactory;
    MockCallee public callee;
    MockERC20 public token0Sorted;
    MockERC20 public token1Sorted;

    function setUp() public override {
        super.setUp();

        // Deploy factory and callee
        pairFactory =
            new PairFactory(address(mockVoter), address(TREASURY), address(accessHub), address(feeRecipientFactory));
        callee = new MockCallee();

        // Sort tokens based on address
        if (address(token0) < address(token1)) {
            token0Sorted = token0;
            token1Sorted = token1;
        } else {
            token0Sorted = token1;
            token1Sorted = token0;
        }

        // Create pair through factory
        pair = Pair(pairFactory.createPair(address(token0), address(token1), false));

        // Mint initial tokens to users
        deal(address(token0Sorted), alice, 100e18);
        deal(address(token1Sorted), alice, 100e18);
        deal(address(token0Sorted), bob, 100e18);
        deal(address(token1Sorted), bob, 100e18);
    }

    function test_initialize() public view {
        // Step 1: Verify factory address is set correctly
        assertEq(pair.factory(), address(pairFactory), "Factory address mismatch");

        // Step 2: Verify token0 is set correctly
        assertEq(pair.token0(), address(token0Sorted), "Token0 mismatch");

        // Step 3: Verify token1 is set correctly
        assertEq(pair.token1(), address(token1Sorted), "Token1 mismatch");

        // Step 4: Verify stable flag is set correctly
        assertEq(pair.stable(), false, "Stable flag mismatch");
    }

    function test_mint() public {
        // Step 1: Start impersonating alice
        vm.startPrank(alice);

        // Step 3: Transfer tokens to pair
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);

        // Step 4: Mint liquidity tokens
        uint256 liquidity = pair.mint(alice);

        // Step 5: Verify liquidity tokens were minted
        assertGt(liquidity, 0, "No liquidity minted");
        assertEq(pair.balanceOf(alice), liquidity, "Liquidity balance mismatch");
    }

    function test_burn() public {
        // Step 1: Start impersonating alice
        vm.startPrank(alice);

        // Step 2: Setup initial liquidity
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);

        // Step 3: Transfer liquidity tokens to pair for burning
        pair.transfer(address(pair), liquidity);

        // Step 4: Burn liquidity tokens
        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        // Step 5: Verify tokens were returned
        assertGt(amount0, 0, "No token0Sorted returned");
        assertGt(amount1, 0, "No token1Sorted returned");

        // Step 6: Verify liquidity tokens were burned
        assertEq(pair.balanceOf(alice), 0, "Liquidity not fully burned");
    }

    function test_swap() public {
        // Step 1: Add initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Start impersonating bob for swap
        vm.startPrank(bob);

        // Step 3: Transfer token0Sorted to pair
        token0Sorted.transfer(address(pair), 1e18);

        // Step 4: Record balance before swap
        uint256 balanceBefore = token1Sorted.balanceOf(bob);

        // Step 5: Execute swap
        pair.swap(0, 0.9e18, bob, "");

        // Step 6: Record balance after swap
        uint256 balanceAfter = token1Sorted.balanceOf(bob);

        // Step 7: Verify swap was successful
        assertGt(balanceAfter, balanceBefore, "Swap did not increase token1Sorted balance");
    }

    function test_syncBasic() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Force imbalance by direct transfer
        token0Sorted.transfer(address(pair), 1e18);
        token1Sorted.transfer(address(pair), 2e18);

        // Step 3: Get reserves before sync
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        // Step 4: Call sync
        pair.sync();

        // Step 5: Get reserves after sync
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        // Step 6: Verify reserves are updated to match current balances
        assertGt(reserve0After, reserve0Before, "Reserve0 did not increase after sync");
        assertGt(reserve1After, reserve1Before, "Reserve1 did not increase after sync");
        assertEq(reserve0After, token0Sorted.balanceOf(address(pair)), "Reserve0 does not match token0Sorted balance");
        assertEq(reserve1After, token1Sorted.balanceOf(address(pair)), "Reserve1 does not match token1Sorted balance");
    }

    function test_syncAfterSwap() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Perform swap as bob
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 3: Get reserves before sync
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        // Step 4: Force additional imbalance as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 1e18);
        vm.stopPrank();

        // Step 5: Call sync to update reserves
        pair.sync();

        // Step 6: Get reserves after sync
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        // Step 7: Verify reserves are updated correctly
        assertGt(reserve0After, reserve0Before, "Reserve0 did not increase after sync");
        assertEq(reserve1After, reserve1Before, "Reserve1 changed unexpectedly");
        assertEq(reserve0After, token0Sorted.balanceOf(address(pair)), "Reserve0 does not match token0Sorted balance");
        assertEq(reserve1After, token1Sorted.balanceOf(address(pair)), "Reserve1 does not match token1Sorted balance");
    }

    function test_skimBasic() public {
        // Step 1: Enable skim for the pair by calling setSkimEnabled from accessHub
        vm.prank(address(accessHub));
        pairFactory.setSkimEnabled(address(pair), true);

        // Step 2: Setup initial liquidity by transferring tokens and minting LP tokens
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 3: Force excess balance by transferring additional tokens to the pair
        token0Sorted.transfer(address(pair), 1e18);
        token1Sorted.transfer(address(pair), 2e18);

        // Step 4: Store initial balances of recipient and pair reserves before skim
        uint256 balance0Before = token0Sorted.balanceOf(bob);
        uint256 balance1Before = token1Sorted.balanceOf(bob);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Step 5: Call skim to transfer excess tokens to recipient
        pair.skim(bob);

        // Step 6: Verify excess tokens were correctly transferred to recipient
        assertEq(token0Sorted.balanceOf(bob), balance0Before + 1e18, "Incorrect token0Sorted skim amount");
        assertEq(token1Sorted.balanceOf(bob), balance1Before + 2e18, "Incorrect token1Sorted skim amount");

        // Step 7: Verify pair reserves remained unchanged after skim
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(reserve0After, reserve0, "Reserve0 changed after skim");
        assertEq(reserve1After, reserve1, "Reserve1 changed after skim");
    }

    function test_skimAfterMultipleTransfers() public {
        // Step 1: Enable skim functionality for the pair through accessHub
        vm.prank(address(accessHub));
        pairFactory.setSkimEnabled(address(pair), true);

        // Step 2: Setup initial liquidity pool state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 3: Create excess balance through multiple smaller transfers
        token0Sorted.transfer(address(pair), 0.5e18);
        token1Sorted.transfer(address(pair), 0.5e18);
        token0Sorted.transfer(address(pair), 0.5e18);
        token1Sorted.transfer(address(pair), 0.5e18);

        // Step 4: Store initial balances and reserves before skim
        uint256 balance0Before = token0Sorted.balanceOf(bob);
        uint256 balance1Before = token1Sorted.balanceOf(bob);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Step 5: Execute skim operation to recipient
        pair.skim(bob);

        // Step 6: Verify accumulated excess tokens were transferred correctly
        assertEq(token0Sorted.balanceOf(bob), balance0Before + 1e18, "Incorrect token0Sorted amount skimmed");
        assertEq(token1Sorted.balanceOf(bob), balance1Before + 1e18, "Incorrect token1Sorted amount skimmed");

        // Step 7: Verify pair reserves remained unchanged
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(reserve0After, reserve0, "Reserve0 changed after skim");
        assertEq(reserve1After, reserve1, "Reserve1 changed after skim");
    }

    function test_revertSkimDisabled() public {
        // Step 1: Setup initial liquidity state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Create excess balance condition
        token0Sorted.transfer(address(pair), 1e18);

        // Step 3: Attempt skim operation while disabled and verify revert
        vm.expectRevert(abi.encodeWithSelector(IPair.SD.selector)); // SD() - Skim Disabled
        pair.skim(bob);
    }

    function test_skimWithNoExcess() public {
        // Step 1: Enable skim functionality through accessHub
        vm.prank(address(accessHub));
        pairFactory.setSkimEnabled(address(pair), true);

        // Step 2: Setup initial liquidity state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 3: Store initial balances before skim
        uint256 balance0Before = token0Sorted.balanceOf(bob);
        uint256 balance1Before = token1Sorted.balanceOf(bob);

        // Step 4: Execute skim with no excess tokens
        pair.skim(bob);

        // Step 5: Verify no token transfers occurred
        assertEq(token0Sorted.balanceOf(bob), balance0Before, "Token0 balance changed when no excess");
        assertEq(token1Sorted.balanceOf(bob), balance1Before, "Token1 balance changed when no excess");
    }

    function test_setFeeRecipient() public {
        // Step 1: Set fee recipient as factory and verify
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));

        // Step 2: Verify fee recipient was set correctly
        assertEq(pair.feeRecipient(), address(feeRecipient), "Fee recipient not set correctly");
    }

    function test_revertSetFeeRecipientUnauthorized() public {
        // Step 1: Attempt unauthorized fee recipient change and verify revert
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPair.NOT_AUTHORIZED.selector)); // NOT_AUTHORIZED()
        pair.setFeeRecipient(address(feeRecipient));
    }

    function test_setFeeSplit() public {
        // Step 1: Set fee split as factory and verify
        vm.startPrank(address(pairFactory));
        pair.setFeeSplit(1000); // 10%

        // Step 2: Verify fee split was set correctly
        assertEq(pair.feeSplit(), 1000, "Fee split not set correctly");
    }

    function test_revertSetFeeSplitUnauthorized() public {
        // Step 1: Attempt unauthorized fee split change and verify revert
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPair.NOT_AUTHORIZED.selector)); // NOT_AUTHORIZED()
        pair.setFeeSplit(1000);
    }

    function test_setFee() public {
        // Step 1: Set fee as factory and verify
        vm.startPrank(address(pairFactory));
        pair.setFee(3000); // 0.3%

        // Step 2: Verify fee was set correctly
        assertEq(pair.fee(), 3000, "Fee not set correctly");
    }

    function test_revertSetFeeUnauthorized() public {
        // Step 1: Attempt unauthorized fee change and verify revert
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPair.NOT_AUTHORIZED.selector)); // NOT_AUTHORIZED()
        pair.setFee(3000);
    }

    function test_getAmountOut() public {
        // Step 1: Setup initial liquidity state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Calculate and verify getAmountOut result
        uint256 amountOut = pair.getAmountOut(1e18, address(token0Sorted));
        assertGt(amountOut, 0, "Amount out must be greater than zero");
    }

    function test_observations() public {
        // Step 1: Setup initial liquidity state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Advance time and trigger observation update
        vm.warp(block.timestamp + 1 days);
        pair.sync();

        // Step 3: Verify observation count
        assertEq(pair.observationLength(), 2, "Observation length should be 2");

        // Step 4: Verify last observation timestamp
        Pair.Observation memory lastObs = pair.lastObservation();
        assertGt(lastObs.timestamp, 0, "Last observation timestamp must be greater than 0");
    }

    function test_currentCumulativePrices() public {
        // Step 1: Setup initial liquidity state
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Advance time
        vm.warp(block.timestamp + 3600);

        // Step 3: Get current cumulative prices
        (uint256 reserve0Cumulative, uint256 reserve1Cumulative, uint256 blockTimestamp) =
            pair.currentCumulativePrices();

        // Step 4: Verify cumulative prices and timestamp
        assertGt(reserve0Cumulative, 0, "Reserve0 cumulative must be greater than 0");
        assertGt(reserve1Cumulative, 0, "Reserve1 cumulative must be greater than 0");
        assertEq(blockTimestamp, block.timestamp, "Block timestamp mismatch");
    }

    function test_stablePair() public {
        // Step 1: Create stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 10e18);

        // Step 3: Mint and verify liquidity
        uint256 liquidity = stablePair.mint(alice);
        assertGt(liquidity, 0, "Liquidity must be greater than 0");
    }

    function test_mintInitialLiquidity() public {
        // Step 1: Start as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);

        // Step 2: Transfer tokens to pair
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);

        // Step 3: Mint liquidity tokens
        uint256 liquidity = pair.mint(alice);

        // Step 4: Verify minimum liquidity was sent to dead address
        assertEq(pair.balanceOf(address(0xdead)), 1000, "Minimum liquidity not sent to dead address");

        // Step 5: Verify liquidity was properly minted to alice
        assertEq(pair.balanceOf(alice), liquidity, "Liquidity not properly minted to alice");

        // Step 6: Verify total supply matches expected amount
        assertEq(pair.totalSupply(), liquidity + 1000, "Total supply mismatch");
    }

    function test_mintAdditionalLiquidity() public {
        // Step 1: Add initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 initialLiquidity = pair.mint(alice);

        // Step 2: Add more liquidity with same ratio
        token0Sorted.transfer(address(pair), 5e18);
        token1Sorted.transfer(address(pair), 5e18);
        uint256 additionalLiquidity = pair.mint(alice);

        // Step 3: Verify additional liquidity is proportional to initial amount
        assertApproxEqAbs(additionalLiquidity, initialLiquidity / 2, 1000, "Additional liquidity not proportional");
    }

    function test_mintWithImbalancedRatio() public {
        // Step 1: Add initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Add liquidity with different ratio
        token0Sorted.transfer(address(pair), 5e18);
        token1Sorted.transfer(address(pair), 3e18);
        uint256 liquidityMinted = pair.mint(alice);

        // Step 3: Get current reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Step 4: Verify minted amount based on lower ratio
        assertEq(
            liquidityMinted,
            Math.min((5e18 * pair.totalSupply()) / reserve0, (3e18 * pair.totalSupply()) / reserve1),
            "Incorrect liquidity minted for imbalanced ratio"
        );
    }

    function test_mintWithFeesAccrued() public {
        // Step 1: Setup initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Configure fees as factory
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));
        pair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 3: Generate fees through swap as bob
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 4: Add more liquidity after fees as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 5e18);
        token1Sorted.transfer(address(pair), 5e18);
        uint256 liquidityWithFees = pair.mint(alice);

        // Step 5: Verify minting with fees
        assertGt(liquidityWithFees, 0, "No liquidity minted after fees");
    }

    function test_mintStablePair() public {
        // Step 1: Create stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Start as alice
        vm.startPrank(alice);

        // Step 3: Add initial liquidity with 1:1 ratio
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 10e18);
        uint256 liquidity = stablePair.mint(alice);

        // Step 4: Verify minting was successful
        assertGt(liquidity, 0, "Liquidity should be greater than 0");
        assertEq(stablePair.balanceOf(alice), liquidity, "Alice's balance should equal minted liquidity");
    }

    function test_revertMintWithZeroLiquidity() public {
        // Step 1: Start as alice and add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Try to mint again without adding more tokens
        vm.expectRevert(abi.encodeWithSelector(IPair.ILM.selector)); // ILM() - Insufficient Liquidity Minted
        pair.mint(alice);
    }

    function test_revertMintStablePairImbalanced() public {
        // Step 1: Create stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Start as alice
        vm.startPrank(alice);

        // Step 3: Attempt imbalanced liquidity add
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 9e18);

        // Step 4: Verify revert on imbalanced ratio
        vm.expectRevert(abi.encodeWithSelector(IPair.UNSTABLE_RATIO.selector)); // UNSTABLE_RATIO()
        stablePair.mint(alice);
    }

    function test_mintToOtherRecipient() public {
        // Step 1: Start as alice
        vm.startPrank(alice);

        // Step 2: Transfer tokens to pair
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);

        // Step 3: Mint to different recipient (bob)
        uint256 liquidity = pair.mint(bob);

        // Step 4: Verify recipient balances
        assertEq(pair.balanceOf(bob), liquidity, "Bob's balance should equal minted liquidity");
        assertEq(pair.balanceOf(alice), 0, "Alice's balance should be 0");
    }

    function test_mintMultipleUsers() public {
        // Step 1: First user (alice) adds liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 aliceLiquidity = pair.mint(alice);
        vm.stopPrank();

        // Step 2: Second user (bob) adds liquidity
        vm.startPrank(bob);
        token0Sorted.transfer(address(pair), 5e18);
        token1Sorted.transfer(address(pair), 5e18);
        uint256 bobLiquidity = pair.mint(bob);
        vm.stopPrank();

        // Step 3: Verify proportional liquidity distribution
        assertApproxEqAbs(bobLiquidity, aliceLiquidity / 2, 1000, "Bob's liquidity should be half of Alice's");
        assertApproxEqAbs(
            pair.balanceOf(alice), aliceLiquidity, 1000, "Alice's balance should equal her minted liquidity"
        );
        assertApproxEqAbs(pair.balanceOf(bob), bobLiquidity, 1000, "Bob's balance should equal his minted liquidity");
    }

    function test_burnInitialLiquidity() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);

        // Step 2: Transfer LP tokens to pair
        pair.transfer(address(pair), liquidity);
        uint256 balance0Before = token0Sorted.balanceOf(alice);
        uint256 balance1Before = token1Sorted.balanceOf(alice);

        // Step 3: Burn liquidity
        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        // Step 4: Verify burn results
        assertGt(amount0, 0, "Amount0 should be greater than 0");
        assertGt(amount1, 0, "Amount1 should be greater than 0");
        assertEq(token0Sorted.balanceOf(alice), balance0Before + amount0, "Incorrect token0Sorted balance after burn");
        assertEq(token1Sorted.balanceOf(alice), balance1Before + amount1, "Incorrect token1Sorted balance after burn");
        assertEq(pair.balanceOf(alice), 0, "LP token balance should be 0 after burn");
    }

    function test_burnPartialLiquidity() public {
        // Step 1: Add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);

        // Step 2: Burn half of liquidity
        uint256 halfLiquidity = liquidity / 2;
        pair.transfer(address(pair), halfLiquidity);
        uint256 balance0Before = token0Sorted.balanceOf(alice);
        uint256 balance1Before = token1Sorted.balanceOf(alice);

        // Step 3: Execute burn
        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        // Step 4: Verify results
        assertApproxEqAbs(amount0, 5e18, 1000, "Should receive half of initial token0Sorted"); // Half of initial
        assertApproxEqAbs(amount1, 5e18, 1000, "Should receive half of initial token1Sorted"); // Half of initial
        assertApproxEqAbs(pair.balanceOf(alice), halfLiquidity, 1000, "Should have half of initial LP tokens remaining");
        assertApproxEqAbs(
            token0Sorted.balanceOf(alice), balance0Before + amount0, 1000, "Incorrect token0Sorted balance after burn"
        );
        assertApproxEqAbs(
            token1Sorted.balanceOf(alice), balance1Before + amount1, 1000, "Incorrect token1Sorted balance after burn"
        );
    }

    function test_burnWithFeesAccrued() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);
        vm.stopPrank();

        // Step 2: Configure fees
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));
        pair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 3: Generate fees through swaps
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 4: Burn liquidity
        vm.startPrank(alice);
        pair.transfer(address(pair), liquidity);
        uint256 balance0Before = token0Sorted.balanceOf(alice);
        uint256 balance1Before = token1Sorted.balanceOf(alice);

        // Step 5: Execute burn and verify results
        (uint256 amount0, uint256 amount1) = pair.burn(alice);

        assertApproxEqAbs(amount0, 10e18, 2000, "Should receive more than initial token0Sorted due to fees");
        assertApproxEqAbs(amount1, 10.1e18, 2000, "Should receive less than initial token1Sorted due to swap");
        assertApproxEqAbs(
            token0Sorted.balanceOf(alice), balance0Before + amount0, 1000, "Incorrect token0Sorted balance after burn"
        );
        assertApproxEqAbs(
            token1Sorted.balanceOf(alice), balance1Before + amount1, 1000, "Incorrect token1Sorted balance after burn"
        );
    }

    function test_burnToOtherRecipient() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);

        // Step 2: Prepare burn to bob
        pair.transfer(address(pair), liquidity);
        uint256 balance0Before = token0Sorted.balanceOf(bob);
        uint256 balance1Before = token1Sorted.balanceOf(bob);

        // Step 3: Execute burn and verify results
        (uint256 amount0, uint256 amount1) = pair.burn(bob);

        assertEq(
            token0Sorted.balanceOf(bob), balance0Before + amount0, "Bob's token0Sorted balance incorrect after burn"
        );
        assertEq(
            token1Sorted.balanceOf(bob), balance1Before + amount1, "Bob's token1Sorted balance incorrect after burn"
        );
        assertEq(token0Sorted.balanceOf(alice), 90e18, "Alice's token0Sorted balance incorrect after burn"); // Initial 100e18 - 10e18
        assertEq(token1Sorted.balanceOf(alice), 90e18, "Alice's token1Sorted balance incorrect after burn"); // Initial 100e18 - 10e18
    }

    function test_burnStablePair() public {
        // Step 1: Create stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 10e18);
        uint256 liquidity = stablePair.mint(alice);

        // Step 3: Prepare burn
        stablePair.transfer(address(stablePair), liquidity);
        uint256 balance0Before = token0Sorted.balanceOf(alice);
        uint256 balance1Before = token1Sorted.balanceOf(alice);

        // Step 4: Execute burn and verify results
        (uint256 amount0, uint256 amount1) = stablePair.burn(alice);

        assertApproxEqAbs(amount0, 10e18, 1000, "Incorrect amount of token0Sorted returned from burn");
        assertApproxEqAbs(amount1, 10e18, 1000, "Incorrect amount of token1Sorted returned from burn");
        assertApproxEqAbs(
            token0Sorted.balanceOf(alice),
            balance0Before + amount0,
            1000,
            "Alice's token0Sorted balance incorrect after burn"
        );
        assertApproxEqAbs(
            token1Sorted.balanceOf(alice),
            balance1Before + amount1,
            1000,
            "Alice's token1Sorted balance incorrect after burn"
        );
    }

    function test_revertBurnWithoutLiquidity() public {
        // Step 1: Start as alice and add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);

        // Step 2: Attempt burn without liquidity
        vm.expectRevert(abi.encodeWithSelector(IPair.ILB.selector)); // ILB() - Insufficient Liquidity Burned
        pair.burn(alice);
    }

    function test_burnUpdatesReserves() public {
        // Step 1: Start as alice and setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);

        // Step 2: Get reserves before burn
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        // Step 3: Burn all liquidity
        pair.transfer(address(pair), liquidity);
        pair.burn(alice);

        // Step 4: Get reserves after burn
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        // Step 5: Verify reserves were updated correctly
        assertLt(reserve0After, reserve0Before, "Reserve0 should decrease after burn");
        assertLt(reserve1After, reserve1Before, "Reserve1 should decrease after burn");
        assertEq(reserve0After, 1000, "Reserve0 should equal MINIMUM_LIQUIDITY"); // Only MINIMUM_LIQUIDITY remaining
        assertEq(reserve1After, 1000, "Reserve1 should equal MINIMUM_LIQUIDITY"); // Only MINIMUM_LIQUIDITY remaining
    }

    function test_swapToken0ForToken1() public {
        // Step 1: Setup initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Prepare swap as bob
        vm.startPrank(bob);
        uint256 swapAmount = 1e18;
        token1Sorted.transfer(address(pair), swapAmount);

        // Step 3: Execute swap and verify results
        uint256 balance1Before = token1Sorted.balanceOf(bob);
        pair.swap(0, 0.9e18, bob, "");
        uint256 balance1After = token1Sorted.balanceOf(bob);

        assertEq(balance1After - balance1Before, 0.9e18, "Incorrect token1Sorted amount received from swap");
    }

    function test_swapToken1ForToken0() public {
        // Step 1: Setup initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Prepare swap as bob
        vm.startPrank(bob);
        uint256 swapAmount = 1e18;
        token1Sorted.transfer(address(pair), swapAmount);

        // Step 3: Execute swap and verify results
        uint256 balance0Before = token0Sorted.balanceOf(bob);
        pair.swap(0.9e18, 0, bob, "");
        uint256 balance0After = token0Sorted.balanceOf(bob);

        assertEq(balance0After - balance0Before, 0.9e18, "Incorrect token0Sorted amount received from swap");
    }

    function test_swapWithFees() public {
        // Step 1: Setup initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Configure fees
        vm.startPrank(address(pairFactory));
        pair.setFee(3000); // 0.3%
        pair.setFeeRecipient(address(feeRecipient));
        vm.stopPrank();

        // Step 3: Execute swap as bob
        vm.startPrank(bob);
        uint256 swapAmount = 1e18;
        token0Sorted.transfer(address(pair), swapAmount);

        uint256 balance1Before = token1Sorted.balanceOf(bob);
        pair.swap(0, 0.9e18, bob, "");
        uint256 balance1After = token1Sorted.balanceOf(bob);

        // Step 4: Verify results including fees
        assertEq(balance1After - balance1Before, 0.9e18, "Incorrect token1Sorted amount received from swap with fees");
        (uint112 reserve0,,) = pair.getReserves();
        assertGt(
            reserve0, 10e18 + swapAmount - ((swapAmount * 3000) / 1_000_000), "Reserve0 should reflect fee deduction"
        );
    }

    function test_swapWithCallback() public {
        // Step 1: Setup initial liquidity as alice
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Deploy mock callee contract and fund it with tokens
        MockCalleeWithCallback mockCalleeWithCallback =
            new MockCalleeWithCallback(address(token0Sorted), address(token1Sorted));
        deal(address(token0Sorted), address(mockCalleeWithCallback), 1e18);

        // Step 3: Prepare and execute swap with callback
        bytes memory data = abi.encode("callback data");
        vm.expectEmit(true, true, true, true);
        emit MockCalleeWithCallback.Log("hook", address(pair), 0, 0.9e18, data);
        mockCalleeWithCallback.initiateSwap(address(pair), 1e18, 0, 0.9e18, data);

        // Step 4: Verify token balances after swap
        assertEq(
            token1Sorted.balanceOf(address(mockCalleeWithCallback)),
            0.9e18,
            "Incorrect token1Sorted balance after callback swap"
        );
    }

    function test_swapStablePair() public {
        // Step 1: Create and setup stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 10e18);
        stablePair.mint(alice);
        vm.stopPrank();

        // Step 3: Perform swap on stable pair
        vm.startPrank(bob);
        token0Sorted.transfer(address(stablePair), 1e18);

        uint256 balance1Before = token1Sorted.balanceOf(bob);
        stablePair.swap(0, 0.9e18, bob, "");
        uint256 balance1After = token1Sorted.balanceOf(bob);

        // Step 4: Verify swap with stable curve
        assertEq(balance1After - balance1Before, 0.9e18, "Incorrect token1Sorted amount received from stable pair swap");
    }

    function test_revertSwapInsufficientOutputAmount() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Attempt invalid swap with zero output
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPair.IOA.selector)); // IOA() - Insufficient Output Amount
        pair.swap(0, 0, bob, "");
    }

    function test_revertSwapInsufficientLiquidity() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Attempt swap exceeding available liquidity
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPair.IL.selector)); // IL() - Insufficient Liquidity
        pair.swap(11e18, 0, bob, "");
    }

    function test_revertSwapInvalidTo() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Attempt swap to invalid address
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPair.IT.selector)); // IT() - Invalid To
        pair.swap(1e18, 0, address(token0Sorted), "");
    }

    function test_revertSwapInsufficientInputAmount() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Attempt swap without providing input tokens
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPair.IIA.selector)); // IIA() - Insufficient Input Amount
        pair.swap(1e18, 0, bob, "");
    }

    function test_revertSwapK() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Attempt swap violating K invariant
        vm.startPrank(bob);
        token0Sorted.transfer(address(pair), 1e18);
        vm.expectRevert(abi.encodeWithSelector(IPair.K.selector)); // K invariant violation
        pair.swap(0, 1e18, bob, "");
    }

    function test_mintFeeWithoutFeeRecipient() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Generate fees through swap
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 3: Attempt to mint fees
        uint256 kLastBefore = pair.kLast();
        pair.mintFee();
        uint256 kLastAfter = pair.kLast();

        // Step 4: Verify no fees were minted
        assertEq(kLastAfter, kLastBefore, "kLast should not change when no fee recipient is set");
    }

    function test_mintFeeWithFeeRecipient() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Set fee recipient and fee split
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));
        pair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 3: Initialize kLast with first swap and fee mint
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        pair.mintFee();

        // Step 4: Perform second swap to generate more fees
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 5: Get balances before minting fees
        uint256 feeRecipientBalanceBefore = pair.balanceOf(address(feeRecipient));
        uint256 kLastBefore = pair.kLast();

        // Step 6: Mint fees and verify
        pair.mintFee();
        assertGt(
            pair.balanceOf(address(feeRecipient)),
            feeRecipientBalanceBefore,
            "Fee recipient balance should increase after minting fees"
        );
        assertGt(pair.kLast(), kLastBefore, "kLast should increase after minting fees");
    }

    function test_mintFeeStablePair() public {
        // Step 1: Create and setup stable pair
        Pair stablePair = Pair(pairFactory.createPair(address(token0Sorted), address(token1Sorted), true));

        // Step 2: Add initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(stablePair), 10e18);
        token1Sorted.transfer(address(stablePair), 10e18);
        stablePair.mint(alice);
        vm.stopPrank();

        // Step 3: Set fee recipient and fee split
        vm.startPrank(address(pairFactory));
        stablePair.setFeeRecipient(address(feeRecipient));
        stablePair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 4: Initialize kLast with first swap and fee mint
        vm.startPrank(bob);
        token1Sorted.transfer(address(stablePair), 1e18);
        stablePair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();
        stablePair.mintFee();

        // Step 5: Generate more fees with second swap
        vm.startPrank(bob);
        token1Sorted.transfer(address(stablePair), 1e18);
        stablePair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 6: Record balances before minting fees
        uint256 feeRecipientBalanceBefore = stablePair.balanceOf(address(feeRecipient));
        uint256 kLastBefore = stablePair.kLast();
        stablePair.mintFee();

        // Step 7: Verify fees were minted correctly
        assertGt(
            stablePair.balanceOf(address(feeRecipient)),
            feeRecipientBalanceBefore,
            "Fee recipient balance should increase after minting fees in stable pair"
        );
        assertGt(stablePair.kLast(), kLastBefore, "kLast should increase after minting fees in stable pair");
    }

    function test_mintFeeMultipleSwaps() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        pair.mint(alice);
        vm.stopPrank();

        // Step 2: Set fee recipient and fee split
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));
        pair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 3: Perform multiple swaps
        vm.startPrank(bob);
        for (uint256 i = 0; i < 5; i++) {
            deal(address(token1Sorted), bob, 1e18);
            token1Sorted.transfer(address(pair), 1e18);
            pair.swap(0, 0.9e18, bob, "");
            if (i == 0) {
                // We create kLast in the first swap
                pair.mintFee();
            }
        }
        vm.stopPrank();

        // Step 4: Get balances and mint fees
        uint256 feeRecipientBalanceBefore = pair.balanceOf(address(feeRecipient));
        pair.mintFee();

        // Step 5: Verify accumulated fees
        uint256 feesMinted = pair.balanceOf(address(feeRecipient)) - feeRecipientBalanceBefore;
        assertGt(feesMinted, 0, "Fees should be minted after multiple swaps");
    }

    function test_mintFeeAfterRemovingLiquidity() public {
        // Step 1: Setup initial liquidity
        vm.startPrank(alice);
        token0Sorted.transfer(address(pair), 10e18);
        token1Sorted.transfer(address(pair), 10e18);
        uint256 liquidity = pair.mint(alice);
        vm.stopPrank();

        // Step 2: Configure fees
        vm.startPrank(address(pairFactory));
        pair.setFeeRecipient(address(feeRecipient));
        pair.setFeeSplit(1000); // 10%
        vm.stopPrank();

        // Step 3: Generate fees through first swap
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 4: Mint fees from first swap
        pair.mintFee();

        // Step 5: Generate more fees through second swap
        vm.startPrank(bob);
        token1Sorted.transfer(address(pair), 1e18);
        pair.swap(0, 0.9e18, bob, "");
        vm.stopPrank();

        // Step 6: Record balance before removing liquidity
        uint256 feeRecipientBalanceBefore = pair.balanceOf(address(feeRecipient));

        // Step 7: Remove partial liquidity
        vm.startPrank(alice);
        pair.transfer(address(pair), liquidity / 2);
        pair.burn(alice);
        vm.stopPrank();

        // Step 8: Mint fees and verify
        pair.mintFee();
        assertGt(
            pair.balanceOf(address(feeRecipient)),
            feeRecipientBalanceBefore,
            "Fee recipient balance should increase after minting fees with partial liquidity removed"
        );
    }
}

contract MockCalleeWithCallback is TestBase {
    constructor(address _token0, address _token1) {
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
    }

    event Log(string message, address pair, uint256 amount0Out, uint256 amount1Out, bytes data);

    function initiateSwap(
        address _pair,
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256 _amountOut,
        bytes memory _data
    ) public {
        // Approve token0 for transfer
        token0.transfer(_pair, _amountIn);
        // Call swap on the pair contract
        Pair(_pair).swap(_amountOutMin, _amountOut, address(this), _data);
    }

    // Implement callback from pair contract
    function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        emit Log("hook", msg.sender, amount0Out, amount1Out, data);
    }
}
