// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { ImbalanceQuote, PoolBalances, SwapQuote } from "../types/LumenTypes.sol";

struct LumenPoolSnapshot {
    address pool;
    address token0;
    address token1;
    uint256 amplification;
    uint256 totalSupply;
    uint256 cachedInvariant;
    uint256 virtual0;
    uint256 virtual1;
    uint256 gross0;
    uint256 gross1;
    uint256 pendingLPFee0;
    uint256 pendingLPFee1;
    uint256 protocolFee0;
    uint256 protocolFee1;
    uint256 imbalancePpm;
}

contract LumenPoolLens {
    function snapshot(
        address pool
    ) external view returns (LumenPoolSnapshot memory data) {
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        data = LumenPoolSnapshot({
            pool: pool,
            token0: ILumenPool(pool).token0(),
            token1: ILumenPool(pool).token1(),
            amplification: ILumenPool(pool).amplification(),
            totalSupply: _totalSupply(pool),
            cachedInvariant: ILumenPool(pool).cachedInvariant(),
            virtual0: balances.virtual0,
            virtual1: balances.virtual1,
            gross0: balances.gross0,
            gross1: balances.gross1,
            pendingLPFee0: balances.pendingLPFee0,
            pendingLPFee1: balances.pendingLPFee1,
            protocolFee0: balances.protocolFee0,
            protocolFee1: balances.protocolFee1,
            imbalancePpm: StableSwapMath.imbalanceScore(balances.virtual0, balances.virtual1)
        });
    }

    function quoteUserExit(
        address pool,
        address account
    )
        external
        view
        returns (
            uint256 shares,
            uint256 proportional0,
            uint256 proportional1,
            uint256 accrued0,
            uint256 accrued1
        )
    {
        shares = _balanceOf(pool, account);
        (proportional0, proportional1) = ILumenPool(pool).quoteRemoveLiquidity(shares);
        (accrued0, accrued1) = ILumenPool(pool).accruedFees(account);
    }

    function quoteSwapMatrix(
        address pool,
        uint256 amount0In,
        uint256 amount1In
    ) external view returns (SwapQuote memory zeroForOne, SwapQuote memory oneForZero) {
        address token0 = ILumenPool(pool).token0();
        address token1 = ILumenPool(pool).token1();
        zeroForOne = ILumenPool(pool).quoteExactInput(token0, amount0In);
        oneForZero = ILumenPool(pool).quoteExactInput(token1, amount1In);
    }

    function quoteImbalanceGrid(
        address pool,
        uint256 amount0,
        uint256 amount1
    )
        external
        view
        returns (
            ImbalanceQuote memory oneSided0,
            ImbalanceQuote memory oneSided1,
            ImbalanceQuote memory both
        )
    {
        oneSided0 = ILumenPool(pool).quoteRemoveLiquidityImbalanced(amount0, 0);
        oneSided1 = ILumenPool(pool).quoteRemoveLiquidityImbalanced(0, amount1);
        both = ILumenPool(pool).quoteRemoveLiquidityImbalanced(amount0, amount1);
    }

    function _totalSupply(
        address token
    ) internal view returns (uint256 supply) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("totalSupply()"));
        require(success && data.length == 32, "LENS_SUPPLY");
        supply = abi.decode(data, (uint256));
    }

    function _balanceOf(
        address token,
        address account
    ) internal view returns (uint256 balance) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        require(success && data.length == 32, "LENS_BALANCE");
        balance = abi.decode(data, (uint256));
    }
}
