// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { ILumenBalanceGuard } from "../interfaces/ILumenBalanceGuard.sol";
import { ILumenFeeManager } from "../interfaces/ILumenFeeManager.sol";
import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { LumenOracle } from "../oracle/LumenOracle.sol";
import { LumenLPToken } from "../tokens/LumenLPToken.sol";
import {
    LumenDeadlineExpired,
    LumenInsufficientInput,
    LumenInsufficientLiquidity,
    LumenInvalidRecipient,
    LumenInvalidToken,
    LumenNoFees,
    LumenOutputBelowMinimum,
    LumenSharesAboveMaximum,
    LumenSharesBelowMinimum,
    LumenTokenMismatch,
    LumenTransferAmountMismatch,
    LumenZeroAddress,
    LumenZeroAmount,
    LumenZeroLiquidity
} from "../types/LumenErrors.sol";
import {
    FeeCheckpoint,
    FeeQuote,
    ImbalanceQuote,
    LiquidityQuote,
    PoolBalances,
    PoolConfig,
    SwapQuote
} from "../types/LumenTypes.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";
import { Pausable } from "../utils/Pausable.sol";
import { ReentrancyGuard } from "../utils/ReentrancyGuard.sol";

contract LumenPool is ILumenPool, LumenLPToken, Ownable2Step, Pausable, ReentrancyGuard {
    using FixedPointMath for uint256;
    using SafeTransferLib for address;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    address public constant DEAD_SHARES = address(0x000000000000000000000000000000000000dEaD);

    address public immutable token0;
    address public immutable token1;
    uint256 public immutable amplification;

    address public feeRecipient;
    address public feeManager;
    address public balanceGuard;
    address public oracle;

    uint256 public cachedInvariant;
    uint256 public lockedLiquidity;

    uint256 private _gross0;
    uint256 private _gross1;
    uint256 private _virtual0;
    uint256 private _virtual1;

    uint256 private _pendingLPFee0;
    uint256 private _pendingLPFee1;
    uint256 private _protocolFee0;
    uint256 private _protocolFee1;

    uint256 private _feeGrowth0X128;
    uint256 private _feeGrowth1X128;

    mapping(address account => FeeCheckpoint checkpoint) private _feeCheckpoints;

    constructor(
        PoolConfig memory config
    ) LumenLPToken("Lumen Stable LP", "lumSLP") Ownable2Step(config.owner) {
        if (
            config.token0 == address(0) || config.token1 == address(0)
                || config.feeRecipient == address(0)
        ) {
            revert LumenZeroAddress();
        }
        if (config.token0 == config.token1) revert LumenTokenMismatch();
        StableSwapMath.validateAmplification(config.amplification);

        token0 = config.token0;
        token1 = config.token1;
        amplification = config.amplification;
        feeRecipient = config.feeRecipient;
        feeManager = config.feeManager;
        balanceGuard = config.balanceGuard;
        oracle = config.oracle;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFeeRecipient(
        address recipient
    ) external onlyOwner {
        if (recipient == address(0)) revert LumenZeroAddress();
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    function setFeeManager(
        address manager
    ) external onlyOwner {
        feeManager = manager;
        emit FeeManagerUpdated(manager);
    }

    function setBalanceGuard(
        address guard
    ) external onlyOwner {
        balanceGuard = guard;
        emit BalanceGuardUpdated(guard);
    }

    function getBalances() external view returns (PoolBalances memory balances) {
        balances = PoolBalances({
            gross0: _gross0,
            gross1: _gross1,
            virtual0: _virtual0,
            virtual1: _virtual1,
            pendingLPFee0: _pendingLPFee0,
            pendingLPFee1: _pendingLPFee1,
            protocolFee0: _protocolFee0,
            protocolFee1: _protocolFee1
        });
    }

    function virtualBalances() external view returns (uint256 balance0, uint256 balance1) {
        return (_virtual0, _virtual1);
    }

    function grossBalances() external view returns (uint256 balance0, uint256 balance1) {
        return (_gross0, _gross1);
    }

    function protocolFees() external view returns (uint256 amount0, uint256 amount1) {
        return (_protocolFee0, _protocolFee1);
    }

    function pendingLPFees() external view returns (uint256 amount0, uint256 amount1) {
        return (_pendingLPFee0, _pendingLPFee1);
    }

    function feeGrowthGlobalX128() external view returns (uint256 growth0, uint256 growth1) {
        return (_feeGrowth0X128, _feeGrowth1X128);
    }

    function feeGrowthCheckpoint(
        address account
    ) external view returns (uint256 growth0, uint256 growth1) {
        FeeCheckpoint memory checkpoint = _feeCheckpoints[account];
        return (checkpoint.feeGrowth0X128, checkpoint.feeGrowth1X128);
    }

    function accruedFees(
        address account
    ) public view returns (uint256 amount0, uint256 amount1) {
        FeeCheckpoint memory checkpoint = _feeCheckpoints[account];
        uint256 accountShares = balanceOf[account];
        amount0 = checkpoint.stored0;
        amount1 = checkpoint.stored1;
        if (accountShares != 0) {
            amount0 += accountShares.mulDiv(
                _feeGrowth0X128 - checkpoint.feeGrowth0X128, FixedPointMath.Q128
            );
            amount1 += accountShares.mulDiv(
                _feeGrowth1X128 - checkpoint.feeGrowth1X128, FixedPointMath.Q128
            );
        }
    }

    function quoteAddLiquidity(
        uint256 amount0,
        uint256 amount1
    ) public view returns (LiquidityQuote memory quote) {
        if (amount0 == 0 && amount1 == 0) revert LumenZeroAmount();
        uint256 invariantBefore = cachedInvariant;
        uint256 invariantAfter =
            StableSwapMath.getD(_virtual0 + amount0, _virtual1 + amount1, amplification);
        uint256 shares =
            StableSwapMath.quoteSharesForDeposit(totalSupply, invariantBefore, invariantAfter);
        if (totalSupply == 0) {
            if (amount0 == 0 || amount1 == 0 || invariantAfter <= MINIMUM_LIQUIDITY) {
                revert LumenZeroLiquidity();
            }
            shares = invariantAfter - MINIMUM_LIQUIDITY;
        }
        quote = LiquidityQuote({
            amount0: amount0,
            amount1: amount1,
            shares: shares,
            invariantBefore: invariantBefore,
            invariantAfter: invariantAfter
        });
    }

    function quoteRemoveLiquidity(
        uint256 shares
    ) public view returns (uint256 amount0, uint256 amount1) {
        if (shares == 0) revert LumenZeroAmount();
        uint256 supply = totalSupply;
        if (supply == 0 || shares > supply) revert LumenInsufficientLiquidity();
        amount0 = shares.mulDiv(_virtual0, supply);
        amount1 = shares.mulDiv(_virtual1, supply);
    }

    function quoteRemoveLiquidityOneToken(
        address tokenOut,
        uint256 shares
    ) public view returns (uint256 amountOut) {
        if (shares == 0) revert LumenZeroAmount();
        uint256 supply = totalSupply;
        if (supply == 0 || shares > supply) revert LumenInsufficientLiquidity();
        uint256 d0 = cachedInvariant;
        uint256 d1 = d0 - shares.mulDiv(d0, supply);
        if (tokenOut == token0) {
            uint256 newY = StableSwapMath.getYForD(0, _virtual1, d1, amplification);
            amountOut = _virtual0 - newY;
        } else if (tokenOut == token1) {
            uint256 newY = StableSwapMath.getYForD(1, _virtual0, d1, amplification);
            amountOut = _virtual1 - newY;
        } else {
            revert LumenInvalidToken();
        }
    }

    function quoteRemoveLiquidityImbalanced(
        uint256 amount0,
        uint256 amount1
    ) public view returns (ImbalanceQuote memory quote) {
        if (amount0 == 0 && amount1 == 0) revert LumenZeroAmount();
        if (amount0 > _virtual0 || amount1 > _virtual1) revert LumenInsufficientLiquidity();

        uint256 invariantBefore = cachedInvariant;
        uint256 actualInvariantAfter =
            StableSwapMath.getD(_virtual0 - amount0, _virtual1 - amount1, amplification);

        uint256 feeShares = _quoteImbalanceFeeShares(totalSupply, invariantBefore, amount0, amount1);
        uint256 staleProjectedInvariant = invariantBefore;

        // Intentional CTF bug: the virtual balances are projected below, but the LP burn
        // calculation keeps the previous D as if the withdrawal had not changed the curve.
        uint256 sharesToBurn = StableSwapMath.quoteSharesForWithdrawal(
            totalSupply, invariantBefore, staleProjectedInvariant
        ) + feeShares;
        if (sharesToBurn == 0) sharesToBurn = 1;

        quote = ImbalanceQuote({
            amount0: amount0,
            amount1: amount1,
            sharesToBurn: sharesToBurn,
            staleInvariant: staleProjectedInvariant,
            actualInvariantAfter: actualInvariantAfter,
            imbalanceFeeShares: feeShares
        });
    }

    function quoteExactInput(
        address tokenIn,
        uint256 amountIn
    ) public view returns (SwapQuote memory quote) {
        if (amountIn == 0) revert LumenZeroAmount();
        bool zeroForOne = tokenIn == token0;
        if (!zeroForOne && tokenIn != token1) revert LumenInvalidToken();

        uint256 reserveIn = zeroForOne ? _virtual0 : _virtual1;
        uint256 reserveOut = zeroForOne ? _virtual1 : _virtual0;
        if (reserveIn == 0 || reserveOut == 0) revert LumenInsufficientLiquidity();

        FeeQuote memory fee = _quoteSwapFee(amountIn, reserveIn, reserveOut);
        uint256 effectiveIn = amountIn - fee.totalFee;
        if (effectiveIn == 0) revert LumenInsufficientInput();

        uint256 y = StableSwapMath.getY(
            zeroForOne ? 0 : 1,
            zeroForOne ? 1 : 0,
            reserveIn + effectiveIn,
            _virtual0,
            _virtual1,
            amplification
        );
        uint256 amountOut = reserveOut > y ? reserveOut - y - 1 : 0;
        if (amountOut == 0) revert LumenInsufficientLiquidity();

        uint256 newVirtual0 = zeroForOne ? _virtual0 + effectiveIn : _virtual0 - amountOut;
        uint256 newVirtual1 = zeroForOne ? _virtual1 - amountOut : _virtual1 + effectiveIn;
        uint256 invariantAfter = StableSwapMath.getD(newVirtual0, newVirtual1, amplification);

        quote = SwapQuote({
            tokenIn: tokenIn,
            tokenOut: zeroForOne ? token1 : token0,
            amountIn: amountIn,
            amountOut: amountOut,
            lpFee: fee.lpFee,
            protocolFee: fee.protocolFee,
            feePpm: fee.feePpm,
            invariantBefore: cachedInvariant,
            invariantAfter: invariantAfter
        });
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        _checkDeadline(deadline);
        _checkRecipient(recipient);
        LiquidityQuote memory quote = quoteAddLiquidity(amount0, amount1);
        if (quote.shares < minShares) revert LumenSharesBelowMinimum();

        _pullExact(token0, msg.sender, amount0);
        _pullExact(token1, msg.sender, amount1);

        _gross0 += amount0;
        _gross1 += amount1;
        _virtual0 += amount0;
        _virtual1 += amount1;

        if (totalSupply == 0) {
            lockedLiquidity = MINIMUM_LIQUIDITY;
            _mint(DEAD_SHARES, MINIMUM_LIQUIDITY);
        }
        shares = quote.shares;
        _mint(recipient, shares);

        cachedInvariant = quote.invariantAfter;
        _validateLiquidityChange(_virtual0, _virtual1);
        _writeOracle();
        emit LiquidityAdded(msg.sender, recipient, amount0, amount1, shares, cachedInvariant);
    }

    function removeLiquidity(
        uint256 shares,
        uint256 minAmount0,
        uint256 minAmount1,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1) {
        _checkDeadline(deadline);
        _checkRecipient(recipient);
        (amount0, amount1) = quoteRemoveLiquidity(shares);
        if (amount0 < minAmount0 || amount1 < minAmount1) revert LumenOutputBelowMinimum();

        _burn(msg.sender, shares);
        _debitVirtualAndGross(amount0, amount1);
        cachedInvariant = StableSwapMath.getD(_virtual0, _virtual1, amplification);
        _validateLiquidityChange(_virtual0, _virtual1);

        token0.safeTransfer(recipient, amount0);
        token1.safeTransfer(recipient, amount1);
        _writeOracle();
        emit LiquidityRemoved(msg.sender, recipient, amount0, amount1, shares, cachedInvariant);
    }

    function removeLiquidityOneToken(
        address tokenOut,
        uint256 shares,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        _checkDeadline(deadline);
        _checkRecipient(recipient);
        amountOut = quoteRemoveLiquidityOneToken(tokenOut, shares);
        if (amountOut < minAmountOut) revert LumenOutputBelowMinimum();

        _burn(msg.sender, shares);
        if (tokenOut == token0) {
            _debitVirtualAndGross(amountOut, 0);
            token0.safeTransfer(recipient, amountOut);
        } else if (tokenOut == token1) {
            _debitVirtualAndGross(0, amountOut);
            token1.safeTransfer(recipient, amountOut);
        } else {
            revert LumenInvalidToken();
        }

        cachedInvariant = StableSwapMath.getD(_virtual0, _virtual1, amplification);
        _validateLiquidityChange(_virtual0, _virtual1);
        _writeOracle();
        emit LiquidityRemoved(
            msg.sender,
            recipient,
            tokenOut == token0 ? amountOut : 0,
            tokenOut == token1 ? amountOut : 0,
            shares,
            cachedInvariant
        );
    }

    function removeLiquidityImbalanced(
        uint256 amount0,
        uint256 amount1,
        uint256 maxShares,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 sharesBurned) {
        _checkDeadline(deadline);
        _checkRecipient(recipient);
        ImbalanceQuote memory quote = quoteRemoveLiquidityImbalanced(amount0, amount1);
        if (quote.sharesToBurn > maxShares) revert LumenSharesAboveMaximum();

        sharesBurned = quote.sharesToBurn;
        _burn(msg.sender, sharesBurned);
        _debitVirtualAndGross(amount0, amount1);

        cachedInvariant = quote.actualInvariantAfter;
        _validateLiquidityChange(_virtual0, _virtual1);

        if (amount0 != 0) token0.safeTransfer(recipient, amount0);
        if (amount1 != 0) token1.safeTransfer(recipient, amount1);
        _writeOracle();
        emit ImbalanceWithdrawal(
            msg.sender,
            recipient,
            amount0,
            amount1,
            sharesBurned,
            quote.staleInvariant,
            quote.actualInvariantAfter
        );
    }

    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        _checkDeadline(deadline);
        _checkRecipient(recipient);
        SwapQuote memory quote = quoteExactInput(tokenIn, amountIn);
        if (quote.amountOut < minAmountOut) revert LumenOutputBelowMinimum();

        bool zeroForOne = tokenIn == token0;
        _pullExact(tokenIn, msg.sender, amountIn);

        if (zeroForOne) {
            _gross0 += amountIn;
            _gross1 -= quote.amountOut;
            _virtual0 += amountIn - quote.lpFee - quote.protocolFee;
            _virtual1 -= quote.amountOut;
            _accountFees(0, quote.lpFee, quote.protocolFee);
            token1.safeTransfer(recipient, quote.amountOut);
        } else {
            _gross1 += amountIn;
            _gross0 -= quote.amountOut;
            _virtual1 += amountIn - quote.lpFee - quote.protocolFee;
            _virtual0 -= quote.amountOut;
            _accountFees(1, quote.lpFee, quote.protocolFee);
            token0.safeTransfer(recipient, quote.amountOut);
        }

        amountOut = quote.amountOut;
        cachedInvariant = quote.invariantAfter;
        _validateSwap(_virtual0, _virtual1, amountIn, amountOut);
        _writeOracle();
        emit Swap(
            msg.sender,
            recipient,
            tokenIn,
            amountIn,
            amountOut,
            quote.lpFee,
            quote.protocolFee,
            cachedInvariant
        );
    }

    function claimFees(
        address recipient
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        _checkRecipient(recipient);
        _checkpoint(msg.sender);
        FeeCheckpoint storage checkpoint = _feeCheckpoints[msg.sender];

        amount0 = FixedPointMath.min(checkpoint.stored0, _pendingLPFee0);
        amount1 = FixedPointMath.min(checkpoint.stored1, _pendingLPFee1);
        if (amount0 == 0 && amount1 == 0) revert LumenNoFees();

        checkpoint.stored0 -= amount0;
        checkpoint.stored1 -= amount1;
        if (amount0 != 0) {
            _pendingLPFee0 -= amount0;
            _gross0 -= amount0;
            token0.safeTransfer(recipient, amount0);
        }
        if (amount1 != 0) {
            _pendingLPFee1 -= amount1;
            _gross1 -= amount1;
            token1.safeTransfer(recipient, amount1);
        }
        emit LPFeesClaimed(msg.sender, recipient, amount0, amount1);
    }

    function collectProtocolFees()
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (msg.sender != owner && msg.sender != feeRecipient) revert LumenInvalidRecipient();
        amount0 = _protocolFee0;
        amount1 = _protocolFee1;
        if (amount0 == 0 && amount1 == 0) revert LumenNoFees();

        _protocolFee0 = 0;
        _protocolFee1 = 0;
        if (amount0 != 0) {
            _gross0 -= amount0;
            token0.safeTransfer(feeRecipient, amount0);
        }
        if (amount1 != 0) {
            _gross1 -= amount1;
            token1.safeTransfer(feeRecipient, amount1);
        }
        emit ProtocolFeesCollected(feeRecipient, amount0, amount1);
    }

    function skim(
        address recipient
    ) external nonReentrant onlyOwner {
        _checkRecipient(recipient);
        uint256 physical0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 physical1 = IERC20Minimal(token1).balanceOf(address(this));
        if (physical0 > _gross0) token0.safeTransfer(recipient, physical0 - _gross0);
        if (physical1 > _gross1) token1.safeTransfer(recipient, physical1 - _gross1);
    }

    function _pullExact(
        address token,
        address payer,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        uint256 beforeBalance = IERC20Minimal(token).balanceOf(address(this));
        token.safeTransferFrom(payer, address(this), amount);
        uint256 afterBalance = IERC20Minimal(token).balanceOf(address(this));
        if (afterBalance - beforeBalance != amount) revert LumenTransferAmountMismatch();
    }

    function _debitVirtualAndGross(
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (amount0 > _virtual0 || amount1 > _virtual1) revert LumenInsufficientLiquidity();
        _virtual0 -= amount0;
        _virtual1 -= amount1;
        _gross0 -= amount0;
        _gross1 -= amount1;
    }

    function _accountFees(
        uint256 tokenIndex,
        uint256 lpFee,
        uint256 protocolFee
    ) internal {
        uint256 feeSupply = totalSupply - lockedLiquidity;
        if (tokenIndex == 0) {
            _pendingLPFee0 += lpFee;
            _protocolFee0 += protocolFee;
            if (lpFee != 0 && feeSupply != 0) {
                _feeGrowth0X128 += lpFee.mulDiv(FixedPointMath.Q128, feeSupply);
            }
        } else {
            _pendingLPFee1 += lpFee;
            _protocolFee1 += protocolFee;
            if (lpFee != 0 && feeSupply != 0) {
                _feeGrowth1X128 += lpFee.mulDiv(FixedPointMath.Q128, feeSupply);
            }
        }
    }

    function _quoteSwapFee(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (FeeQuote memory quote) {
        if (feeManager != address(0)) {
            return ILumenFeeManager(feeManager)
                .quoteSwapFee(address(this), amountIn, reserveIn, reserveOut);
        }
        quote.feePpm = 400;
        quote.totalFee = amountIn.ppmOf(400);
        quote.protocolFee = quote.totalFee / 2;
        quote.lpFee = quote.totalFee - quote.protocolFee;
    }

    function _quoteImbalanceFeeShares(
        uint256 supply,
        uint256 invariant,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (uint256) {
        if (feeManager != address(0)) {
            return ILumenFeeManager(feeManager)
                .quoteImbalanceFeeShares(address(this), supply, invariant, amount0, amount1);
        }
        uint256 valueOut = amount0 + amount1;
        if (supply == 0 || invariant == 0 || valueOut == 0) return 0;
        uint256 baseShares = supply.mulDiv(valueOut, invariant);
        uint256 feeShares = baseShares.ppmOf(500);
        return feeShares == 0 ? 1 : feeShares;
    }

    function _checkpoint(
        address account
    ) internal {
        if (account == address(0)) return;
        FeeCheckpoint storage checkpoint = _feeCheckpoints[account];
        uint256 accountShares = balanceOf[account];
        if (accountShares != 0) {
            checkpoint.stored0 += accountShares.mulDiv(
                _feeGrowth0X128 - checkpoint.feeGrowth0X128, FixedPointMath.Q128
            );
            checkpoint.stored1 += accountShares.mulDiv(
                _feeGrowth1X128 - checkpoint.feeGrowth1X128, FixedPointMath.Q128
            );
        }
        checkpoint.feeGrowth0X128 = _feeGrowth0X128;
        checkpoint.feeGrowth1X128 = _feeGrowth1X128;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        _checkpoint(from);
        _checkpoint(to);
    }

    function _validateLiquidityChange(
        uint256 virtual0_,
        uint256 virtual1_
    ) internal view {
        if (balanceGuard != address(0)) {
            ILumenBalanceGuard(balanceGuard)
                .validateAfterLiquidityChange(address(this), virtual0_, virtual1_);
        }
    }

    function _validateSwap(
        uint256 virtual0_,
        uint256 virtual1_,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        if (balanceGuard != address(0)) {
            ILumenBalanceGuard(balanceGuard)
                .validateSwap(address(this), virtual0_, virtual1_, amountIn, amountOut);
        }
    }

    function _writeOracle() internal {
        if (oracle != address(0)) {
            try LumenOracle(oracle).write(_virtual0, _virtual1) { } catch { }
        }
    }

    function _checkDeadline(
        uint256 deadline
    ) internal view {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert LumenDeadlineExpired();
    }

    function _checkRecipient(
        address recipient
    ) internal pure {
        if (recipient == address(0) || recipient == DEAD_SHARES) revert LumenInvalidRecipient();
    }
}
