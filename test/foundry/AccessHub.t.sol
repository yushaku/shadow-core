// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {AccessHub} from "../../contracts/AccessHub.sol";
import {IVoter} from "../../contracts/interfaces/IVoter.sol";
import {IFeeCollector} from "../../contracts/CL/gauge/interfaces/IFeeCollector.sol";
import {IRamsesV3Factory} from "../../contracts/CL/core/interfaces/IRamsesV3Factory.sol";
import {IVoteModule} from "../../contracts/interfaces/IVoteModule.sol";
import {IPairFactory} from "../../contracts/interfaces/IPairFactory.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IMinter} from "../../contracts/interfaces/IMinter.sol";
import {IXShadow} from "../../contracts/interfaces/IXShadow.sol";
import {IAccessHub} from "../../contracts/interfaces/IAccessHub.sol";

contract AccessHubTest is TestBase {
    address public newTimelock = makeAddr("newTimelock");
    address public newTreasury = makeAddr("newTreasury");
    address public newGovernor = makeAddr("newGovernor");
    address public swapFeeSetter = makeAddr("swapFeeSetter");
    address public protocolOperator = makeAddr("protocolOperator");
    address[] public tokens;
    bool[] public whitelisted;
    address[] public pools;
    uint24[] public swapFees;
    uint8[] public clFeeSplits;
    uint256[] public legacyFeeSplits;
    bool[] public concentrated;

    MockLauncherPlugin public launcherPlugin;
    MockXShadow public xShadow;
    MockRamsesV3Factory public ramsesV3PoolFactory;
    MockPoolFactory public poolFactory;
    MockFeeCollector public feeCollector;
    MockFeeDistributorFactory public feeDistributorFactory;
    address public clGaugeFactory;
    address public gaugeFactory;
    address public voteModule;

    function setUp() public override {
        super.setUp();
        // Deploy mock contracts
        launcherPlugin = new MockLauncherPlugin();
        xShadow = new MockXShadow();
        ramsesV3PoolFactory = new MockRamsesV3Factory();
        poolFactory = new MockPoolFactory();
        feeCollector = new MockFeeCollector();
        feeDistributorFactory = new MockFeeDistributorFactory();
        clGaugeFactory = makeAddr("clGaugeFactory");
        gaugeFactory = makeAddr("gaugeFactory");
        voteModule = makeAddr("voteModule");

        // Create InitParams struct
        IAccessHub.InitParams memory params = IAccessHub.InitParams({
            timelock: TIMELOCK,
            treasury: TREASURY,
            voter: address(mockVoter),
            minter: address(mockMinter),
            launcherPlugin: address(launcherPlugin),
            xShadow: address(xShadow),
            x33: address(mockX33),
            ramsesV3PoolFactory: address(ramsesV3PoolFactory),
            poolFactory: address(poolFactory),
            clGaugeFactory: clGaugeFactory,
            gaugeFactory: gaugeFactory,
            feeRecipientFactory: address(feeRecipientFactory),
            feeDistributorFactory: address(feeDistributorFactory),
            feeCollector: address(feeCollector),
            voteModule: address(voteModule)
        });

        accessHub.initialize(params);

        // Setup roles
        vm.startPrank(TREASURY);
        accessHub.grantRole(accessHub.SWAP_FEE_SETTER(), swapFeeSetter);
        accessHub.grantRole(accessHub.PROTOCOL_OPERATOR(), protocolOperator);
        vm.stopPrank();

        // Setup arrays for batch operations
        tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        whitelisted = new bool[](2);
        whitelisted[0] = true;
        whitelisted[1] = false;

        pools = new address[](2);
        pools[0] = address(0x1);
        pools[1] = address(0x2);

        swapFees = new uint24[](2);
        swapFees[0] = 3000;
        swapFees[1] = 5000;

        concentrated = new bool[](2);
        concentrated[0] = true;
        concentrated[1] = false;

        clFeeSplits = new uint8[](2);
        clFeeSplits[0] = 50;
        clFeeSplits[1] = 30;

        legacyFeeSplits = new uint256[](2);
        legacyFeeSplits[0] = 50_000;
        legacyFeeSplits[1] = 30_000;

        vm.label(address(mockMinter), "mock_minter");
        vm.label(address(launcherPlugin), "launcher_plugin");
        vm.label(address(xShadow), "x_shadow");
        vm.label(address(ramsesV3PoolFactory), "ramses_v3_factory");
        vm.label(address(poolFactory), "pool_factory");
        vm.label(address(feeCollector), "fee_collector");
        vm.label(address(feeDistributorFactory), "fee_distributor_factory");
        vm.label(clGaugeFactory, "cl_gauge_factory");
        vm.label(gaugeFactory, "gauge_factory");
    }

    function test_constructor() public view {
        assertEq(accessHub.timelock(), TIMELOCK, "Incorrect timelock address");
        assertEq(accessHub.treasury(), TREASURY, "Incorrect treasury address");
    }

    function test_roles() public view {
        // Check admin roles
        assertTrue(accessHub.hasRole(accessHub.DEFAULT_ADMIN_ROLE(), TREASURY), "Treasury should have admin role");
        assertTrue(accessHub.hasRole(accessHub.DEFAULT_ADMIN_ROLE(), TIMELOCK), "Timelock should have admin role");

        // Check SWAP_FEE_SETTER role
        assertTrue(
            accessHub.hasRole(accessHub.SWAP_FEE_SETTER(), TREASURY), "Treasury should have swap fee setter role"
        );
        assertTrue(
            accessHub.hasRole(accessHub.SWAP_FEE_SETTER(), swapFeeSetter),
            "SwapFeeSetter should have swap fee setter role"
        );

        // Check PROTOCOL_OPERATOR role
        assertTrue(
            accessHub.hasRole(accessHub.PROTOCOL_OPERATOR(), TREASURY), "Treasury should have protocol operator role"
        );
        assertTrue(
            accessHub.hasRole(accessHub.PROTOCOL_OPERATOR(), protocolOperator),
            "ProtocolOperator should have protocol operator role"
        );

        // Verify role admin
        assertEq(
            accessHub.getRoleAdmin(accessHub.SWAP_FEE_SETTER()),
            accessHub.DEFAULT_ADMIN_ROLE(),
            "Incorrect admin for SWAP_FEE_SETTER role"
        );
        assertEq(
            accessHub.getRoleAdmin(accessHub.PROTOCOL_OPERATOR()),
            accessHub.DEFAULT_ADMIN_ROLE(),
            "Incorrect admin for PROTOCOL_OPERATOR role"
        );

        // Check role member counts
        assertEq(accessHub.getRoleMemberCount(accessHub.DEFAULT_ADMIN_ROLE()), 2, "Incorrect admin role member count");
        assertEq(
            accessHub.getRoleMemberCount(accessHub.SWAP_FEE_SETTER()), 2, "Incorrect swap fee setter role member count"
        );
        assertEq(
            accessHub.getRoleMemberCount(accessHub.PROTOCOL_OPERATOR()),
            2,
            "Incorrect protocol operator role member count"
        );

        // Verify role members
        assertEq(
            accessHub.getRoleMember(accessHub.DEFAULT_ADMIN_ROLE(), 0), TREASURY, "Incorrect first admin role member"
        );
        assertEq(
            accessHub.getRoleMember(accessHub.DEFAULT_ADMIN_ROLE(), 1), TIMELOCK, "Incorrect second admin role member"
        );
        assertEq(
            accessHub.getRoleMember(accessHub.SWAP_FEE_SETTER(), 0),
            TREASURY,
            "Incorrect first swap fee setter role member"
        );
        assertEq(
            accessHub.getRoleMember(accessHub.SWAP_FEE_SETTER(), 1),
            swapFeeSetter,
            "Incorrect second swap fee setter role member"
        );
        assertEq(
            accessHub.getRoleMember(accessHub.PROTOCOL_OPERATOR(), 0),
            TREASURY,
            "Incorrect first protocol operator role member"
        );
        assertEq(
            accessHub.getRoleMember(accessHub.PROTOCOL_OPERATOR(), 1),
            protocolOperator,
            "Incorrect second protocol operator role member"
        );
    }

    function test_setSwapFees() public {
        // Test that protocol operator cannot call
        vm.startPrank(protocolOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, protocolOperator, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setSwapFees(pools, swapFees, concentrated);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setSwapFees(pools, swapFees, concentrated);
        vm.stopPrank();

        // Test that swap fee setter can call
        vm.startPrank(swapFeeSetter);

        for (uint256 i = 0; i < pools.length; i++) {
            if (concentrated[i]) {
                vm.mockCall(
                    address(ramsesV3PoolFactory),
                    abi.encodeWithSelector(IRamsesV3Factory.setFee.selector, pools[i], swapFees[i]),
                    abi.encode()
                );
            } else {
                vm.mockCall(
                    address(poolFactory),
                    abi.encodeWithSelector(IPairFactory.setPairFee.selector, pools[i], swapFees[i]),
                    abi.encode()
                );
            }
        }

        /// @dev change now that there's 2 dif funcs
        accessHub.setSwapFees(pools, swapFees, concentrated);
        vm.stopPrank();
    }

    function test_setFeeSplitCL() public {
        // Test that protocol operator cannot call
        vm.startPrank(protocolOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, protocolOperator, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setFeeSplitCL(pools, clFeeSplits);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setFeeSplitCL(pools, clFeeSplits);
        vm.stopPrank();

        // Test that swap fee setter can call
        vm.startPrank(swapFeeSetter);
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(ramsesV3PoolFactory),
                abi.encodeWithSelector(IRamsesV3Factory.setPoolFeeProtocol.selector, pools[i], clFeeSplits[i]),
                abi.encode()
            );
        }
        accessHub.setFeeSplitCL(pools, clFeeSplits);
        vm.stopPrank();
    }

    function test_setFeeSplitLegacy() public {
        // Test that protocol operator cannot call
        vm.startPrank(protocolOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, protocolOperator, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, accessHub.SWAP_FEE_SETTER()
            )
        );
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);
        vm.stopPrank();

        // Test that swap fee setter can call
        vm.startPrank(swapFeeSetter);
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(poolFactory),
                abi.encodeWithSelector(IPairFactory.setPairFeeSplit.selector, pools[i], legacyFeeSplits[i]),
                abi.encode()
            );
        }
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);
        vm.stopPrank();
    }

    function test_setNewGovernorInVoter() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, swapFeeSetter, accessHub.PROTOCOL_OPERATOR()
            )
        );
        accessHub.setNewGovernorInVoter(newGovernor);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, accessHub.PROTOCOL_OPERATOR()
            )
        );
        accessHub.setNewGovernorInVoter(newGovernor);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        vm.mockCall(address(mockVoter), abi.encodeWithSelector(IVoter.setGovernor.selector, newGovernor), abi.encode());
        accessHub.setNewGovernorInVoter(newGovernor);
        vm.stopPrank();
    }

    function test_governanceWhitelist() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();

        // Test that protocol operator can call
        for (uint256 i = 0; i < tokens.length; i++) {
            if (whitelisted[i]) {
                vm.mockCall(
                    address(mockVoter), abi.encodeWithSelector(IVoter.whitelist.selector, tokens[i]), abi.encode()
                );
            } else {
                vm.mockCall(
                    address(mockVoter), abi.encodeWithSelector(IVoter.revokeWhitelist.selector, tokens[i]), abi.encode()
                );
            }
        }
        vm.startPrank(protocolOperator);
        accessHub.governanceWhitelist(tokens, whitelisted);
        vm.stopPrank();
    }

    function test_transferWhitelistInXShadow() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.transferWhitelistInXShadow(tokens, whitelisted);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.transferWhitelistInXShadow(tokens, whitelisted);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        vm.mockCall(
            address(xShadow), abi.encodeWithSelector(IXShadow.setExemption.selector, tokens, whitelisted), abi.encode()
        );
        accessHub.transferWhitelistInXShadow(tokens, whitelisted);
        vm.stopPrank();
    }

    function test_killGauge() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.killGauge(pools);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.killGauge(pools);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        // Mock successful fee collection for each pool
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(feeCollector),
                abi.encodeWithSelector(IFeeCollector.collectProtocolFees.selector, pools[i]),
                abi.encode()
            );
        }
        accessHub.killGauge(pools);
        vm.stopPrank();
    }

    function test_reviveGauge() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.reviveGauge(pools);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.reviveGauge(pools);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        // Mock successful fee collection for each pool
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(feeCollector),
                abi.encodeWithSelector(IFeeCollector.collectProtocolFees.selector, pools[i]),
                abi.encode()
            );

            vm.mockCall(
                address(ramsesV3PoolFactory),
                abi.encodeWithSelector(IRamsesV3Factory.feeProtocol.selector),
                abi.encode(5)
            );
            vm.mockCall(
                pools[i],
                abi.encodeWithSelector(IRamsesV3Factory.setPoolFeeProtocol.selector, pools[i], 5),
                abi.encode()
            );
        }
        accessHub.reviveGauge(pools);
        vm.stopPrank();
    }

    function test_setEmissionsRatioInVoter() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.setEmissionsRatioInVoter(5000);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.setEmissionsRatioInVoter(5000);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        vm.mockCall(address(mockVoter), abi.encodeWithSelector(IVoter.setGlobalRatio.selector, 5000), abi.encode());
        accessHub.setEmissionsRatioInVoter(5000); // 50%
        vm.stopPrank();
    }

    function test_setEmissionsMultiplierInMinter() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.setEmissionsMultiplierInMinter(200);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.setEmissionsMultiplierInMinter(200);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        vm.mockCall(
            address(mockMinter), abi.encodeWithSelector(IMinter.updateEmissionsMultiplier.selector, 200), abi.encode()
        );
        accessHub.setEmissionsMultiplierInMinter(200); // 2x
        vm.stopPrank();
    }

    function test_augmentGaugeRewardsForPair() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.augmentGaugeRewardsForPair(pools, tokens, whitelisted);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.augmentGaugeRewardsForPair(pools, tokens, whitelisted);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        for (uint256 i = 0; i < pools.length; i++) {
            address mockGauge = makeAddr(string.concat("gauge_", vm.toString(i)));

            // Mock the gauge lookup call
            vm.mockCall(
                address(mockVoter),
                abi.encodeWithSelector(IVoter.gaugeForPool.selector, pools[i]),
                abi.encode(mockGauge)
            );

            // Mock the whitelist/remove reward calls based on whitelisted flag
            if (whitelisted[i]) {
                vm.mockCall(
                    address(mockVoter),
                    abi.encodeWithSelector(IVoter.whitelistGaugeRewards.selector, mockGauge, tokens[i]),
                    abi.encode()
                );
            } else {
                vm.mockCall(
                    address(mockVoter),
                    abi.encodeWithSelector(IVoter.removeGaugeRewardWhitelist.selector, mockGauge, tokens[i]),
                    abi.encode()
                );
            }
        }
        accessHub.augmentGaugeRewardsForPair(pools, tokens, whitelisted);
        vm.stopPrank();
    }

    function test_removeFeeDistributorRewards() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.removeFeeDistributorRewards(pools, tokens);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.removeFeeDistributorRewards(pools, tokens);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        for (uint256 i = 0; i < pools.length; i++) {
            address mockFeeDistributor = makeAddr(string.concat("fee_distributor_", vm.toString(i)));
            vm.mockCall(
                address(mockVoter),
                abi.encodeWithSelector(IVoter.feeDistributorForGauge.selector, pools[i]),
                abi.encode(mockFeeDistributor)
            );
        }
        accessHub.removeFeeDistributorRewards(pools, tokens);
        vm.stopPrank();
    }

    function test_launcherPluginFunctions() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.migratePoolInLauncherPlugin(pools[0], pools[1]);
        vm.expectRevert();
        accessHub.setConfigsInLauncherPlugin(pools[0], 1000, newTreasury);
        vm.expectRevert();
        accessHub.enablePoolInLauncherPlugin(pools[0]);
        vm.expectRevert();
        accessHub.disablePoolInLauncherPlugin(pools[0]);
        vm.expectRevert();
        accessHub.setOperatorInLauncherPlugin(newTreasury);
        vm.expectRevert();
        accessHub.grantAuthorityInLauncherPlugin(newTreasury, "treasury");
        vm.expectRevert();
        accessHub.revokeAuthorityInLauncherPlugin(TREASURY);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.migratePoolInLauncherPlugin(pools[0], pools[1]);
        vm.expectRevert();
        accessHub.setConfigsInLauncherPlugin(pools[0], 1000, newTreasury);
        vm.expectRevert();
        accessHub.enablePoolInLauncherPlugin(pools[0]);
        vm.expectRevert();
        accessHub.disablePoolInLauncherPlugin(pools[0]);
        vm.expectRevert();
        accessHub.setOperatorInLauncherPlugin(newTreasury);
        vm.expectRevert();
        accessHub.grantAuthorityInLauncherPlugin(newTreasury, "treasury");
        vm.expectRevert();
        accessHub.revokeAuthorityInLauncherPlugin(TREASURY);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        accessHub.migratePoolInLauncherPlugin(pools[0], pools[1]);
        accessHub.setConfigsInLauncherPlugin(pools[0], 1000, newTreasury);
        accessHub.enablePoolInLauncherPlugin(pools[0]);
        accessHub.disablePoolInLauncherPlugin(pools[0]);
        accessHub.setOperatorInLauncherPlugin(newTreasury);
        accessHub.grantAuthorityInLauncherPlugin(newTreasury, "treasury");
        accessHub.revokeAuthorityInLauncherPlugin(TREASURY);
        vm.stopPrank();
    }

    function test_feeCollectorFunctions() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.setTreasuryInFeeCollector(newTreasury);
        vm.expectRevert();
        accessHub.setTreasuryFeesInFeeCollector(1000);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.setTreasuryInFeeCollector(newTreasury);
        vm.expectRevert();
        accessHub.setTreasuryFeesInFeeCollector(1000);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        vm.mockCall(
            address(feeCollector), abi.encodeWithSelector(IFeeCollector.setTreasury.selector, newTreasury), abi.encode()
        );
        accessHub.setTreasuryInFeeCollector(newTreasury);
        vm.mockCall(
            address(feeCollector), abi.encodeWithSelector(IFeeCollector.setTreasuryFees.selector, 1000), abi.encode()
        );
        accessHub.setTreasuryFeesInFeeCollector(1000);
        vm.stopPrank();
    }

    function test_feeRecipientFactoryFunctions() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.setFeeToTreasuryInFeeRecipientFactory(1000);
        vm.expectRevert();
        accessHub.setTreasuryInFeeRecipientFactory(newTreasury);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.setFeeToTreasuryInFeeRecipientFactory(1000);
        vm.expectRevert();
        accessHub.setTreasuryInFeeRecipientFactory(newTreasury);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        accessHub.setFeeToTreasuryInFeeRecipientFactory(1000);
        accessHub.setTreasuryInFeeRecipientFactory(newTreasury);
        vm.stopPrank();
    }

    function test_enableTickSpacing() public {
        // Test that swap fee setter cannot call
        vm.startPrank(swapFeeSetter);
        vm.expectRevert();
        accessHub.enableTickSpacing(100, 3000);
        vm.stopPrank();

        // Test that random address cannot call
        vm.startPrank(alice);
        vm.expectRevert();
        accessHub.enableTickSpacing(100, 3000);
        vm.stopPrank();

        // Test that protocol operator can call
        vm.startPrank(protocolOperator);
        accessHub.enableTickSpacing(100, 3000);
        vm.stopPrank();
    }

    function test_setNewTimelockRevertsForSameAddress() public {
        vm.startPrank(TIMELOCK);
        vm.expectRevert(IAccessHub.SAME_ADDRESS.selector);
        accessHub.setNewTimelock(TIMELOCK);
        vm.stopPrank();
    }

    function test_unauthorizedAccessReverts() public {
        vm.startPrank(alice);

        vm.expectRevert();
        accessHub.setSwapFees(pools, swapFees, concentrated);

        vm.expectRevert();
        accessHub.setFeeSplitCL(pools, clFeeSplits);

        vm.expectRevert();
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);

        vm.expectRevert();
        accessHub.setNewGovernorInVoter(newGovernor);

        vm.expectRevert();
        accessHub.setNewTimelock(newTimelock);

        vm.stopPrank();
    }

    function test_lengthMismatchReverts() public {
        vm.startPrank(swapFeeSetter);

        // Create mismatched arrays
        address[] memory shortPools = new address[](1);
        shortPools[0] = pools[0];

        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        accessHub.setSwapFees(shortPools, swapFees, concentrated);

        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        accessHub.setFeeSplitCL(shortPools, clFeeSplits);

        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        accessHub.setFeeSplitLegacy(shortPools, legacyFeeSplits);

        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSignature("LENGTH_MISMATCH()"));
        accessHub.governanceWhitelist(shortPools, whitelisted);
    }

    function test_setCannotBeCalledTwice() public {
        vm.startPrank(protocolOperator);

        // Create InitParams struct for second initialization attempt
        IAccessHub.InitParams memory params = IAccessHub.InitParams({
            timelock: TIMELOCK,
            treasury: TREASURY,
            voter: address(mockVoter),
            minter: address(mockMinter),
            launcherPlugin: address(launcherPlugin),
            xShadow: address(xShadow),
            x33: address(mockX33),
            ramsesV3PoolFactory: address(ramsesV3PoolFactory),
            poolFactory: address(poolFactory),
            clGaugeFactory: clGaugeFactory,
            gaugeFactory: gaugeFactory,
            feeRecipientFactory: address(feeRecipientFactory),
            feeDistributorFactory: address(feeDistributorFactory),
            feeCollector: address(feeCollector),
            voteModule: address(voteModule)
        });

        vm.expectRevert();
        accessHub.initialize(params);

        vm.stopPrank();
    }

    function test_swapFeeSetterRoleAccess() public {
        // Test SWAP_FEE_SETTER role functions
        vm.startPrank(protocolOperator);
        vm.expectRevert();
        accessHub.setSwapFees(pools, swapFees, concentrated);

        vm.expectRevert();
        accessHub.setFeeSplitCL(pools, clFeeSplits);
        vm.expectRevert();
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);
        vm.stopPrank();

        // Should work with correct role
        vm.startPrank(swapFeeSetter);
        for (uint256 i = 0; i < pools.length; i++) {
            if (concentrated[i]) {
                vm.mockCall(
                    address(ramsesV3PoolFactory),
                    abi.encodeWithSelector(IRamsesV3Factory.setFee.selector, pools[i], swapFees[i]),
                    abi.encode()
                );
            } else {
                vm.mockCall(
                    address(poolFactory),
                    abi.encodeWithSelector(IPairFactory.setPairFee.selector, pools[i], swapFees[i]),
                    abi.encode()
                );
            }
        }
        accessHub.setSwapFees(pools, swapFees, concentrated);
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(ramsesV3PoolFactory),
                abi.encodeWithSelector(IRamsesV3Factory.setPoolFeeProtocol.selector, pools[i], clFeeSplits[i]),
                abi.encode()
            );
        }
        accessHub.setFeeSplitCL(pools, clFeeSplits);

        // Test Legacy fee splits
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(
                address(poolFactory),
                abi.encodeWithSelector(IPairFactory.setPairFeeSplit.selector, pools[i], legacyFeeSplits[i]),
                abi.encode()
            );
        }
        accessHub.setFeeSplitLegacy(pools, legacyFeeSplits);
        vm.stopPrank();
    }

    function test_protocolOperatorRoleAccess() public {
        // Test PROTOCOL_OPERATOR role functions
        vm.startPrank(swapFeeSetter);

        vm.expectRevert();
        accessHub.setNewGovernorInVoter(newGovernor);

        vm.expectRevert();
        accessHub.governanceWhitelist(tokens, whitelisted);

        vm.expectRevert();
        accessHub.killGauge(pools);
        vm.stopPrank();

        // Should work with correct role
        vm.startPrank(protocolOperator);
        vm.mockCall(address(mockVoter), abi.encodeWithSelector(IVoter.setGovernor.selector, newGovernor), abi.encode());
        accessHub.setNewGovernorInVoter(newGovernor);
        vm.stopPrank();
    }

    function test_executeTimelockAccess() public {
        // Test execute function with non-timelock address
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.execute(address(0), "");
        vm.stopPrank();

        vm.startPrank(TREASURY);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, TREASURY));
        accessHub.execute(address(0), "");
        vm.stopPrank();

        // Should work with timelock
        vm.startPrank(TIMELOCK);
        accessHub.execute(address(0), "");
        vm.stopPrank();
    }

    function test_setNewTimelockAccess() public {
        // Test setNewTimelock function with non-timelock address
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.setNewTimelock(newTimelock);
        vm.stopPrank();

        vm.startPrank(TREASURY);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, TREASURY));
        accessHub.setNewTimelock(newTimelock);
        vm.stopPrank();

        // Should work with timelock
        vm.startPrank(TIMELOCK);
        accessHub.setNewTimelock(newTimelock);
        vm.stopPrank();
    }

    function test_setCooldownExemption() public {
        address[] memory candidates = new address[](2);
        candidates[0] = address(0x1);
        candidates[1] = address(0x2);
        bool[] memory exempt = new bool[](2);
        exempt[0] = true;
        exempt[1] = false;

        // Test non-timelock access
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));

        accessHub.setCooldownExemption(candidates, exempt);
        vm.stopPrank();

        // Test with timelock
        vm.startPrank(TIMELOCK);

        for (uint256 i = 0; i < candidates.length; i++) {
            vm.mockCall(
                address(voteModule),
                abi.encodeWithSelector(IVoteModule.setCooldownExemption.selector, candidates[i], exempt[i]),
                abi.encode()
            );
        }
        accessHub.setCooldownExemption(candidates, exempt);

        vm.stopPrank();
    }

    function test_setNewRebaseStreamingDuration() public {
        // Test non-timelock access
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.setNewRebaseStreamingDuration(1000);
        vm.stopPrank();

        // Test with timelock
        vm.startPrank(TIMELOCK);
        vm.mockCall(
            address(voteModule), abi.encodeWithSelector(IVoteModule.setNewDuration.selector, 1000), abi.encode()
        );
        accessHub.setNewRebaseStreamingDuration(1000);
        vm.stopPrank();
    }

    function test_setNewVoteModuleCooldown() public {
        // Test non-timelock access
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.setNewVoteModuleCooldown(1000);
        vm.stopPrank();

        // Test with timelock
        vm.startPrank(TIMELOCK);
        vm.mockCall(
            address(voteModule), abi.encodeWithSelector(IVoteModule.setNewCooldown.selector, 1000), abi.encode()
        );
        accessHub.setNewVoteModuleCooldown(1000);
        vm.stopPrank();
    }

    function test_setVoterAddressInFactoryV3() public {
        address newVoter = makeAddr("newVoter");

        // Test non-timelock access
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.setVoterAddressInFactoryV3(newVoter);
        vm.stopPrank();

        // Test with timelock
        vm.startPrank(TIMELOCK);
        vm.mockCall(
            address(ramsesV3PoolFactory),
            abi.encodeWithSelector(IRamsesV3Factory.setVoter.selector, newVoter),
            abi.encode()
        );
        accessHub.setVoterAddressInFactoryV3(newVoter);
        vm.stopPrank();
    }

    function test_initializeVoter() public {
        address shadow = makeAddr("shadow");
        address legacyFactory = makeAddr("legacyFactory");
        address gauges = makeAddr("gauges");
        address msig = makeAddr("msig");
        address nfpManager = makeAddr("nfpManager");

        // Test non-timelock access
        vm.startPrank(protocolOperator);
        vm.expectRevert(abi.encodeWithSelector(IAccessHub.NOT_TIMELOCK.selector, protocolOperator));
        accessHub.initializeVoter(
            shadow,
            legacyFactory,
            gauges,
            address(feeDistributorFactory),
            address(mockMinter),
            msig,
            address(xShadow),
            address(ramsesV3PoolFactory),
            clGaugeFactory,
            nfpManager,
            address(feeRecipientFactory),
            voteModule,
            address(launcherPlugin)
        );
        vm.stopPrank();

        // Test with timelock
        vm.startPrank(TIMELOCK);
        accessHub.initializeVoter(
            shadow,
            legacyFactory,
            gauges,
            address(feeDistributorFactory),
            address(mockMinter),
            msig,
            address(xShadow),
            address(ramsesV3PoolFactory),
            clGaugeFactory,
            nfpManager,
            address(feeRecipientFactory),
            voteModule,
            address(launcherPlugin)
        );
        vm.stopPrank();
    }

    function test_executeFailure() public {
        // Create a contract that will revert
        MockFailingContract failingContract = new MockFailingContract();

        vm.startPrank(TIMELOCK);
        vm.expectRevert(IAccessHub.MANUAL_EXECUTION_FAILURE.selector);
        accessHub.execute(address(failingContract), abi.encodeWithSignature("failingFunction()"));
        vm.stopPrank();
    }
}

// ------------ MOCKS ------------

contract MockLauncherPlugin {
    address public operator;
    mapping(address => bool) public poolEnabled;
    mapping(address => uint256) public poolConfigs;
    mapping(address => address) public poolTreasuries;
    mapping(address => bool) public authorities;

    function migratePool(address _oldPool, address _newPool) external {}

    function setConfigs(address _pool, uint256 _config, address _treasury) external {
        poolConfigs[_pool] = _config;
        poolTreasuries[_pool] = _treasury;
    }

    function enablePool(address _pool) external {
        poolEnabled[_pool] = true;
    }

    function disablePool(address _pool) external {
        poolEnabled[_pool] = false;
    }

    function setOperator(address _operator) external {
        operator = _operator;
    }

    function grantAuthority(address _authority, string calldata _name) external {
        authorities[_authority] = true;
        _name;
    }

    function revokeAuthority(address _authority) external {
        authorities[_authority] = false;
    }
}

contract MockXShadow {
    mapping(address => bool) public transferWhitelist;

    function setExemption(address[] calldata _who, bool[] calldata _whitelisted) external {
        for (uint256 i = 0; i < _who.length; i++) {
            transferWhitelist[_who[i]] = _whitelisted[i];
        }
    }
}

contract MockRamsesV3Factory {
    mapping(int24 => uint24) public tickSpacing;
    mapping(address => uint8) public poolFeeProtocol;
    mapping(address => uint24) public poolFees;

    function enableTickSpacing(int24 _spacing, uint24 _fee) external {
        tickSpacing[_spacing] = _fee;
    }

    function setPoolFeeProtocol(address _pool, uint8 _feeProtocol) external {
        poolFeeProtocol[_pool] = _feeProtocol;
    }

    function setFee(address _pool, uint24 _fee) external {
        poolFees[_pool] = _fee;
    }
}

contract MockPoolFactory {
    mapping(address => uint256) public swapFees;
    mapping(address => uint256) public feeSplits;

    function setPairFee(address _pool, uint256 _fee) external {
        swapFees[_pool] = _fee;
    }

    function setPairFeeSplit(address _pool, uint256 _split) external {
        feeSplits[_pool] = _split;
    }
}

contract MockFeeCollector {
    address public treasury;
    uint256 public treasuryFees;

    function setTreasury(address _treasury) external {
        treasury = _treasury;
    }

    function setTreasuryFees(uint256 _fees) external {
        treasuryFees = _fees;
    }
}

contract MockFeeRecipientFactory {
    address public treasury;
    uint256 public feeToTreasury;

    function setFeeToTreasury(uint256 _feeToTreasury) external {
        feeToTreasury = _feeToTreasury;
    }

    function setTreasury(address _treasury) external {
        treasury = _treasury;
    }
}

contract MockFeeDistributorFactory {
    mapping(address => mapping(address => bool)) public removedRewards;

    function removeRewards(address _pool, address _token) external {
        removedRewards[_pool][_token] = true;
    }
}

contract MockFailingContract {
    function failingFunction() external pure {
        revert("FORCED_FAILURE");
    }
}

contract MockX33 {
    address public operator;
    address public accessHub;
    address public xShadow;
    address public voter;
    address public voteModule;

    function initialize(address _operator, address _accessHub, address _xShadow, address _voter, address _voteModule)
        external
    {
        operator = _operator;
        accessHub = _accessHub;
        xShadow = _xShadow;
        voter = _voter;
        voteModule = _voteModule;
    }
}
