// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {Shadow} from "../../contracts/Shadow.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ShadowTest is TestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_nameSymbolDecimals() public {
        assertEq(shadow.name(), "Shadow", "Name mismatch");
        assertEq(shadow.symbol(), "SHADOW", "Symbol mismatch");
        assertEq(shadow.decimals(), 18, "Decimals mismatch");
    }

    function test_initialBalances() public {
        assertEq(shadow.balanceOf(ACCESS_MANAGER), 0, "Initial balance for ACCESS_MANAGER should be 0");
        assertEq(shadow.balanceOf(bob), 0, "Initial balance for bob should be 0");
        assertEq(shadow.totalSupply(), 0, "Total supply should be 0");
    }

    function test_mint() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        shadow.mint(ACCESS_MANAGER, amount);
        assertEq(shadow.balanceOf(ACCESS_MANAGER), amount, "Minted amount mismatch");
        assertEq(shadow.totalSupply(), amount, "Total supply mismatch");
    }

    function test_revertOnNonMinterMint() public {
        uint256 amount = 100e18;
        vm.prank(bob);
        vm.expectRevert(Shadow.NOT_MINTER.selector);
        shadow.mint(bob, amount);
    }

    function test_transfer() public {
        uint256 amount = 100;
        vm.prank(ACCESS_MANAGER);
        shadow.mint(ACCESS_MANAGER, amount);

        vm.prank(ACCESS_MANAGER);
        shadow.transfer(bob, amount);
        assertEq(shadow.balanceOf(ACCESS_MANAGER), 0, "Transfer from ACCESS_MANAGER should result in 0 balance");
        assertEq(shadow.balanceOf(bob), amount, "Transfer to bob should result in correct balance");

        vm.prank(bob);
        shadow.transfer(ACCESS_MANAGER, amount);
        assertEq(shadow.balanceOf(bob), 0, "Transfer from bob should result in 0 balance");
        assertEq(
            shadow.balanceOf(ACCESS_MANAGER),
            amount,
            "Transfer to ACCESS_MANAGER should result in correct balance"
        );
    }

    function test_transferFromWithoutApproval() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        shadow.mint(ACCESS_MANAGER, amount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        shadow.transferFrom(ACCESS_MANAGER, bob, amount);
    }

    function test_transferFromWithApproval() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        shadow.mint(ACCESS_MANAGER, amount);

        vm.prank(ACCESS_MANAGER);
        shadow.approve(bob, amount);

        assertEq(shadow.allowance(ACCESS_MANAGER, bob), amount, "Approval amount mismatch");

        vm.prank(bob);
        shadow.transferFrom(ACCESS_MANAGER, bob, amount);

        assertEq(shadow.balanceOf(ACCESS_MANAGER), 0, "Transfer from ACCESS_MANAGER should result in 0 balance");
        assertEq(shadow.balanceOf(bob), amount, "Transfer to bob should result in correct balance");
        assertEq(shadow.allowance(ACCESS_MANAGER, bob), 0, "Allowance should be 0 after transfer");
    }

    function test_burn() public {
        uint256 amount = 100e18;
        vm.startPrank(ACCESS_MANAGER);
        shadow.mint(bob, amount);

        vm.startPrank(bob);
        shadow.burn(amount);

        assertEq(shadow.balanceOf(bob), 0, "Burn should result in 0 balance for bob");
        assertEq(shadow.totalSupply(), 0, "Total supply should be 0 after burn");
    }

    function test_burnFrom() public {
        uint256 amount = 100e18;
        vm.prank(ACCESS_MANAGER);
        shadow.mint(bob, amount);

        vm.prank(bob);
        shadow.approve(alice, amount);

        vm.prank(alice);
        shadow.burnFrom(bob, amount);

        assertEq(shadow.balanceOf(bob), 0, "Burn from bob should result in 0 balance for bob");
        assertEq(shadow.totalSupply(), 0, "Total supply should be 0 after burn");
    }

    function test_partialBurnFrom() public {
        uint256 mintAmount = 100e18;
        uint256 burnAmount = 60e18;

        vm.prank(ACCESS_MANAGER);
        shadow.mint(bob, mintAmount);

        vm.prank(bob);
        shadow.approve(alice, mintAmount);

        vm.prank(alice);
        shadow.burnFrom(bob, burnAmount);

        assertEq(
            shadow.balanceOf(bob),
            mintAmount - burnAmount,
            "Partial burn should result in correct balance for bob"
        );
        assertEq(
            shadow.totalSupply(), mintAmount - burnAmount, "Total supply should be correct after partial burn"
        );
        assertEq(
            shadow.allowance(bob, alice),
            mintAmount - burnAmount,
            "Allowance should be correct after partial burn"
        );
    }

    function test_permitAndBurn() public {
        uint256 amount = 100e18;
        uint256 deadline = block.timestamp + 1 days;

        // Generate permit signature
        bytes32 permitHash = _getPermitHash(bob, alice, amount, shadow.nonces(bob), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, permitHash);

        // Mint tokens to bob
        vm.prank(ACCESS_MANAGER);
        shadow.mint(bob, amount);

        // Execute permit and burn
        shadow.permit(bob, alice, amount, deadline, v, r, s);

        vm.prank(alice);
        shadow.burnFrom(bob, amount);

        assertEq(shadow.balanceOf(bob), 0, "Burn from permit should result in 0 balance for bob");
        assertEq(shadow.totalSupply(), 0, "Total supply should be 0 after burn");
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
                shadow.DOMAIN_SEPARATOR(),
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
