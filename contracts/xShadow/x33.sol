// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVoter} from "../interfaces/IVoter.sol";
import {IXShadow} from "../interfaces/IXShadow.sol";
import {IVoteModule} from "../interfaces/IVoteModule.sol";
import {IX33} from "../interfaces/IX33.sol";

/// @title Canonical xShadow Wrapper for Shadow Exchange on Sonic
/// @dev Autocompounding shares token voting optimally each epoch
contract x33 is ERC4626, IX33, ReentrancyGuard {
    using SafeERC20 for ERC20;

    /// @inheritdoc IX33
    address public operator;

    /// @inheritdoc IX33
    address public immutable accessHub;

    IERC20 public immutable shadow;
    IXShadow public immutable xShadow;
    IVoteModule public immutable voteModule;
    IVoter public immutable voter;

    /// @inheritdoc IX33
    uint256 public activePeriod;

    /// @inheritdoc IX33
    mapping(uint256 => bool) public periodUnlockStatus;

    /// @notice Mapping of whitelisted aggregators
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
        address _xShadow,
        address _voter,
        address _voteModule
    ) ERC20("Shadow Liquid Staking Token", "x33") ERC4626(IERC20(_xShadow)) {
        operator = _operator;
        accessHub = _accessHub;
        xShadow = IXShadow(_xShadow);
        shadow = IERC20(xShadow.SHADOW());
        voteModule = IVoteModule(_voteModule);
        voter = IVoter(_voter);
        activePeriod = getPeriod();
        /// @dev pre-approve shadow and xShadow
        shadow.approve(address(xShadow), type(uint256).max);
        xShadow.approve(address(voteModule), type(uint256).max);
    }

    /// @inheritdoc IX33
    function submitVotes(
        address[] calldata _pools,
        uint256[] calldata _weights
    ) external onlyOperator {
        /// @dev cast vote on behalf of this address
        voter.vote(address(this), _pools, _weights);
    }

    /// @inheritdoc IX33
    function compound() external onlyOperator {
        /// @dev fetch the current ratio prior to compounding
        uint256 currentRatio = ratio();
        /// @dev cache the current shadow balance
        uint256 currentShadowBalance;
        /// @dev fetch from simple IERC20 call to the underlying SHADOW
        currentShadowBalance = shadow.balanceOf(address(this));
        /// @dev convert to xShadow
        xShadow.convertEmissionsToken(currentShadowBalance);
        /// @dev deposit into the voteModule
        voteModule.depositAll();
        /// @dev fetch new ratio
        uint256 newRatio = ratio();

        emit Compounded(currentRatio, newRatio, currentShadowBalance);
    }

    /// @inheritdoc IX33
    function claimRebase() external onlyOperator {
        /// @dev claim rebase only if full rebase amount is ready
        /// @dev this is fine since the gap to do so is 6+ days
        require(
            block.timestamp > voteModule.periodFinish(),
            REBASE_IN_PROGRESS()
        );

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

    /// @inheritdoc IX33
    function claimIncentives(
        address[] calldata _feeDistributors,
        address[][] calldata _tokens
    ) external onlyOperator {
        /// @dev claim all voting rewards to x33 contract
        voter.claimIncentives(address(this), _feeDistributors, _tokens);
    }

    /// @inheritdoc IX33
    function swapIncentiveViaAggregator(
        AggregatorParams calldata _params
    ) external nonReentrant onlyOperator {
        /// @dev check to make sure the aggregator is supported
        require(
            whitelistedAggregators[_params.aggregator],
            AGGREGATOR_NOT_WHITELISTED(_params.aggregator)
        );

        /// @dev required to validate later against malicious calldata
        /// @dev fetch underlying xShadow in the votemodule before swap
        uint256 xShadowBalanceBeforeSwap = totalAssets();
        /// @dev fetch the shadowBalance of the contract
        uint256 shadowBalanceBeforeSwap = shadow.balanceOf(address(this));

        /// @dev swap via aggregator (swapping SHADOW is forbidden)
        require(
            _params.tokenIn != address(shadow),
            FORBIDDEN_TOKEN(address(shadow))
        );
        IERC20(_params.tokenIn).approve(_params.aggregator, _params.amountIn);
        (bool success, bytes memory returnData) = _params.aggregator.call(
            _params.callData
        );
        /// @dev revert with the returnData for debugging
        require(success, AGGREGATOR_REVERTED(returnData));

        /// @dev fetch the new balances after swap
        /// @dev shadow balance after the swap
        uint256 shadowBalanceAfterSwap = shadow.balanceOf(address(this));
        /// @dev underlying xShadow balance in the voteModule
        uint256 xShadowBalanceAfterSwap = totalAssets();
        /// @dev the difference from shadow before to after
        uint256 diffShadow = shadowBalanceAfterSwap - shadowBalanceBeforeSwap;
        /// @dev shadow tokenOut slippage check
        require(
            diffShadow >= _params.minAmountOut,
            AMOUNT_OUT_TOO_LOW(diffShadow)
        );
        /// @dev prevent any holding xshadow on x33 to be manipulated (under any circumstance)
        require(
            xShadowBalanceAfterSwap == xShadowBalanceBeforeSwap,
            FORBIDDEN_TOKEN(address(shadow))
        );

        emit SwappedBribe(
            operator,
            _params.tokenIn,
            _params.amountIn,
            diffShadow
        );
    }

    /// @inheritdoc IX33
    function rescue(
        address _token,
        uint256 _amount
    ) external nonReentrant onlyAccessHub {
        uint256 snapshotxShadowBalance = totalAssets();

        /// @dev transfer to the caller
        IERC20(_token).transfer(msg.sender, _amount);

        /// @dev _token could be any malicious contract someone sent to the x33 module
        /// @dev extra security check to ensure xShadow balance or allowance doesn't change when rescued
        require(
            xShadow.allowance(_token, address(this)) == 0,
            FORBIDDEN_TOKEN(address(xShadow))
        );
        require(
            totalAssets() == snapshotxShadowBalance,
            FORBIDDEN_TOKEN(address(xShadow))
        );
    }

    /// @inheritdoc IX33
    function unlock() external onlyOperator {
        /// @dev block unlocking until the cooldown is concluded
        require(!isCooldownActive(), LOCKED());
        /// @dev unlock the current period
        periodUnlockStatus[getPeriod()] = true;

        emit Unlocked(block.timestamp);
    }
    /// @inheritdoc IX33

    function transferOperator(address _newOperator) external onlyAccessHub {
        address currentOperator = operator;

        /// @dev set the new operator
        operator = _newOperator;

        emit NewOperator(currentOperator, operator);
    }

    /// @inheritdoc IX33
    function whitelistAggregator(
        address _aggregator,
        bool _status
    ) external onlyAccessHub {
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

    /// @inheritdoc IX33
    function ratio() public view returns (uint256) {
        if (totalSupply() == 0) return 1e18;
        return (totalAssets() * 1e18) / totalSupply();
    }

    /// @inheritdoc IX33
    function getPeriod() public view returns (uint256 period) {
        period = block.timestamp / 1 weeks;
    }

    /// @inheritdoc IX33
    function isUnlocked() public view returns (bool) {
        /// @dev calculate the time left in the current period
        /// @dev getPeriod() + 1 can be viewed as the starting point of the NEXT period
        uint256 timeLeftInPeriod = ((getPeriod() + 1) * 1 weeks) -
            block.timestamp;
        /// @dev if there's <= 1 hour until flip, lock it
        /// @dev does not matter if the period is unlocked, block
        if (timeLeftInPeriod <= 1 hours) {
            return false;
        }
        /// @dev if it's unlocked and not within an hour until flip, allow interactions
        return periodUnlockStatus[getPeriod()];
    }

    /// @inheritdoc IX33
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
        SafeERC20.safeTransferFrom(xShadow, caller, address(this), assets);
        
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

        /// @dev withdraw from the voteModule before sending the user's xShadow
        voteModule.withdraw(assets);

        SafeERC20.safeTransfer(xShadow, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
