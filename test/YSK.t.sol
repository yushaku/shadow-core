// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {TheTestBase} from "./Base.t.sol";
import {YSK} from "contracts/YSK.sol";

contract YSKTest is TheTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_nameSymbolDecimals() public view {
        assertEq(ysk.name(), "Yushaku", "Name mismatch");
        assertEq(ysk.symbol(), "YSK", "Symbol mismatch");
        assertEq(ysk.decimals(), 18, "Decimals mismatch");
    }

    function test_initialBalances() public view{
        assertEq(ysk.balanceOf(ACCESS_MANAGER), 0, "Initial balance for ACCESS_MANAGER should be 0");
        assertEq(ysk.balanceOf(bob), 0, "Initial balance for bob should be 0");
        assertEq(ysk.totalSupply(), 0, "Total supply should be 0");
    }

    function test_mint() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        ysk.mint(ACCESS_MANAGER, amount);
        assertEq(ysk.balanceOf(ACCESS_MANAGER), amount, "Minted amount mismatch");
        assertEq(ysk.totalSupply(), amount, "Total supply mismatch");
    }

    function test_revertOnNonMinterMint() public {
        uint256 amount = 100e18;
        vm.prank(bob);
        vm.expectRevert(YSK.NOT_MINTER.selector);
        ysk.mint(bob, amount);
    }

    function test_transfer() public {
        uint256 amount = 100;
        vm.prank(ACCESS_MANAGER);
        ysk.mint(ACCESS_MANAGER, amount);

        vm.prank(ACCESS_MANAGER);
        ysk.transfer(bob, amount);
        assertEq(ysk.balanceOf(ACCESS_MANAGER), 0, "Transfer from ACCESS_MANAGER should result in 0 balance");
        assertEq(ysk.balanceOf(bob), amount, "Transfer to bob should result in correct balance");

        vm.prank(bob);
        ysk.transfer(ACCESS_MANAGER, amount);
        assertEq(ysk.balanceOf(bob), 0, "Transfer from bob should result in 0 balance");
        assertEq(
            ysk.balanceOf(ACCESS_MANAGER),
            amount,
            "Transfer to ACCESS_MANAGER should result in correct balance"
        );
    }

    function test_transferFromWithoutApproval() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        ysk.mint(ACCESS_MANAGER, amount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        ysk.transferFrom(ACCESS_MANAGER, bob, amount);
    }

    function test_transferFromWithApproval() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        ysk.mint(ACCESS_MANAGER, amount);

        vm.prank(ACCESS_MANAGER);
        ysk.approve(bob, amount);

        assertEq(ysk.allowance(ACCESS_MANAGER, bob), amount, "Approval amount mismatch");

        vm.prank(bob);
        ysk.transferFrom(ACCESS_MANAGER, bob, amount);

        assertEq(ysk.balanceOf(ACCESS_MANAGER), 0, "Transfer from ACCESS_MANAGER should result in 0 balance");
        assertEq(ysk.balanceOf(bob), amount, "Transfer to bob should result in correct balance");
        assertEq(ysk.allowance(ACCESS_MANAGER, bob), 0, "Allowance should be 0 after transfer");
    }

    function test_burn() public {
        uint256 amount = 100e18;
        vm.startPrank(ACCESS_MANAGER);
        ysk.mint(bob, amount);

        vm.startPrank(bob);
        ysk.burn(amount);

        assertEq(ysk.balanceOf(bob), 0, "Burn should result in 0 balance for bob");
        assertEq(ysk.totalSupply(), 0, "Total supply should be 0 after burn");
    }

    function test_burnFrom() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        ysk.mint(bob, amount);

        vm.prank(bob);
        ysk.approve(alice, amount);

        vm.prank(alice);
        ysk.burnFrom(bob, amount);

        assertEq(ysk.balanceOf(bob), 0, "Burn from bob should result in 0 balance for bob");
        assertEq(ysk.totalSupply(), 0, "Total supply should be 0 after burn");
    }

    function test_partialBurnFrom() public {
        uint256 mintAmount = 100e18;
        uint256 burnAmount = 60e18;

        vm.prank(ACCESS_MANAGER);
        ysk.mint(bob, mintAmount);

        vm.prank(bob);
        ysk.approve(alice, mintAmount);

        vm.prank(alice);
        ysk.burnFrom(bob, burnAmount);

        assertEq(
            ysk.balanceOf(bob),
            mintAmount - burnAmount,
            "Partial burn should result in correct balance for bob"
        );
        assertEq(
            ysk.totalSupply(), mintAmount - burnAmount, "Total supply should be correct after partial burn"
        );
        assertEq(
            ysk.allowance(bob, alice),
            mintAmount - burnAmount,
            "Allowance should be correct after partial burn"
        );
    }

    function test_permitAndBurn() public {
        uint256 amount = 100e18;
        uint256 deadline = block.timestamp + 1 days;

        // Generate permit signature
        bytes32 permitHash = _getPermitHash(bob, alice, amount, ysk.nonces(bob), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, permitHash);

        // Mint tokens to bob
        vm.prank(ACCESS_MANAGER);
        ysk.mint(bob, amount);

        // Execute permit and burn
        ysk.permit(bob, alice, amount, deadline, v, r, s);

        vm.prank(alice);
        ysk.burnFrom(bob, amount);

        assertEq(ysk.balanceOf(bob), 0, "Burn from permit should result in 0 balance for bob");
        assertEq(ysk.totalSupply(), 0, "Total supply should be 0 after burn");
    }

    // Helper function for permit tests
    function _getPermitHash(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                ysk.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );
    }
}
