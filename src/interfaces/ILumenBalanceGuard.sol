// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ILumenBalanceGuard {
    function validateAfterLiquidityChange(
        address pool,
        uint256 virtual0,
        uint256 virtual1
    ) external view;
    function validateSwap(
        address pool,
        uint256 virtual0,
        uint256 virtual1,
        uint256 amountIn,
        uint256 amountOut
    ) external view;
}
