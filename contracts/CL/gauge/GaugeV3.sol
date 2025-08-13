// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./interfaces/IGaugeV3.sol";
import "../periphery/interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IFeeCollector.sol";
import "../core/libraries/FullMath.sol";

import "../core/interfaces/IRamsesV3Pool.sol";

import "../core/libraries/PoolStorage.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVoter} from "../../interfaces/IVoter.sol";

contract GaugeV3 is IGaugeV3 {
	using SafeERC20 for IERC20;

	uint256 internal constant WEEK = 1 weeks;
	uint256 internal constant PRECISION = 10 ** 18;

	bool internal _unlocked;

	IRamsesV3Pool public immutable pool;
	address public immutable voter;
	IFeeCollector public immutable feeCollector;
	INonfungiblePositionManager public immutable nfpManager;

	/// @inheritdoc IGaugeV3
	uint256 public immutable firstPeriod;

	/// @inheritdoc IGaugeV3
	/// @dev period => token => total supply
	mapping(uint256 => mapping(address => uint256)) public tokenTotalSupplyByPeriod;

	/// @dev period => position hash => bool
	mapping(uint256 => mapping(bytes32 => bool)) internal periodAmountsWritten;
	/// @dev period => position hash => seconds in range
	mapping(uint256 => mapping(bytes32 => uint256)) internal periodNfpSecondsX96;

	/// @inheritdoc IGaugeV3
	/// @dev period => position hash => reward token => amount
	mapping(uint256 => mapping(bytes32 => mapping(address => uint256))) public periodClaimedAmount;

	/// @dev token => position hash => period
	/// @inheritdoc IGaugeV3
	mapping(address => mapping(bytes32 => uint256)) public lastClaimByToken;

	/// @inheritdoc IGaugeV3
	address[] public rewards;
	/// @inheritdoc IGaugeV3
	mapping(address => bool) public isReward;

	/// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
	/// @dev to a function before the Gauge is initialized.
	modifier lock() {
		require(_unlocked, IRamsesV3PoolErrors.LOK());
		_unlocked = false;
		_;
		_unlocked = true;
	}

	/// @dev pushes fees from the pool to fee distributor on notify rewards
	modifier pushFees() {
		feeCollector.collectProtocolFees(pool);
		_;
	}

	constructor(address _voter, address _nfpManager, address _feeCollector, address _pool) {
		_unlocked = true;

		voter = _voter;
		feeCollector = IFeeCollector(_feeCollector);
		nfpManager = INonfungiblePositionManager(_nfpManager);
		pool = IRamsesV3Pool(_pool);

		firstPeriod = _blockTimestamp() / WEEK;

		(address shadow, address xshadow) = (IVoter(_voter).shadow(), IVoter(_voter).xShadow());

		(address token0, address token1) = (
			IRamsesV3Pool(_pool).token0(),
			IRamsesV3Pool(_pool).token1()
		);

		rewards.push(token0);
		rewards.push(token1);
		(isReward[token0], isReward[token1], isReward[xshadow]) = (true, true, true);
		/// @dev if token0 and token1 aren't shadow add shadow in the records
		if (token0 != shadow && token1 != shadow) {
			rewards.push(shadow);
			isReward[shadow] = true;
		}

		for (uint256 i; i < rewards.length; i++) {
			emit RewardAdded(rewards[i]);
		}
	}

	function _blockTimestamp() internal view virtual returns (uint256) {
		return block.timestamp;
	}

	/// @inheritdoc IGaugeV3
	function left(address token) external view override returns (uint256) {
		uint256 period = _blockTimestamp() / WEEK;
		uint256 remainingTime = ((period + 1) * WEEK) - _blockTimestamp();
		return (tokenTotalSupplyByPeriod[period][token] * remainingTime) / WEEK;
	}

	/// @inheritdoc IGaugeV3
	function rewardRate(address token) external view returns (uint256) {
		uint256 period = _blockTimestamp() / WEEK;
		return (tokenTotalSupplyByPeriod[period][token] / WEEK);
	}

	/// @inheritdoc IGaugeV3
	function getRewardTokens() external view override returns (address[] memory) {
		return rewards;
	}

	/// @inheritdoc IGaugeV3
	function positionHash(
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper
	) public pure returns (bytes32) {
		return keccak256(abi.encodePacked(owner, index, tickLower, tickUpper));
	}

	/// @inheritdoc IGaugeV3
	function notifyRewardAmount(address token, uint256 amount) external override pushFees lock {
		require(amount > 0, NOT_GT_ZERO(amount));
		require(isReward[token], IVoter.NOT_WHITELISTED());
		IRamsesV3Pool(pool)._advancePeriod();
		uint256 period = _blockTimestamp() / WEEK;

		uint256 balanceBefore = IERC20(token).balanceOf(address(this));
		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
		uint256 balanceAfter = IERC20(token).balanceOf(address(this));

		amount = balanceAfter - balanceBefore;
		tokenTotalSupplyByPeriod[period][token] += amount;
		emit NotifyReward(msg.sender, token, amount, period);
	}

	/// @inheritdoc IGaugeV3
	function notifyRewardAmountNextPeriod(address token, uint256 amount) external lock {
		require(amount > 0, NOT_GT_ZERO(amount));
		require(isReward[token], IVoter.NOT_WHITELISTED());
		uint256 period = (_blockTimestamp() / WEEK) + 1;
		uint256 balanceBefore = IERC20(token).balanceOf(address(this));
		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
		uint256 balanceAfter = IERC20(token).balanceOf(address(this));

		amount = balanceAfter - balanceBefore;
		tokenTotalSupplyByPeriod[period][token] += amount;

		emit NotifyReward(msg.sender, token, amount, period);
	}

	/// @inheritdoc IGaugeV3
	function notifyRewardAmountForPeriod(
		address token,
		uint256 amount,
		uint256 period
	) external lock {
		require(amount > 0, NOT_GT_ZERO(amount));
		require(isReward[token], IVoter.NOT_WHITELISTED());
		require(period > _blockTimestamp() / WEEK, RETRO());
		uint256 balanceBefore = IERC20(token).balanceOf(address(this));
		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
		uint256 balanceAfter = IERC20(token).balanceOf(address(this));

		amount = balanceAfter - balanceBefore;
		tokenTotalSupplyByPeriod[period][token] += amount;

		emit NotifyReward(msg.sender, token, amount, period);
	}

	/// @inheritdoc IGaugeV3
	function earned(address token, uint256 tokenId) external view returns (uint256 reward) {
		INonfungiblePositionManager _nfpManager = nfpManager;
		(, , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager.positions(tokenId);

		bytes32 _positionHash = positionHash(address(_nfpManager), tokenId, tickLower, tickUpper);

		uint256 lastClaim = Math.max(lastClaimByToken[token][_positionHash], firstPeriod);
		uint256 currentPeriod = _blockTimestamp() / WEEK;
		for (uint256 period = lastClaim; period <= currentPeriod; ++period) {
			reward += periodEarned(
				period,
				token,
				address(_nfpManager),
				tokenId,
				tickLower,
				tickUpper
			);
		}
	}

	/// @inheritdoc IGaugeV3
	function periodEarned(
		uint256 period,
		address token,
		uint256 tokenId
	) public view override returns (uint256) {
		INonfungiblePositionManager _nfpManager = nfpManager;
		(, , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager.positions(tokenId);

		return periodEarned(period, token, address(_nfpManager), tokenId, tickLower, tickUpper);
	}

	/// @inheritdoc IGaugeV3
	function periodEarned(
		uint256 period,
		address token,
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper
	) public view returns (uint256 amount) {
		(bool success, bytes memory data) = address(this).staticcall(
			abi.encodeCall(
				this.cachePeriodEarned,
				(period, token, owner, index, tickLower, tickUpper, false)
			)
		);

		if (!success) {
			return 0;
		}

		return abi.decode(data, (uint256));
	}

	/// @inheritdoc IGaugeV3
	/// @dev used by getReward() and saves gas by saving states
	function cachePeriodEarned(
		uint256 period,
		address token,
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper,
		bool caching
	) public override returns (uint256 amount) {
		uint256 periodSecondsInsideX96;

		bytes32 _positionHash = positionHash(owner, index, tickLower, tickUpper);

		/// @dev get seconds from pool if not already written into storage
		if (!periodAmountsWritten[period][_positionHash]) {
			(bool success, bytes memory data) = address(pool).staticcall(
				abi.encodeCall(
					IRamsesV3PoolState.positionPeriodSecondsInRange,
					(period, owner, index, tickLower, tickUpper)
				)
			);

			if (!success) {
				return 0;
			}

			(periodSecondsInsideX96) = abi.decode(data, (uint256));

			if (period < _blockTimestamp() / WEEK && caching) {
				periodAmountsWritten[period][_positionHash] = true;
				periodNfpSecondsX96[period][_positionHash] = periodSecondsInsideX96;
			}
		} else {
			periodSecondsInsideX96 = periodNfpSecondsX96[period][_positionHash];
		}

		amount = FullMath.mulDiv(
			tokenTotalSupplyByPeriod[period][token],
			periodSecondsInsideX96,
			WEEK << 96
		);

		uint256 claimed = periodClaimedAmount[period][_positionHash][token];
		if (amount >= claimed) {
			amount -= claimed;
		} else {
			amount = 0;
		}

		return amount;
	}

	/// @inheritdoc IGaugeV3
	function getPeriodReward(
		uint256 period,
		address[] calldata tokens,
		uint256 tokenId,
		address receiver
	) external override lock {
		require(period <= _blockTimestamp() / WEEK, CANT_CLAIM_FUTURE());
		INonfungiblePositionManager _nfpManager = nfpManager;
		address owner = _nfpManager.ownerOf(tokenId);
		address operator = _nfpManager.getApproved(tokenId);

		/// @dev check if owner, operator, or approved for all
		require(
			msg.sender == owner ||
				msg.sender == operator ||
				_nfpManager.isApprovedForAll(owner, msg.sender),
			NOT_AUTHORIZED()
		);

		(, , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager.positions(tokenId);

		bytes32 _positionHash = positionHash(address(_nfpManager), tokenId, tickLower, tickUpper);

		for (uint256 i = 0; i < tokens.length; ++i) {
			if (period < _blockTimestamp() / WEEK) {
				lastClaimByToken[tokens[i]][_positionHash] = period;
			}

			_getReward(
				period,
				tokens[i],
				address(_nfpManager),
				tokenId,
				tickLower,
				tickUpper,
				_positionHash,
				receiver
			);
		}
	}

	/// @inheritdoc IGaugeV3
	function getPeriodReward(
		uint256 period,
		address[] calldata tokens,
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper,
		address receiver
	) external override lock {
		require(msg.sender == owner, NOT_AUTHORIZED());
		bytes32 _positionHash = positionHash(owner, index, tickLower, tickUpper);

		for (uint256 i = 0; i < tokens.length; ++i) {
			if (period < _blockTimestamp() / WEEK) {
				lastClaimByToken[tokens[i]][_positionHash] = period;
			}

			_getReward(
				period,
				tokens[i],
				owner,
				index,
				tickLower,
				tickUpper,
				_positionHash,
				receiver
			);
		}
	}
	/// @inheritdoc IGaugeV3
	function getReward(uint256[] calldata tokenIds, address[] memory tokens) external {
		uint256 length = tokenIds.length;

		for (uint256 i = 0; i < length; ++i) {
			getReward(tokenIds[i], tokens);
		}
	}
	/// @inheritdoc IGaugeV3
	function getReward(uint256 tokenId, address[] memory tokens) public lock {
		INonfungiblePositionManager _nfpManager = nfpManager;
		address owner = _nfpManager.ownerOf(tokenId);
		address operator = _nfpManager.getApproved(tokenId);
		/// @dev check if owner, operator, or approved for all
		require(
			msg.sender == owner ||
				msg.sender == operator ||
				_nfpManager.isApprovedForAll(owner, msg.sender),
			NOT_AUTHORIZED()
		);

		(, , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager.positions(tokenId);

		_getAllRewards(address(_nfpManager), tokenId, tickLower, tickUpper, tokens, msg.sender);
	}
	/// @inheritdoc IGaugeV3
	function getRewardForOwner(uint256 tokenId, address[] memory tokens) external lock {
		require(msg.sender == voter || msg.sender == address(nfpManager), NOT_AUTHORIZED());

		INonfungiblePositionManager _nfpManager = nfpManager;
		address owner = _nfpManager.ownerOf(tokenId);

		(, , , int24 tickLower, int24 tickUpper, , , , , ) = _nfpManager.positions(tokenId);

		_getAllRewards(address(_nfpManager), tokenId, tickLower, tickUpper, tokens, owner);
	}

	function getReward(
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper,
		address[] memory tokens,
		address receiver
	) external lock {
		require(msg.sender == owner, NOT_AUTHORIZED());
		_getAllRewards(owner, index, tickLower, tickUpper, tokens, receiver);
	}

	function _getAllRewards(
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper,
		address[] memory tokens,
		address receiver
	) internal {
		bytes32 _positionHash = positionHash(owner, index, tickLower, tickUpper);
		uint256 currentPeriod = _blockTimestamp() / WEEK;
		uint256 lastClaim;
		for (uint256 i = 0; i < tokens.length; ++i) {
			lastClaim = Math.max(lastClaimByToken[tokens[i]][_positionHash], firstPeriod);
			for (uint256 period = lastClaim; period <= currentPeriod; ++period) {
				_getReward(
					period,
					tokens[i],
					owner,
					index,
					tickLower,
					tickUpper,
					_positionHash,
					receiver
				);
			}
			lastClaimByToken[tokens[i]][_positionHash] = currentPeriod - 1;
		}
	}

	function _getReward(
		uint256 period,
		address token,
		address owner,
		uint256 index,
		int24 tickLower,
		int24 tickUpper,
		bytes32 _positionHash,
		address receiver
	) internal {
		uint256 _reward = cachePeriodEarned(
			period,
			token,
			owner,
			index,
			tickLower,
			tickUpper,
			true
		);

		if (_reward > 0) {
			periodClaimedAmount[period][_positionHash][token] += _reward;

			IERC20(token).safeTransfer(receiver, _reward);
			emit ClaimRewards(period, _positionHash, receiver, token, _reward);
		}
	}

	function addRewards(address reward) external {
		require(msg.sender == voter, NOT_VOTER());
		if (!isReward[reward]) {
			rewards.push(reward);
			isReward[reward] = true;
			emit RewardAdded(reward);
		}
	}

	function removeRewards(address reward) external {
		require(msg.sender == voter, NOT_VOTER());
		if (isReward[reward]) {
			uint256 idx;

			for (uint256 i; i < rewards.length; ++i) {
				if (rewards[i] == reward) {
					idx = i;
					break;
				}
			}

			for (uint256 i = idx; i < rewards.length - 1; ++i) {
				rewards[i] = rewards[i + 1];
			}

			rewards.pop();
			isReward[reward] = false;

			emit RewardRemoved(reward);
		}
	}
}
