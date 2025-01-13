// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import "erc4626-tests/ERC4626.test.sol";
// import {Voter} from "../../contracts/Voter.sol";
// import {VoteModule} from "../../contracts/VoteModule.sol";
// import {XShadow} from "../../contracts/xShadow/xShadow.sol";
// import {AccessHub} from "../../contracts/AccessHub.sol";
// import {x33 as X33Vault} from "../../contracts/xShadow/x33.sol";
// import {PairFactory} from "../../contracts/factories/PairFactory.sol";
// import {GaugeFactory} from "../../contracts/factories/GaugeFactory.sol";
// import {FeeDistributorFactory} from "../../contracts/factories/FeeDistributorFactory.sol";
// import {FeeRecipientFactory} from "../../contracts/factories/FeeRecipientFactory.sol";
// import {Shadow} from "../../contracts/Shadow.sol";
// import {TestBase as CustomTestBase} from "./TestBase.sol";
// import {MockMinter} from "./TestBase.sol";
// import {MockLauncherPlugin} from "./TestBase.sol";
// import {MockFeeCollector} from "./TestBase.sol";
// import {IAccessHub} from "../../contracts/interfaces/IAccessHub.sol";

// contract x33Base is CustomTestBase {
//     function setUp() public override {
//         super.setUp();
//     }
// }

// contract x33TestProperty is ERC4626Test, CustomTestBase {
//     Voter public voter;
//     address public constant CL_FACTORY = address(0xabc);
//     address public constant CL_GAUGE_FACTORY = address(0xdef);
//     address public constant NFP_MANAGER = address(0xbcd);
//     address public constant PROTOCOL_OPERATOR = address(0x123);
//     address public constant FEE_COLLECTOR = address(0x123);

//     XShadow public xShadow;
//     VoteModule public voteModule;
//     PairFactory public pairFactory;
//     GaugeFactory public gaugeFactory;
//     FeeDistributorFactory public feeDistributorFactory;

//     function setUp() public override(CustomTestBase, ERC4626Test) {
//         console.log("x33Test.setUp");
//         CustomTestBase.setUp();
//         voter = new Voter(address(accessHub));
//         mockMinter = new MockMinter();

//         voteModule = new VoteModule();

//         xShadow = new XShadow(
//             address(shadow),
//             address(voter),
//             address(TREASURY),
//             address(accessHub),
//             address(voteModule),
//             address(mockMinter)
//         );
//         feeRecipientFactory = new FeeRecipientFactory(TREASURY, address(voter), address(accessHub));
//         pairFactory =
//             new PairFactory(address(voter), address(TREASURY), address(accessHub), address(feeRecipientFactory));
//         gaugeFactory = new GaugeFactory();
//         feeDistributorFactory = new FeeDistributorFactory();
//         voteModule.initialize(address(xShadow), address(voter), address(accessHub));

//         vm.startPrank(address(TIMELOCK));

//         // Create InitParams struct
//         IAccessHub.InitParams memory params = IAccessHub.InitParams({
//             timelock: TIMELOCK,
//             treasury: TREASURY,
//             voter: address(voter),
//             minter: address(mockMinter),
//             launcherPlugin: address(mockLauncherPlugin),
//             xShadow: address(xShadow),
//             x33: address(mockX33),
//             ramsesV3PoolFactory: address(CL_FACTORY),
//             poolFactory: address(pairFactory),
//             clGaugeFactory: CL_GAUGE_FACTORY,
//             gaugeFactory: address(gaugeFactory),
//             feeRecipientFactory: address(feeRecipientFactory),
//             feeDistributorFactory: address(feeDistributorFactory),
//             feeCollector: address(mockFeeCollector),
//             voteModule: address(voteModule)
//         });

//         accessHub.initialize(params);

//         accessHub.initializeVoter(
//             address(shadow),
//             address(pairFactory),
//             address(gaugeFactory),
//             address(feeDistributorFactory),
//             address(mockMinter),
//             TREASURY,
//             address(xShadow),
//             CL_FACTORY,
//             CL_GAUGE_FACTORY,
//             NFP_MANAGER,
//             address(feeRecipientFactory),
//             address(voteModule),
//             address(mockLauncherPlugin)
//         );
//         accessHub.grantRole(accessHub.PROTOCOL_OPERATOR(), PROTOCOL_OPERATOR);

//         vm.startPrank(address(PROTOCOL_OPERATOR));
//         address[] memory tokens = new address[](5);
//         tokens[0] = address(shadow);
//         tokens[1] = address(token0);
//         tokens[2] = address(token1);
//         tokens[3] = address(xShadow);
//         tokens[4] = address(token6Decimals);
//         bool[] memory whitelisted = new bool[](5);
//         whitelisted[0] = true;
//         whitelisted[1] = true;
//         whitelisted[2] = true;
//         whitelisted[3] = true;
//         whitelisted[4] = true;
//         accessHub.governanceWhitelist(tokens, whitelisted);
//         vm.stopPrank();
//         _underlying_ = address(xShadow);
//         _vault_ = address(
//             new X33Vault(address(TREASURY), address(accessHub), address(xShadow), address(voter), address(voteModule))
//         );
//         _delta_ = 0;
//         _vaultMayBeEmpty = false;
//         _unlimitedAmount = false;
//     }
// }
