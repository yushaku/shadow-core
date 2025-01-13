// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {ILauncherPlugin} from "./interfaces/ILauncherPlugin.sol";
import {IVoter} from "./interfaces/IVoter.sol";

/// @author ShadowDEX on Sonic
/// @title LauncherPlugins contract for modular plug-n-play with Sonic memes
/** @dev There are two trusted roles in the LauncherPlugin system
 * Authority: Whitelisted external launchers, e.g. DegenExpress
 * Operator: Shadow operational multisig, or other timelocked/secure system
 * AccessHub: central authority management contract
 * These roles are to be managed securely, and with diligence to prevent abuse
 * However, the system already has checks in place to mitigate any possible abuse situations ahead of time
 */
contract LauncherPlugin is ILauncherPlugin {
    /// @inheritdoc ILauncherPlugin
    address public accessHub;
    /// @inheritdoc ILauncherPlugin
    address public operator;

    /// @notice the voter contract
    IVoter public immutable voter;

    /// @inheritdoc ILauncherPlugin
    mapping(address pool => bool isEnabled) public launcherPluginEnabled;
    /// @inheritdoc ILauncherPlugin
    mapping(address pool => LauncherConfigs) public poolConfigs;
    /// @inheritdoc ILauncherPlugin
    mapping(address pool => address feeDist) public feeDistToPool;
    /// @inheritdoc ILauncherPlugin
    mapping(address who => bool authority) public authorityMap;
    /// @inheritdoc ILauncherPlugin
    mapping(address authority => string name) public nameOfAuthority;

    /// @inheritdoc ILauncherPlugin
    uint256 public constant DENOM = 10_000;

    modifier onlyAuthority() {
        /// @dev authority check of either the operator of authority in the mapping
        require(
            authorityMap[msg.sender] || msg.sender == accessHub,
            NOT_AUTHORITY()
        );
        _;
    }

    modifier onlyOperator() {
        /// @dev redundant `operator` address put here as a safeguard for input errors on transferring roles
        require(
            msg.sender == accessHub || msg.sender == operator,
            NOT_OPERATOR()
        );
        _;
    }

    constructor(address _voter, address _accessHub, address _operator) {
        /// @dev initialize the voter
        voter = IVoter(_voter);
        /// @dev operator and team initially are the same
        accessHub = _accessHub;
        operator = _operator;
    }

    /// @inheritdoc ILauncherPlugin
    /// @dev should be called by another contract with proper batching of function calls
    function setConfigs(
        address _pool,
        uint256 _take,
        address _recipient
    ) external onlyAuthority {
        /// @dev ensure launcherPlugins are enabled
        require(launcherPluginEnabled[_pool], NOT_ENABLED(_pool));
        /// @dev ensure the fee is <= 100%
        require(_take <= DENOM, INVALID_TAKE());
        /// @dev store launcher configs in pool to struct mapping
        LauncherConfigs memory lc = LauncherConfigs(_take, _recipient);
        /// @dev store the pool configs in the mapping
        poolConfigs[_pool] = lc;
        /// @dev emit an event for configuration
        emit Configured(_pool, _take, _recipient);
    }
    /// @inheritdoc ILauncherPlugin
    /// @dev should be called by another contract with proper batching of function calls
    function enablePool(address _pool) external onlyAuthority {
        /// @dev require that the plugin is enabled
        require(!launcherPluginEnabled[_pool], ENABLED());
        /// @dev fetch the feeDistributor address
        address _feeDist = voter.feeDistributorForGauge(
            voter.gaugeForPool(_pool)
        );
        /// @dev check that _feeDist is not the zero addresss
        require(_feeDist != address(0), NO_FEEDIST());
        /// @dev set the feeDist for the pool
        feeDistToPool[_feeDist] = _pool;
        launcherPluginEnabled[_pool] = true;
        /// @dev emit with the name of the authority
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
            voter.feeDistributorForGauge(voter.gaugeForPool(_oldPool)),
            voter.feeDistributorForGauge(voter.gaugeForPool(_newPool))
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
        /// @dev require the plugin is already enabled
        require(launcherPluginEnabled[_pool], NOT_ENABLED(_pool));
        /// @dev wipe struct
        delete poolConfigs[_pool];
        /// @dev wipe the mapping for feeDist to the pool, incase the feeDist is overwritten
        delete feeDistToPool[
            voter.feeDistributorForGauge(voter.gaugeForPool(_pool))
        ];
        /// @dev set to disabled
        launcherPluginEnabled[_pool] = false;
        /// @dev emit an event
        emit DisabledPool(_pool);
    }
    /// @inheritdoc ILauncherPlugin
    function setOperator(address _newOperator) external onlyOperator {
        /// @dev ensure the new operator is not already the operator
        require(operator != _newOperator, ALREADY_OPERATOR());
        /// @dev store the oldOperator to use in the event, for info purposes
        address oldOperator = operator;
        /// @dev set operator as the new operator
        operator = _newOperator;
        /// @dev emit operator change event
        emit NewOperator(oldOperator, operator);
    }

    /// @inheritdoc ILauncherPlugin
    function grantAuthority(
        address _newAuthority,
        string calldata _name
    ) external onlyOperator {
        /// @dev ensure the proposed _newAuthority is not already one
        require(!authorityMap[_newAuthority], ALREADY_AUTHORITY());
        /// @dev set the mapping to true
        authorityMap[_newAuthority] = true;
        /// @dev emit the new authority event
        emit NewAuthority(_newAuthority);
        /// @dev label the authority
        _labelAuthority(_newAuthority, _name);
    }

    /// @inheritdoc ILauncherPlugin
    function revokeAuthority(address _oldAuthority) external onlyOperator {
        /// @dev ensure _oldAuthority is already an authority
        require(authorityMap[_oldAuthority], NOT_AUTHORITY());
        /// @dev set the mapping to false
        authorityMap[_oldAuthority] = false;
        /// @dev emit the remove authority event
        emit RemovedAuthority(_oldAuthority);
    }
    /// @inheritdoc ILauncherPlugin
    function label(
        address _authority,
        string calldata _label
    ) external onlyOperator {
        _labelAuthority(_authority, _label);
    }

    /// @inheritdoc ILauncherPlugin
    function values(
        address _feeDist
    ) external view returns (uint256 _take, address _recipient) {
        /// @dev fetch the poolConfigs from the mapping
        LauncherConfigs memory _tmp = poolConfigs[feeDistToPool[_feeDist]];
        /// @dev return the existing values
        return (_tmp.launcherTake, _tmp.takeRecipient);
    }

    /// @dev internal function called on creation and manually
    function _labelAuthority(
        address _authority,
        string calldata _label
    ) internal {
        /// @dev ensure they are an authority
        require(authorityMap[_authority], NOT_AUTHORITY());
        /// @dev label the authority
        nameOfAuthority[_authority] = _label;
        /// @dev emit on label
        emit Labeled(_authority, _label);
    }
}
