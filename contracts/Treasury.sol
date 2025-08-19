// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPair} from "contracts/interfaces/IPair.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IRouter} from "contracts/interfaces/IRouter.sol";
import {IAccessHub} from "contracts/interfaces/IAccessHub.sol";
import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";
import {IXY} from "contracts/interfaces/IXY.sol";

/**
 * @title TreasuryHelper
 * @notice This contract acts as a helper or a manager for the main treasury.
 * It is designed to automate and manage various treasury operations, such as staking, voting, claiming rewards, and distributing funds.
 * It is not the treasury itself, but a contract that acts on behalf of the treasury.
 *
 * Key Features:
 * - Automated Treasury Operations: The contract automates many of the treasury's day-to-day operations, which are performed by a designated operator.
 * - Fund Distribution: The contract provides a mechanism to distribute funds to a list of members based on a predefined weight.
 * - Member Management: The treasury can manage a list of members and their corresponding weights for fund distributions.
 * - Robust Access Control: The contract has a clear separation of powers with strict access control between the timelock, treasury, and operator.
 * - Safety and Recovery Features: The contract includes several safety features to protect the treasury's funds, such as a guarded modifier and fund recovery functions.
 * - LP Token Management: The contract has the ability to unwrap LP tokens into their underlying assets.
 */
contract TreasuryHelper is UUPSUpgradeable {
	using EnumerableMap for EnumerableMap.AddressToUintMap;

	/// @dev ERRORS
	// authorization errors
	error NotTimelock(address caller);
	error NotTreasury(address caller);
	error NotOperator(address caller);
	error NotMember(address account);
	// input validation errors
	error NotLP(address token);
	error InvalidAddress();
	error InvalidWeight(uint256 weight);
	error InvalidTotalWeight(uint256 total);
	error ZeroAddress();
	error ZeroAmount();
	// state errors
	error InvalidAggregator(address aggregator);
	error NoMembers();
	error NoBalance();
	error RebaseInProgress();
	error WARNING();
	// transaction errors
	error TransferFailed();
	error CallFailed();
	error AggregatorFailed(bytes returnData);
	error InsufficientOutput(uint256 received, uint256 minimum);
	error NotDog();

	/// @dev STATE
	struct Storage {
		uint256 BASIS_POINTS;
		IXY xShadow;
		IVoteModule voteModule;
		address treasury;
		address timelock;
		IVoter voter;
		address operator;
		// config
		mapping(address => bool) whitelistedAggregators;
		EnumerableMap.AddressToUintMap memberWeights;
		uint256 totalWeight;
		address legacyRouter;
	}

	// keccak256(abi.encode(uint256(keccak256("ysk.treasury.helper.v1")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 public constant STORAGE_LOCATION =
		0x5cce8d48e117d58a89d528cceec71c713a74bfaf421e67ad358cb391ecc41f00;

	/// @dev Return state storage struct for reading and writing
	function getStorage() internal pure returns (Storage storage $) {
		assembly {
			$.slot := STORAGE_LOCATION
		}
	}

	/// @dev STRUCTS

	struct AggregatorParams {
		address _aggregator;
		address _tokenIn;
		address _tokenOut;
		uint256 _amountIn;
		uint256 _minAmountOut;
		bytes _callData;
	}
	/// @dev EVENTS

	event MemberUpdated(address account, uint256 weight);
	event Distribution(address indexed member, address indexed token, uint256 amount);
	event SwappedIncentive(address indexed tokenIn, uint256 amountIn, uint256 amountOut);
	event AggregatorWhitelistUpdated(address aggregator, bool status);
	event Voted(address[] pools, uint256[] weights);

	constructor() {
		_disableInitializers();
	}

	function _authorizeUpgrade(address newImplementation) internal override onlyOperator {
		if (newImplementation == address(0)) revert ZeroAddress();
	}

	function initialize(IXY _xShadow, address _initialOperator) public initializer {
		if (address(_xShadow) == address(0)) revert ZeroAddress();
		if (_initialOperator == address(0)) revert ZeroAddress();

		Storage storage $ = getStorage();
		$.xShadow = _xShadow;
		IAccessHub accessHub = IAccessHub($.xShadow.ACCESS_HUB()); // only used for initialization
		$.timelock = accessHub.timelock();
		$.treasury = accessHub.treasury();
		$.voteModule = IVoteModule(accessHub.voteModule());
		$.voter = IVoter(accessHub.voter());
		$.operator = _initialOperator;
	}

	/// @dev MODIFIERS

	modifier onlyTimelock() {
		Storage storage $ = getStorage();
		if (msg.sender != $.timelock) revert NotTimelock(msg.sender);
		_;
	}

	modifier onlyTreasury() {
		Storage storage $ = getStorage();
		if (msg.sender != $.treasury) revert NotTreasury(msg.sender);
		_;
	}

	modifier onlyOperator() {
		Storage storage $ = getStorage();
		if (msg.sender != $.operator) revert NotOperator(msg.sender);
		_;
	}

	modifier guarded() {
		Storage storage $ = getStorage();
		uint256 stakedBalanceBefore = $.voteModule.balanceOf(address(this));
		_;
		uint256 stakedBalanceAfter = $.voteModule.balanceOf(address(this));
		if (stakedBalanceAfter < stakedBalanceBefore) revert WARNING();
	}

	/// @dev MANAGEMENT

	function updateMember(address _account, uint256 _weight) external onlyTreasury {
		Storage storage $ = getStorage();

		if (_account == address(0)) revert InvalidAddress();
		if (_weight > $.BASIS_POINTS) revert InvalidWeight(_weight);

		if ($.memberWeights.contains(_account)) {
			uint256 oldWeight = $.memberWeights.get(_account);
			$.totalWeight -= oldWeight;
		}
		$.totalWeight += _weight;
		if ($.totalWeight > $.BASIS_POINTS) revert InvalidTotalWeight($.totalWeight);
		if (_weight > 0) {
			$.memberWeights.set(_account, _weight);
		} else {
			$.memberWeights.remove(_account);
		}
		emit MemberUpdated(_account, _weight);
	}

	function updateOperator(address _newOperator) external onlyTreasury {
		Storage storage $ = getStorage();
		if (_newOperator == address(0)) revert ZeroAddress();
		$.operator = _newOperator;
	}

	/// @dev TREASURY OPERATIONS
	function depositXShadow(uint256 _amount) external onlyTreasury {
		Storage storage $ = getStorage();
		if (_amount == 0) revert ZeroAmount();
		$.xShadow.approve(address($.voteModule), _amount);
		$.voteModule.deposit(_amount);
	}

	function withdrawXShadow(uint256 _amount) external onlyTreasury {
		Storage storage $ = getStorage();
		if (_amount == 0) revert ZeroAmount();
		$.voteModule.withdraw(_amount);
		require(IERC20($.xShadow).balanceOf(address(this)) >= _amount, "RUGGED");
	}

	/// @dev OPERATOR UPKEEP
	function claimRebase() external onlyOperator {
		Storage storage $ = getStorage();
		$.voteModule.getReward();
		IERC20($.xShadow).approve(
			address($.voteModule),
			IERC20($.xShadow).balanceOf(address(this))
		);
		$.voteModule.deposit(type(uint256).max);
	}

	function claimIncentives(
		address[] calldata _feeDistributors,
		address[][] calldata _tokens
	) external onlyOperator {
		Storage storage $ = getStorage();
		$.voter.claimIncentives(address(this), _feeDistributors, _tokens);
	}

	/// @notice Allows the operator to cast votes on behalf of the treasury
	/// @param _pools Array of pool addresses to vote for
	/// @param _weights Array of corresponding weights for each pool
	function submitVotes(
		address[] calldata _pools,
		uint256[] calldata _weights
	) external onlyOperator {
		Storage storage $ = getStorage();
		// Call the vote function on the voter contract, casting votes from this contract's address
		$.voter.vote(address(this), _pools, _weights);
		emit Voted(_pools, _weights);
	}

	function swapIncentiveViaAggregator(
		AggregatorParams calldata _params
	) external onlyOperator guarded {
		Storage storage $ = getStorage();
		if (!$.whitelistedAggregators[_params._aggregator])
			revert InvalidAggregator(_params._aggregator);

		// swap via aggregator
		uint256 balanceBefore = IERC20(_params._tokenOut).balanceOf(address(this));
		IERC20(_params._tokenIn).approve(_params._aggregator, _params._amountIn);
		(bool success, bytes memory returnData) = _params._aggregator.call(_params._callData);
		if (!success) revert AggregatorFailed(returnData);

		// validate slippage
		uint256 balanceAfter = IERC20(_params._tokenOut).balanceOf(address(this));
		uint256 received = balanceAfter - balanceBefore;
		if (received < _params._minAmountOut)
			revert InsufficientOutput(received, _params._minAmountOut);

		emit SwappedIncentive(_params._tokenIn, _params._amountIn, received);
	}

	/// @notice try to unwrap LP token to token0/1
	/// @param token LP token address
	/// @return isLP bool if its a LP token
	/// @return tokenA token0 address
	/// @return tokenB token1 address
	function _tryUnwrapLP(
		address token
	) internal returns (bool isLP, address tokenA, address tokenB) {
		Storage storage $ = getStorage();
		try IPair(token).token0() returns (address token0) {
			address token1 = IPair(token).token1();
			uint256 lpBalance = IERC20(token).balanceOf(address(this));

			if (lpBalance > 0) {
				// approve legacy router to spend LP tokens
				IERC20(token).approve($.legacyRouter, lpBalance);
				// remove liquidity
				IRouter($.legacyRouter).removeLiquidity(
					token0,
					token1,
					IPair(token).stable(),
					lpBalance,
					0, // amountAMin
					0, // amountBMin
					address(this),
					block.timestamp
				);

				return (true, token0, token1);
			}
		} catch {
			return (false, address(0), address(0));
		}
	}

	function tryUnwrapLP(address token) external onlyOperator guarded {
		(bool isLP, , ) = _tryUnwrapLP(token);
		if (!isLP) revert NotLP(token);
	}

	function whitelistAggregator(address _aggregator, bool _status) external onlyTreasury {
		Storage storage $ = getStorage();
		$.whitelistedAggregators[_aggregator] = _status;
		emit AggregatorWhitelistUpdated(_aggregator, _status);
	}

	function distribute(address _token) external onlyOperator {
		Storage storage $ = getStorage();
		if ($.memberWeights.length() == 0) revert NoMembers();
		if (_token == address(0)) revert ZeroAddress();

		// don't distribute unless all members been defined allocation
		if ($.totalWeight != $.BASIS_POINTS) revert InvalidTotalWeight($.totalWeight);

		uint256 balance = IERC20(_token).balanceOf(address(this));
		if (balance == 0) revert NoBalance();

		for (uint256 i = 0; i < $.memberWeights.length(); i++) {
			(address account, uint256 weight) = $.memberWeights.at(i);
			uint256 share = (balance * weight) / $.BASIS_POINTS;
			if (share > 0) {
				bool success = IERC20(_token).transfer(account, share);
				if (account == address(0)) revert ZeroAddress();
				if (!success) revert TransferFailed();
				emit Distribution(account, _token, share);
			}
		}
	}

	/// @dev VIEW FUNCTIONS
	function getMemberWeight(address _account) external view returns (uint256) {
		Storage storage $ = getStorage();
		require($.memberWeights.contains(_account), NotMember(_account));
		return $.memberWeights.get(_account);
	}

	function getMemberCount() external view returns (uint256) {
		Storage storage $ = getStorage();
		return $.memberWeights.length();
	}

	function getAllMembers()
		external
		view
		returns (address[] memory accounts, uint256[] memory weights)
	{
		Storage storage $ = getStorage();
		uint256 length = $.memberWeights.length();
		accounts = new address[](length);
		weights = new uint256[](length);

		for (uint256 i = 0; i < length; i++) {
			(accounts[i], weights[i]) = $.memberWeights.at(i);
		}

		return (accounts, weights);
	}

	function treasuryVotingPower() external view returns (uint256) {
		Storage storage $ = getStorage();
		uint256 totalVotingPower = $.voteModule.balanceOf(address(this)) +
			$.xShadow.balanceOf(address(this)) +
			$.voteModule.earned(address(this));
		uint256 totalSupply = $.xShadow.totalSupply();

		return (totalVotingPower * 1e18) / totalSupply;
	}

	/// @dev SAFETY FUNCTIONS
	function recoverERC20(address _token, uint256 _amount) external onlyTreasury {
		Storage storage $ = getStorage();
		IERC20(_token).transfer($.treasury, _amount);
	}

	function recoverNative() external onlyTreasury {
		Storage storage $ = getStorage();
		(bool success, ) = $.treasury.call{value: address(this).balance}("");
		if (!success) revert TransferFailed();
	}

	function emergencyExecute(address _to, bytes calldata _data) external onlyTimelock {
		if (_to == address(0)) revert ZeroAddress();
		(bool success, ) = _to.call(_data);
		if (!success) revert CallFailed();
	}

	function clawBackToTreasury(address _token, uint256 _amount) external onlyOperator {
		Storage storage $ = getStorage();
		IERC20(_token).transfer($.treasury, _amount);
	}

	/// @dev VIEW FUNCTIONS FOR STORAGE VARIABLES
	function getXShadow() external view returns (address) {
		Storage storage $ = getStorage();
		return address($.xShadow);
	}

	function getVoteModule() external view returns (address) {
		Storage storage $ = getStorage();
		return address($.voteModule);
	}

	function getTreasury() external view returns (address) {
		Storage storage $ = getStorage();
		return $.treasury;
	}

	function getTimelock() external view returns (address) {
		Storage storage $ = getStorage();
		return $.timelock;
	}

	function getVoter() external view returns (address) {
		Storage storage $ = getStorage();
		return address($.voter);
	}

	function getOperator() external view returns (address) {
		Storage storage $ = getStorage();
		return $.operator;
	}

	function isAggregatorWhitelisted(address _aggregator) external view returns (bool) {
		Storage storage $ = getStorage();
		return $.whitelistedAggregators[_aggregator];
	}

	function getTotalWeight() external view returns (uint256) {
		Storage storage $ = getStorage();
		return $.totalWeight;
	}

	function getLegacyRouter() external view returns (address) {
		Storage storage $ = getStorage();
		return $.legacyRouter;
	}

	function getBasisPoints() external view returns (uint256) {
		Storage storage $ = getStorage();
		return $.BASIS_POINTS;
	}
}
