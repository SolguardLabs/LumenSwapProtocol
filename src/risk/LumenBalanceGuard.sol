// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILumenBalanceGuard } from "../interfaces/ILumenBalanceGuard.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import {
    LumenImbalanceTooHigh,
    LumenInvalidFee,
    LumenReserveTooLow
} from "../types/LumenErrors.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

contract LumenBalanceGuard is ILumenBalanceGuard, Ownable2Step {
    uint256 public minVirtualReserve;
    uint256 public maxImbalanceBps;
    uint256 public maxSwapOutBps;

    event GuardConfigUpdated(
        uint256 minVirtualReserve, uint256 maxImbalanceBps, uint256 maxSwapOutBps
    );

    constructor(
        address owner_,
        uint256 minVirtualReserve_,
        uint256 maxImbalanceBps_,
        uint256 maxSwapOutBps_
    ) Ownable2Step(owner_) {
        _setConfig(minVirtualReserve_, maxImbalanceBps_, maxSwapOutBps_);
    }

    function setConfig(
        uint256 minVirtualReserve_,
        uint256 maxImbalanceBps_,
        uint256 maxSwapOutBps_
    ) external onlyOwner {
        _setConfig(minVirtualReserve_, maxImbalanceBps_, maxSwapOutBps_);
    }

    function validateAfterLiquidityChange(
        address,
        uint256 virtual0,
        uint256 virtual1
    ) external view {
        _validateReserves(virtual0, virtual1);
        _validateImbalance(virtual0, virtual1);
    }

    function validateSwap(
        address,
        uint256 virtual0,
        uint256 virtual1,
        uint256,
        uint256 amountOut
    ) external view {
        _validateReserves(virtual0, virtual1);
        _validateImbalance(virtual0, virtual1);
        uint256 remaining = FixedPointMath.min(virtual0, virtual1);
        if (amountOut > FixedPointMath.bpsOf(remaining + amountOut, maxSwapOutBps)) {
            revert LumenImbalanceTooHigh();
        }
    }

    function _setConfig(
        uint256 minVirtualReserve_,
        uint256 maxImbalanceBps_,
        uint256 maxSwapOutBps_
    ) internal {
        if (maxImbalanceBps_ < 10_000 || maxImbalanceBps_ > 1_000_000 || maxSwapOutBps_ > 9500) {
            revert LumenInvalidFee();
        }
        minVirtualReserve = minVirtualReserve_;
        maxImbalanceBps = maxImbalanceBps_;
        maxSwapOutBps = maxSwapOutBps_;
        emit GuardConfigUpdated(minVirtualReserve_, maxImbalanceBps_, maxSwapOutBps_);
    }

    function _validateReserves(
        uint256 virtual0,
        uint256 virtual1
    ) internal view {
        if (virtual0 < minVirtualReserve || virtual1 < minVirtualReserve) {
            revert LumenReserveTooLow();
        }
    }

    function _validateImbalance(
        uint256 virtual0,
        uint256 virtual1
    ) internal view {
        uint256 high = FixedPointMath.max(virtual0, virtual1);
        uint256 low = FixedPointMath.min(virtual0, virtual1);
        if (low == 0) revert LumenReserveTooLow();
        uint256 ratioBps = FixedPointMath.mulDiv(high, 10_000, low);
        if (ratioBps > maxImbalanceBps) revert LumenImbalanceTooHigh();
    }
}
