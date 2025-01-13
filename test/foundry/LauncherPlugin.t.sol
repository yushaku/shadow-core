// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LauncherPlugin} from "../../contracts/LauncherPlugin.sol";
import {ILauncherPlugin} from "../../contracts/interfaces/ILauncherPlugin.sol";

contract LauncherPluginTest is TestBase {
    LauncherPlugin public launcherPlugin;
    address public mockPool;
    address public mockFeeDist;
    address public mockNewPool;
    address public mockNewFeeDist;

    event NewOperator(address indexed _old, address indexed _new);
    event NewAuthority(address indexed _newAuthority);
    event RemovedAuthority(address indexed _previousAuthority);
    event EnabledPool(address indexed pool, string indexed _name);
    event DisabledPool(address indexed pool);
    event MigratedPool(address indexed oldPool, address indexed newPool);
    event Configured(address indexed pool, uint256 take, address indexed recipient);

    function setUp() public override {
        super.setUp();
        launcherPlugin = new LauncherPlugin(address(mockVoter), address(accessHub), alice);
        mockPool = makeAddr("mockPool");
        mockFeeDist = makeAddr("mockFeeDist");
        mockNewPool = makeAddr("mockNewPool");
        mockNewFeeDist = makeAddr("mockNewFeeDist");

        // Setup mock calls for mockVoter
        vm.mockCall(
            address(mockVoter), abi.encodeWithSignature("gaugeForPool(address)"), abi.encode(makeAddr("mockGauge"))
        );
        vm.mockCall(
            address(mockVoter), abi.encodeWithSignature("feeDistributorForGauge(address)"), abi.encode(mockFeeDist)
        );
    }

    function test_constructor() public view {
        assertEq(address(launcherPlugin.voter()), address(mockVoter));
        assertEq(launcherPlugin.accessHub(), address(accessHub));
        assertEq(launcherPlugin.operator(), alice);
    }

    function testFuzz_setConfigs(uint256 take, address recipient) public {
        vm.assume(take <= launcherPlugin.DENOM());
        vm.assume(recipient != address(0));

        // Enable pool first
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);

        // Set configs
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, true);
        emit Configured(mockPool, take, recipient);
        launcherPlugin.setConfigs(mockPool, take, recipient);

        // Verify configs
        (uint256 storedTake, address storedRecipient) = launcherPlugin.poolConfigs(mockPool);
        assertEq(storedTake, take);
        assertEq(storedRecipient, recipient);
    }

    function test_setConfigsReverts() public {
        // Test revert when pool not enabled
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_ENABLED(address)", mockPool));
        launcherPlugin.setConfigs(mockPool, 100, alice);

        // Enable pool
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);

        // Test revert when take > DENOM
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("INVALID_TAKE()"));
        launcherPlugin.setConfigs(mockPool, 10_001, alice);

        // Test revert when not authority
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORITY()"));
        launcherPlugin.setConfigs(mockPool, 100, alice);
    }

    function test_enablePool() public {
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit EnabledPool(mockPool, "accessHub");
        launcherPlugin.enablePool(mockPool);

        assertTrue(launcherPlugin.launcherPluginEnabled(mockPool));
        assertEq(launcherPlugin.feeDistToPool(mockFeeDist), mockPool);
    }

    function test_enablePoolReverts() public {
        // Enable pool first time
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);

        // Test revert when trying to enable already enabled pool
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ENABLED()"));
        launcherPlugin.enablePool(mockPool);

        // Test revert when not authority
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORITY()"));
        launcherPlugin.enablePool(mockNewPool);
    }

    function test_enablePoolNoFeeDist() public {
        // Mock mockVoter to return zero address for feeDist
        vm.mockCall(address(mockVoter), abi.encodeWithSignature("gaugeForPool(address)"), abi.encode(address(0)));
        vm.mockCall(
            address(mockVoter), abi.encodeWithSignature("feeDistributorForGauge(address)"), abi.encode(address(0))
        );

        // Enable pool
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit EnabledPool(mockPool, "accessHub");
        launcherPlugin.enablePool(mockPool);

        // Verify pool is enabled but no feeDist mapping exists
        assertTrue(launcherPlugin.launcherPluginEnabled(mockPool));
        assertEq(launcherPlugin.feeDistToPool(address(0)), mockPool);
    }

    function test_migratePool() public {
        // Setup initial pool
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);
        vm.prank(address(accessHub));
        launcherPlugin.setConfigs(mockPool, 100, alice);

        // Setup mock calls for new pool
        vm.mockCall(
            address(mockVoter), abi.encodeWithSignature("gaugeForPool(address)"), abi.encode(makeAddr("mockNewGauge"))
        );
        vm.mockCall(
            address(mockVoter), abi.encodeWithSignature("feeDistributorForGauge(address)"), abi.encode(mockNewFeeDist)
        );

        // Migrate pool
        vm.prank(address(mockVoter));
        vm.expectEmit(true, true, false, false);
        emit MigratedPool(mockPool, mockNewPool);
        launcherPlugin.migratePool(mockPool, mockNewPool);

        // Verify migration
        assertTrue(launcherPlugin.launcherPluginEnabled(mockNewPool));
        assertFalse(launcherPlugin.launcherPluginEnabled(mockPool));
        assertEq(launcherPlugin.feeDistToPool(mockNewFeeDist), mockNewPool);

        // Verify configs were copied
        (uint256 take, address recipient) = launcherPlugin.poolConfigs(mockNewPool);
        assertEq(take, 100);
        assertEq(recipient, alice);
    }

    function test_migratePoolReverts() public {
        // Test revert when old pool not enabled
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_ENABLED(address)", mockPool));
        launcherPlugin.migratePool(mockPool, mockNewPool);

        // Test revert when not authorized
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORIZED(address)", bob));
        launcherPlugin.migratePool(mockPool, mockNewPool);
    }

    function test_disablePool() public {
        // Enable pool first
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);
        vm.prank(address(accessHub));
        launcherPlugin.setConfigs(mockPool, 100, alice);

        // Disable pool
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit DisabledPool(mockPool);
        launcherPlugin.disablePool(mockPool);

        // Verify state
        assertFalse(launcherPlugin.launcherPluginEnabled(mockPool));
        (uint256 take, address recipient) = launcherPlugin.poolConfigs(mockPool);
        assertEq(take, 0);
        assertEq(recipient, address(0));
        assertEq(launcherPlugin.feeDistToPool(mockFeeDist), address(0));
    }

    function test_disablePoolReverts() public {
        // Test revert when pool not enabled
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_ENABLED(address)", mockPool));
        launcherPlugin.disablePool(mockPool);

        // Test revert when not operator
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_OPERATOR()"));
        launcherPlugin.disablePool(mockPool);
    }

    function test_setOperator() public {
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, false, false);
        emit NewOperator(alice, bob);
        launcherPlugin.setOperator(bob);

        assertEq(launcherPlugin.operator(), bob);
    }

    function test_setOperatorReverts() public {
        // Test revert when setting same operator
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ALREADY_OPERATOR()"));
        launcherPlugin.setOperator(alice);

        // Test revert when not operator
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_OPERATOR()"));
        launcherPlugin.setOperator(carol);
    }

    function test_grantAuthority() public {
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit NewAuthority(bob);
        launcherPlugin.grantAuthority(bob, "bob");

        assertTrue(launcherPlugin.authorityMap(bob));
    }

    function test_grantAuthorityReverts() public {
        // Grant authority first
        vm.prank(address(accessHub));
        launcherPlugin.grantAuthority(bob, "bob");

        // Test revert when already authority
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ALREADY_AUTHORITY()"));
        launcherPlugin.grantAuthority(bob, "bob");

        // Test revert when not operator
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSignature("NOT_OPERATOR()"));
        launcherPlugin.grantAuthority(carol, "carol");
    }

    function test_revokeAuthority() public {
        // Grant authority first
        vm.prank(address(accessHub));
        launcherPlugin.grantAuthority(bob, "bob");

        // Revoke authority
        vm.prank(address(accessHub));
        vm.expectEmit(true, false, false, false);
        emit RemovedAuthority(bob);
        launcherPlugin.revokeAuthority(bob);

        assertFalse(launcherPlugin.authorityMap(bob));
    }

    function test_revokeAuthorityReverts() public {
        // Test revert when not authority
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("NOT_AUTHORITY()"));
        launcherPlugin.revokeAuthority(bob);

        // Test revert when not operator
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NOT_OPERATOR()"));
        launcherPlugin.revokeAuthority(alice);
    }

    function test_values() public {
        // Setup pool with configs
        vm.prank(address(accessHub));
        launcherPlugin.enablePool(mockPool);
        vm.prank(address(accessHub));
        launcherPlugin.setConfigs(mockPool, 100, alice);

        // Test values function
        (uint256 take, address recipient) = launcherPlugin.values(mockFeeDist);
        assertEq(take, 100);
        assertEq(recipient, alice);
    }
}
