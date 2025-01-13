// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "../TestBase.sol";
import {PairFactory} from "../../../contracts/factories/PairFactory.sol";
import {Pair} from "../../../contracts/Pair.sol";
import {AccessHub} from "../../../contracts/AccessHub.sol";
import {IPairFactory} from "../../../contracts/interfaces/IPairFactory.sol";
import {IPair} from "../../../contracts/interfaces/IPair.sol";

contract PairFactoryTest is TestBase {
    PairFactory public factory;
    address public newTreasury = makeAddr("newTreasury");

    function setUp() public override {
        super.setUp();
        factory = new PairFactory(address(mockVoter), TREASURY, address(accessHub), address(feeRecipientFactory));
    }

    function test_constructor() public view {
        assertEq(factory.voter(), address(mockVoter), "Voter address mismatch");
        assertEq(factory.treasury(), TREASURY, "Treasury address mismatch");
        assertEq(factory.accessHub(), address(accessHub), "AccessHub address mismatch");
        assertEq(factory.feeRecipientFactory(), address(feeRecipientFactory), "FeeRecipientFactory address mismatch");
        assertEq(factory.fee(), 3000, "Default fee should be 0.30%");
    }

    function test_createPair() public {
        address pair = factory.createPair(address(token0), address(token1), true);

        assertTrue(factory.isPair(pair), "Pair should be registered");
        assertEq(factory.allPairs(0), pair, "First pair should match created pair");
        assertEq(factory.allPairsLength(), 1, "Should have exactly one pair");
        assertEq(factory.getPair(address(token0), address(token1), true), pair, "Forward pair lookup failed");
        assertEq(factory.getPair(address(token1), address(token0), true), pair, "Reverse pair lookup failed");
    }

    function test_createPairRevertsForSameTokens() public {
        vm.expectRevert(abi.encodeWithSignature("IA()"));
        factory.createPair(address(token0), address(token0), true);
    }

    function test_createPairRevertsForZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZA()"));
        factory.createPair(address(0), address(token1), true);
    }

    function test_createPairRevertsForExistingPair() public {
        factory.createPair(address(token0), address(token1), true);
        vm.expectRevert(abi.encodeWithSignature("PE()"));
        factory.createPair(address(token0), address(token1), true);
    }

    function test_setFee() public {
        uint256 newFee = 5000;
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SetFee(newFee);
        factory.setFee(newFee);
        assertEq(factory.fee(), newFee, "Fee not updated correctly");
    }

    function test_setFeeRevertsForUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setFee(5000);
    }

    function test_setFeeRevertsForZeroFee() public {
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("ZERO_FEE()"));
        factory.setFee(0);
    }

    function test_setFeeRevertsForTooHighFee() public {
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("FEE_TOO_HIGH()"));
        factory.setFee(100_001);
    }

    function test_setPairFee() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        uint256 newFee = 5000;

        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SetPairFee(pair, newFee);
        factory.setPairFee(pair, newFee);
        assertEq(factory.pairFee(pair), newFee, "Pair fee not set in factory");
        assertEq(IPair(pair).fee(), newFee, "Pair fee not set in pair contract");
    }

    function test_setTreasury() public {
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.NewTreasury(address(accessHub), newTreasury);
        factory.setTreasury(newTreasury);
        assertEq(factory.treasury(), newTreasury, "Treasury not updated correctly");
    }

    function test_setTreasuryRevertsForUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setTreasury(address(newTreasury));
    }

    function test_setFeeSplitWhenNoGauge() public {
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.FeeSplitWhenNoGauge(address(accessHub), true);
        factory.setFeeSplitWhenNoGauge(true);
        assertTrue(factory.feeSplitWhenNoGauge(), "FeeSplitWhenNoGauge not set correctly");
    }

    function test_setFeeSplit() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        uint256 newFeeSplit = 9500;
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SetFeeSplit(newFeeSplit);
        factory.setFeeSplit(newFeeSplit);
        assertEq(factory.feeSplit(), newFeeSplit, "FeeSplit not set correctly in factory");
        assertNotEq(IPair(pair).feeSplit(), newFeeSplit, "FeeSplit should not be set in pair contract");
    }

    function test_setFeeSplitRevertsForInvalidValue() public {
        vm.prank(address(accessHub));
        vm.expectRevert(abi.encodeWithSignature("INVALID_FEE_SPLIT()"));
        factory.setFeeSplit(10_001);
    }

    function test_setPairFeeSplit() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        uint256 newFeeSplit = 9500;

        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SetPairFeeSplit(pair, newFeeSplit);
        factory.setPairFeeSplit(pair, newFeeSplit);
        assertEq(IPair(pair).feeSplit(), newFeeSplit, "Pair feeSplit not set correctly");
    }

    function test_setFeeRecipient() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        address newFeeRecipient = address(newTreasury);

        vm.prank(address(mockVoter));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SetFeeRecipient(pair, newFeeRecipient);
        factory.setFeeRecipient(pair, newFeeRecipient);
        assertEq(IPair(pair).feeRecipient(), newFeeRecipient, "FeeRecipient not set correctly");
    }

    function test_setFeeRecipientRevertsForUnauthorized() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        vm.prank(alice);
        vm.expectRevert();
        factory.setFeeRecipient(pair, address(newTreasury));
    }

    function test_setSkimEnabled() public {
        address pair = factory.createPair(address(token0), address(token1), true);

        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SkimStatus(pair, true);
        factory.setSkimEnabled(pair, true);
        assertTrue(factory.skimEnabled(pair), "Skim not enabled correctly");
        // Setting same status should not change the value
        vm.prank(address(accessHub));
        vm.expectEmit(true, true, true, true);
        emit IPairFactory.SkimStatus(pair, true);
        factory.setSkimEnabled(pair, true);
        assertTrue(factory.skimEnabled(pair), "Skim status should remain enabled");
    }

    function test_setSkimEnabledRevertsForUnauthorized() public {
        address pair = factory.createPair(address(token0), address(token1), true);
        vm.prank(alice);
        vm.expectRevert();
        factory.setSkimEnabled(pair, true);
    }

    function test_pairCodeHash() public {
        bytes32 expectedHash = keccak256(abi.encodePacked(type(Pair).creationCode));
        assertEq(factory.pairCodeHash(), expectedHash, "PairCodeHash mismatch");
    }

    function test_createPairEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        // Determine token0 and token1 based on addresses
        address token0Local = address(token0) < address(token1) ? address(token0) : address(token1);
        address token1Local = address(token0) < address(token1) ? address(token1) : address(token0);
        emit IPairFactory.PairCreated(
            address(token0Local), // token0 is smaller address
            address(token1Local),
            computePairAddress(address(token0Local), address(token1Local), true), // predicted pair address
            1 // first pair
        );
        factory.createPair(address(token0), address(token1), true);
    }

    // Helper function to compute pair address (you may already have this)
    function computePairAddress(address token0, address token1, bool stable) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(abi.encodePacked(type(Pair).creationCode)))
        );
        return address(uint160(uint256(hash)));
    }

    function test_onlyGovernanceOrVoterFunctions() public {
        address pair = factory.createPair(address(token0), address(token1), true);

        // Test setFee can be called by voter and governance
        vm.prank(address(mockVoter));
        factory.setFee(5000); // Should work with voter
        vm.prank(address(accessHub));
        factory.setFee(6000); // Should work with governance

        // Test setPairFee can be called by voter and governance
        vm.prank(address(mockVoter));
        factory.setPairFee(pair, 5000); // Should work with voter
        vm.prank(address(accessHub));
        factory.setPairFee(pair, 6000); // Should work with governance

        // Test setFeeSplit can be called by voter and governance
        vm.prank(address(mockVoter));
        factory.setFeeSplit(9000); // Should work with voter
        vm.prank(address(accessHub));
        factory.setFeeSplit(9500); // Should work with governance

        // Test setPairFeeSplit can be called by voter and governance
        vm.prank(address(mockVoter));
        factory.setPairFeeSplit(pair, 9000); // Should work with voter
        vm.prank(address(accessHub));
        factory.setPairFeeSplit(pair, 9500); // Should work with governance
    }

    function test_onlyGovernanceFunctions() public {
        address pair = factory.createPair(address(token0), address(token1), true);

        // Test setTreasury can be called by governance
        vm.prank(address(accessHub));
        factory.setTreasury(newTreasury);
        vm.prank(address(mockVoter)); // mockVoter should not be able to call this
        vm.expectRevert();
        factory.setTreasury(newTreasury);

        // Test setFeeSplitWhenNoGauge can be called by governance
        vm.prank(address(accessHub));
        factory.setFeeSplitWhenNoGauge(true);
        vm.prank(address(mockVoter)); // mockVoter should not be able to call this
        vm.expectRevert();
        factory.setFeeSplitWhenNoGauge(true);

        // Test setSkimEnabled can be called by governance
        vm.prank(address(accessHub));
        factory.setSkimEnabled(pair, true);
        vm.prank(address(mockVoter)); // mockVoter should not be able to call this
        vm.expectRevert();
        factory.setSkimEnabled(pair, true);
    }

    function test_onlyGovernanceOrVoterFunctionsRevertForUnauthorized() public {
        address pair = factory.createPair(address(token0), address(token1), true);

        // Test setFee
        vm.prank(alice);
        vm.expectRevert();
        factory.setFee(5000);

        // Test setPairFee
        vm.prank(alice);
        vm.expectRevert();
        factory.setPairFee(pair, 5000);

        // Test setFeeSplit
        vm.prank(alice);
        vm.expectRevert();
        factory.setFeeSplit(9000);

        // Test setPairFeeSplit
        vm.prank(alice);
        vm.expectRevert();
        factory.setPairFeeSplit(pair, 9000);
    }
}
