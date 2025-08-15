// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";

import {YSK} from "contracts/YSK.sol";
import {XY} from "contracts/x/XY.sol";
import {XYZ} from "contracts/x/XYZ.sol";
import {Voter} from "contracts/Voter.sol";
// import {Treasury} from "contracts/Treasury.sol"
import {PairFactory} from "contracts/factories/PairFactory.sol";

import "./Helper.s.sol";

contract Deploy is Script {
	Helper.Config public config;

	address[] public tokens;

	YSK public ysk;
	XY public xYushaku;
	XYZ public stakeYsk;

	Voter public voter;
	PairFactory public pairFactory;

	function _beforeSetup() public {
		Helper helper = new Helper();
		Helper.Config memory _config = helper.getConfig();
		config = _config;
	}

	function _coreSetup() public {
		ysk = new YSK(config.deployer);
		tokens.push(address(ysk));

		// TODO: need to deploy needed contract before this one
		address _treasury;
		address _accessHub;
		address _feeRecipientFactory;
		address _voter;
		address _voteModule;

		xYushaku = new XY(
			address(ysk),
			_voter,
			config.deployer,
			_accessHub,
			_voteModule,
			config.deployer,
		);

		stakeYsk = new XYZ(config.deployer, _accessHub, xYushaku, _voter, _voteModule);

		pairFactory = new PairFactory(address(voter), _treasury, _accessHub, _feeRecipientFactory);
	}
}
