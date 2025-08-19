// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPairFactory} from "contracts/interfaces/IPairFactory.sol";
import {IPair} from "contracts/interfaces/IPair.sol";
import {Pair} from "contracts/legacy/Pair.sol";

contract PairFactory is IPairFactory {
	/// @dev max swap fee set to 10%
	uint256 public constant MAX_FEE = 100_000;

	address public immutable voter;
	bytes32 public immutable pairCodeHash;
	address public immutable feeRecipientFactory;

	address public treasury;
	address public accessHub;

	uint256 public fee;
	uint256 public feeSplit;

	address[] public allPairs;
	mapping(address token0 => mapping(address token1 => mapping(bool stable => address pair)))
		public getPair;
	mapping(address pair => bool isPair) public isPair;
	mapping(address pair => uint256 fee) public _pairFee;
	mapping(address pair => bool skimEnabled) public skimEnabled;

	/// @dev if enabled, fee split to treasury if no gauge
	bool public feeSplitWhenNoGauge;

	constructor(
		address _voter,
		address _treasury,
		address _accessHub,
		address _feeRecipientFactory
	) {
		/// @dev default of 0.30%
		fee = 3000;
		voter = _voter;
		treasury = _treasury;
		accessHub = _accessHub;
		feeRecipientFactory = _feeRecipientFactory;
		pairCodeHash = keccak256(type(Pair).creationCode);
	}

	modifier onlyGovernanceOrVoter() {
		require(msg.sender == accessHub || msg.sender == voter);
		_;
	}

	modifier onlyGovernance() {
		require(msg.sender == accessHub, NotAuthorized());
		_;
	}

	/****************************************************************************************/
	/*                                     AUTHORIZED FUNCTIONS                             */
	/****************************************************************************************/

	/// @inheritdoc IPairFactory
	function setFee(uint256 _fee) external onlyGovernanceOrVoter {
		if (_fee == 0) revert ZeroFee();
		if (_fee > MAX_FEE) revert FeeTooHigh();
		fee = _fee;
		emit SetFee(_fee);
	}

	/// @inheritdoc IPairFactory
	function setPairFee(address _pair, uint256 _fee) external onlyGovernanceOrVoter {
		if (_fee > MAX_FEE) revert FeeTooHigh();
		uint256 __fee = (_fee == 0 ? fee : _fee);
		IPair(_pair).setFee(__fee);
		_pairFee[_pair] = __fee;
		emit SetPairFee(_pair, _fee);
	}

	/// @inheritdoc IPairFactory
	function setTreasury(address _treasury) external onlyGovernance {
		treasury = _treasury;
		emit NewTreasury(msg.sender, _treasury);
	}

	/// @inheritdoc IPairFactory
	/// @notice allow feeSplit directly to treasury if (gauge) does not exist
	function setFeeSplitWhenNoGauge(bool status) external onlyGovernance {
		feeSplitWhenNoGauge = status;
		emit FeeSplitWhenNoGauge(msg.sender, status);
	}

	/// @inheritdoc IPairFactory
	/// @notice set the percent of fee growth to mint in BP e.g. (9500 to mint 95% of fees)
	/// @dev gated to voter or AccessHub
	function setFeeSplit(uint256 _feeSplit) external onlyGovernanceOrVoter {
		/// @dev ensure feeSplit is within bounds
		require(_feeSplit <= 10_000, InvalidFeeSplit());
		/// @dev update the global feeSplit for newly created pairs
		feeSplit = _feeSplit;

		emit SetFeeSplit(_feeSplit);
	}

	/// @inheritdoc IPairFactory
	function setPairFeeSplit(address _pair, uint256 _feeSplit) external onlyGovernanceOrVoter {
		/// @dev ensure feeSplit is within bounds
		require(_feeSplit <= 10_000, InvalidFeeSplit());
		/// @dev set the feeSplit for the specific pair
		IPair(_pair).setFeeSplit(_feeSplit);

		emit SetPairFeeSplit(_pair, _feeSplit);
	}

	/// @inheritdoc IPairFactory
	/// @dev gated to voter or AccessHub
	/// @dev only voter can call upon creation
	function setFeeRecipient(address _pair, address _feeRecipient) external onlyGovernanceOrVoter {
		require(msg.sender == voter, NotAuthorized());
		IPair(_pair).setFeeRecipient(_feeRecipient);

		emit SetFeeRecipient(_pair, _feeRecipient);
	}

	/// @inheritdoc IPairFactory
	/// @dev function restrict or enable skim functionality on legacy pairs
	function setSkimEnabled(address _pair, bool _status) external onlyGovernance {
		skimEnabled[_pair] = skimEnabled[_pair] != _status ? _status : skimEnabled[_pair];
		emit SkimStatus(_pair, _status);
	}

	/****************************************************************************************/
	/*                                     USER FUNCTIONS                                   */
	/****************************************************************************************/

	/// @inheritdoc IPairFactory
	function createPair(
		address tokenA,
		address tokenB,
		bool stable
	) external returns (address pair) {
		if (tokenA == tokenB) revert SameAddress();

		/// @dev calculate token0 and token1 of the pair by sorting the addresses
		(address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
		if (token0 == address(0)) revert ZeroAddress();
		if (getPair[token0][token1][stable] != address(0)) revert PairExists();

		/// @dev pair creation logic
		bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
		pair = address(new Pair{salt: salt}());

		/// @dev initialize the pair upon creation
		IPair(pair).initialize(token0, token1, stable);
		IPair(pair).setFee(fee);

		/// @dev if we want an active fee split for gaugeless pairs
		if (feeSplitWhenNoGauge) {
			IPair(pair).setFeeRecipient(treasury);
			IPair(pair).setFeeSplit(feeSplit);
		}
		getPair[token0][token1][stable] = pair;
		getPair[token1][token0][stable] = pair;
		allPairs.push(pair);
		isPair[pair] = true;

		emit PairCreated(token0, token1, pair, allPairs.length);
	}

	/****************************************************************************************/
	/*                                      GETTERS                                         */
	/****************************************************************************************/
	/// @inheritdoc IPairFactory
	function pairFee(address _pair) public view returns (uint256 feeForPair) {
		return _pairFee[_pair];
	}

	/// @inheritdoc IPairFactory
	function allPairsLength() external view returns (uint256) {
		return allPairs.length;
	}
}
