// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FeeConfig, FeeQuote } from "../types/LumenTypes.sol";

interface ILumenFeeManager {
    function config() external view returns (FeeConfig memory);
    function quoteSwapFee(
        address pool,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (FeeQuote memory quote);
    function quoteImbalanceFeeShares(
        address pool,
        uint256 totalSupply,
        uint256 invariant,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint256 shares);
}
