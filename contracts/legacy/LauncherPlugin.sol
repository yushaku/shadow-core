// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {ILauncherPlugin} from "contracts/interfaces/ILauncherPlugin.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";

/**
 * @title LauncherPlugins contract for modular plug-n-play with memes
 * @dev There are two trusted roles in the LauncherPlugin system
 * Authority: Whitelisted external launchers, e.g. DegenExpress
 * Operator: Shadow operational multisig, or other timelocked/secure system
 * AccessHub: central authority management contract
 * These roles are to be managed securely, and with diligence to prevent abuse
 * However, the system already has checks in place to mitigate any possible abuse situations ahead of time
 */
contract LauncherPlugin is ILauncherPlugin {
	uint256 public constant DENOM = 10_000;

	IVoter public immutable VOTER;
	address public accessHub;
	address public operator;

	mapping(address pool => bool isEnabled) public launcherPluginEnabled;
	mapping(address pool => LauncherConfigs) public poolConfigs;
	mapping(address pool => address feeDist) public feeDistToPool;
	mapping(address who => bool authority) public authorityMap;
	mapping(address authority => string name) public nameOfAuthority;

	modifier onlyAuthority() {
		/// @dev authority check of either the operator of authority in the mapping
		require(authorityMap[msg.sender] || msg.sender == accessHub, NOT_AUTHORITY());
		_;
	}

	modifier onlyOperator() {
		/// @dev redundant `operator` address put here as a safeguard for input errors on transferring roles
		require(msg.sender == accessHub || msg.sender == operator, NOT_OPERATOR());
		_;
	}

	constructor(address _voter, address _accessHub, address _operator) {
		VOTER = IVoter(_voter);
		accessHub = _accessHub;
		operator = _operator;
	}

	/***************************************************************************************/
	/* Authorized Functions */
	/***************************************************************************************/

	/// @inheritdoc ILauncherPlugin
	/// @dev should be called by another contract with proper batching of function calls
	function setConfigs(address _pool, uint256 _take, address _recipient) external onlyAuthority {
		/// @dev ensure the fee is <= 100%
		require(_take <= DENOM, INVALID_TAKE());
		require(launcherPluginEnabled[_pool], NOT_ENABLED(_pool));

		LauncherConfigs memory lc = LauncherConfigs(_take, _recipient);
		poolConfigs[_pool] = lc;

		emit Configured(_pool, _take, _recipient);
	}

	/// @inheritdoc ILauncherPlugin
	/// @dev should be called by another contract with proper batching of function calls
	function enablePool(address _pool) external onlyAuthority {
		require(!launcherPluginEnabled[_pool], ENABLED());
		address _feeDist = VOTER.feeDistributorForGauge(VOTER.gaugeForPool(_pool));
		require(_feeDist != address(0), NO_FEEDIST());

		feeDistToPool[_feeDist] = _pool;
		launcherPluginEnabled[_pool] = true;

		emit EnabledPool(_pool, nameOfAuthority[msg.sender]);
	}

	/// @inheritdoc ILauncherPlugin
	function migratePool(address _oldPool, address _newPool) external {
		/// @dev gate to accessHub and the current operator
		require(
			msg.sender == accessHub || msg.sender == operator,
			IVoter.NOT_AUTHORIZED(msg.sender)
		);
		require(launcherPluginEnabled[_oldPool], NOT_ENABLED(_oldPool));
		launcherPluginEnabled[_newPool] = true;
		/// @dev fetch the feedists for each pool
		(address _feeDist, address _newFeeDist) = (
			VOTER.feeDistributorForGauge(VOTER.gaugeForPool(_oldPool)),
			VOTER.feeDistributorForGauge(VOTER.gaugeForPool(_newPool))
		);
		/// @dev set the new pool's feedist
		feeDistToPool[_newFeeDist] = _newPool;
		/// @dev copy over the values
		poolConfigs[_newPool] = poolConfigs[_oldPool];
		/// @dev delete old values
		delete poolConfigs[_oldPool];
		/// @dev set to disabled
		launcherPluginEnabled[_oldPool] = false;
		/// @dev set the old fee dist to the new one as a safety measure
		feeDistToPool[_feeDist] = feeDistToPool[_newFeeDist];

		emit MigratedPool(_oldPool, _newPool);
	}

  
	/// @inheritdoc ILauncherPlugin
	function disablePool(address _pool) external onlyOperator {
		require(launcherPluginEnabled[_pool], NOT_ENABLED(_pool));

		delete poolConfigs[_pool];
		delete feeDistToPool[VOTER.feeDistributorForGauge(VOTER.gaugeForPool(_pool))];
		launcherPluginEnabled[_pool] = false;

		emit DisabledPool(_pool);
	}

	/// @inheritdoc ILauncherPlugin
	function setOperator(address _newOperator) external onlyOperator {
		require(operator != _newOperator, ALREADY_OPERATOR());

		address oldOperator = operator;
		operator = _newOperator;

		emit NewOperator(oldOperator, operator);
	}

	/// @inheritdoc ILauncherPlugin
	function grantAuthority(address _newAuthority, string calldata _name) external onlyOperator {
		require(!authorityMap[_newAuthority], ALREADY_AUTHORITY());

		authorityMap[_newAuthority] = true;
		_labelAuthority(_newAuthority, _name);
		emit NewAuthority(_newAuthority);
	}

	/// @inheritdoc ILauncherPlugin
	function revokeAuthority(address _oldAuthority) external onlyOperator {
		require(authorityMap[_oldAuthority], NOT_AUTHORITY());

		authorityMap[_oldAuthority] = false;
		emit RemovedAuthority(_oldAuthority);
	}

	/// @inheritdoc ILauncherPlugin
	function label(address _authority, string calldata _label) external onlyOperator {
		require(authorityMap[_authority], NOT_AUTHORITY());
		_labelAuthority(_authority, _label);
	}

	/***************************************************************************************/
	/* View Functions */
	/***************************************************************************************/

	/// @inheritdoc ILauncherPlugin
	function values(address _feeDist) external view returns (uint256 _take, address _recipient) {
		LauncherConfigs memory _tmp = poolConfigs[feeDistToPool[_feeDist]];
		return (_tmp.launcherTake, _tmp.takeRecipient);
	}

	/// @dev internal function called on creation and manually
	function _labelAuthority(address _authority, string calldata _label) internal {
		nameOfAuthority[_authority] = _label;
		emit Labeled(_authority, _label);
	}
}
