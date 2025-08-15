// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVoteModule} from "contracts/interfaces/IVoteModule.sol";
import {IVoter} from "contracts/interfaces/IVoter.sol";
import {IXYZ} from "contracts/interfaces/IXYZ.sol";
import {IXY} from "contracts/interfaces/IXY.sol";

/**
 * @title Canonical xYushaku Wrapper for yushaku Exchange
 * @dev AUTO-COMPOUNDING shares token voting optimally each epoch
 */
contract XYZ is ERC4626, IXYZ, ReentrancyGuard {
	using SafeERC20 for ERC20;

	address public immutable accessHub;
	IVoteModule public immutable voteModule;
	IERC20 public immutable ysk;
	IXY public immutable xy;
	IVoter public immutable voter;

	address public operator;
	uint256 public activePeriod;

	mapping(uint256 => bool) public periodUnlockStatus;
	mapping(address => bool) public whitelistedAggregators;

	modifier whileNotLocked() {
		require(isUnlocked(), LOCKED());
		_;
	}

	modifier onlyOperator() {
		require(msg.sender == operator, IVoter.NOT_AUTHORIZED(msg.sender));
		_;
	}

	modifier onlyAccessHub() {
		require(msg.sender == accessHub, NOT_ACCESSHUB(msg.sender));
		_;
	}

	constructor(
		address _operator,
		address _accessHub,
		address _xYsk,
		address _voter,
		address _voteModule
	) ERC20("Ysk Liquid Staking Token", "XYZ") ERC4626(IERC20(_xYsk)) {
		operator = _operator;
		accessHub = _accessHub;
		xy = IXY(_xYsk);
		ysk = IERC20(xy.YSK());
		voteModule = IVoteModule(_voteModule);
		voter = IVoter(_voter);
		activePeriod = getPeriod();
		/// @dev pre-approve ysk and xYsk
		ysk.approve(address(xy), type(uint256).max);
		xy.approve(address(voteModule), type(uint256).max);
	}

	/// @inheritdoc IXYZ
	function submitVotes(
		address[] calldata _pools,
		uint256[] calldata _weights
	) external onlyOperator {
		/// @dev cast vote on behalf of this address
		voter.vote(address(this), _pools, _weights);
	}

	/// @inheritdoc IXYZ
	function compound() external onlyOperator {
		/// @dev fetch the current ratio prior to compounding
		uint256 currentRatio = ratio();
		/// @dev cache the current ysk balance
		uint256 currentYskBalance;
		/// @dev fetch from simple IERC20 call to the underlying SHADOW
		currentYskBalance = ysk.balanceOf(address(this));
		/// @dev convert to xYsk
		xy.convertEmissionsToken(currentYskBalance);
		/// @dev deposit into the voteModule
		voteModule.depositAll();
		/// @dev fetch new ratio
		uint256 newRatio = ratio();

		emit Compounded(currentRatio, newRatio, currentYskBalance);
	}

	/// @inheritdoc IXYZ
	function claimRebase() external onlyOperator {
		/// @dev claim rebase only if full rebase amount is ready
		/// @dev this is fine since the gap to do so is 6+ days
		require(block.timestamp > voteModule.periodFinish(), REBASE_IN_PROGRESS());

		/// @dev fetch index prior to claiming rebase
		uint256 currentRatio = ratio();
		/// @dev fetch how big the rebase is supposed to be
		uint256 rebaseSize = voteModule.earned(address(this));
		/// @dev claim the rebase
		voteModule.getReward();
		/// @dev deposit the rebase back into the voteModule
		voteModule.depositAll();
		/// @dev calculate the new index
		uint256 newRatio = ratio();

		emit Rebased(currentRatio, newRatio, rebaseSize);
	}

	/// @inheritdoc IXYZ
	function claimIncentives(
		address[] calldata _feeDistributors,
		address[][] calldata _tokens
	) external onlyOperator {
		/// @dev claim all voting rewards to x33 contract
		voter.claimIncentives(address(this), _feeDistributors, _tokens);
	}

	/// @inheritdoc IXYZ
	function swapIncentiveViaAggregator(
		AggregatorParams calldata _params
	) external nonReentrant onlyOperator {
		/// @dev check to make sure the aggregator is supported
		require(
			whitelistedAggregators[_params.aggregator],
			AGGREGATOR_NOT_WHITELISTED(_params.aggregator)
		);

		/// @dev required to validate later against malicious calldata
		/// @dev fetch underlying xYsk in the votemodule before swap
		uint256 xYskBalanceBeforeSwap = totalAssets();
		/// @dev fetch the yskBalance of the contract
		uint256 yskBalanceBeforeSwap = ysk.balanceOf(address(this));

		/// @dev swap via aggregator (swapping SHADOW is forbidden)
		require(_params.tokenIn != address(ysk), FORBIDDEN_TOKEN(address(ysk)));
		IERC20(_params.tokenIn).approve(_params.aggregator, _params.amountIn);
		(bool success, bytes memory returnData) = _params.aggregator.call(_params.callData);
		/// @dev revert with the returnData for debugging
		require(success, AGGREGATOR_REVERTED(returnData));

		/// @dev fetch the new balances after swap
		/// @dev ysk balance after the swap
		uint256 yskBalanceAfterSwap = ysk.balanceOf(address(this));
		/// @dev underlying xYsk balance in the voteModule
		uint256 xYskBalanceAfterSwap = totalAssets();
		/// @dev the difference from ysk before to after
		uint256 diffYsk = yskBalanceAfterSwap - yskBalanceBeforeSwap;
		/// @dev ysk tokenOut slippage check
		require(diffYsk >= _params.minAmountOut, AMOUNT_OUT_TOO_LOW(diffYsk));
		/// @dev prevent any holding xysk on x33 to be manipulated (under any circumstance)
		require(xYskBalanceAfterSwap == xYskBalanceBeforeSwap, FORBIDDEN_TOKEN(address(ysk)));

		emit SwappedBribe(operator, _params.tokenIn, _params.amountIn, diffYsk);
	}

	/// @inheritdoc IXYZ
	function rescue(address _token, uint256 _amount) external nonReentrant onlyAccessHub {
		uint256 snapshotxYskBalance = totalAssets();

		/// @dev transfer to the caller
		IERC20(_token).transfer(msg.sender, _amount);

		/// @dev _token could be any malicious contract someone sent to the x33 module
		/// @dev extra security check to ensure xYsk balance or allowance doesn't change when rescued
		require(xy.allowance(_token, address(this)) == 0, FORBIDDEN_TOKEN(address(xy)));
		require(totalAssets() == snapshotxYskBalance, FORBIDDEN_TOKEN(address(xy)));
	}

	/// @inheritdoc IXYZ
	function unlock() external onlyOperator {
		/// @dev block unlocking until the cooldown is concluded
		require(!isCooldownActive(), LOCKED());
		/// @dev unlock the current period
		periodUnlockStatus[getPeriod()] = true;

		emit Unlocked(block.timestamp);
	}

	/// @inheritdoc IXYZ
	function transferOperator(address _newOperator) external onlyAccessHub {
		address currentOperator = operator;

		/// @dev set the new operator
		operator = _newOperator;

		emit NewOperator(currentOperator, operator);
	}

	/// @inheritdoc IXYZ
	function whitelistAggregator(address _aggregator, bool _status) external onlyAccessHub {
		/// @dev add to the whitelisted aggregator mapping
		whitelistedAggregators[_aggregator] = _status;
		emit AggregatorWhitelistUpdated(_aggregator, _status);
	}

	/**
	 * Read Functions
	 */

	/// @inheritdoc ERC4626
	function totalAssets() public view override returns (uint256) {
		/// @dev simple call to the voteModule
		return voteModule.balanceOf(address(this));
	}

	/// @inheritdoc IXYZ
	function ratio() public view returns (uint256) {
		if (totalSupply() == 0) return 1e18;
		return (totalAssets() * 1e18) / totalSupply();
	}

	/// @inheritdoc IXYZ
	function getPeriod() public view returns (uint256 period) {
		period = block.timestamp / 1 weeks;
	}

	/// @inheritdoc IXYZ
	function isUnlocked() public view returns (bool) {
		/// @dev calculate the time left in the current period
		/// @dev getPeriod() + 1 can be viewed as the starting point of the NEXT period
		uint256 timeLeftInPeriod = ((getPeriod() + 1) * 1 weeks) - block.timestamp;
		/// @dev if there's <= 1 hour until flip, lock it
		/// @dev does not matter if the period is unlocked, block
		if (timeLeftInPeriod <= 1 hours) {
			return false;
		}
		/// @dev if it's unlocked and not within an hour until flip, allow interactions
		return periodUnlockStatus[getPeriod()];
	}

	/// @inheritdoc IXYZ
	function isCooldownActive() public view returns (bool) {
		/// @dev fetch the next unlock from the voteModule
		uint256 unlockTime = voteModule.unlockTime();
		return (block.timestamp >= unlockTime ? false : true);
	}

	/**
	 * ERC4626 internal overrides
	 */
	function _deposit(
		address caller,
		address receiver,
		uint256 assets,
		uint256 shares
	) internal virtual override whileNotLocked {
		SafeERC20.safeTransferFrom(xy, caller, address(this), assets);

		/// @dev deposit to the voteModule before minting shares to the user
		voteModule.deposit(assets);
		_mint(receiver, shares);

		emit Deposit(caller, receiver, assets, shares);
	}

	function _withdraw(
		address caller,
		address receiver,
		address owner,
		uint256 assets,
		uint256 shares
	) internal virtual override {
		if (caller != owner) {
			_spendAllowance(owner, caller, shares);
		}

		_burn(owner, shares);

		/// @dev withdraw from the voteModule before sending the user's xYsk
		voteModule.withdraw(assets);

		SafeERC20.safeTransfer(xy, receiver, assets);

		emit Withdraw(caller, receiver, owner, assets, shares);
	}
}
