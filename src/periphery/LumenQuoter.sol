// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenAccounting } from "../accounting/LumenAccounting.sol";
import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { LiquidityQuote, PoolBalances, SwapQuote } from "../types/LumenTypes.sol";

struct LumenPoolDiagnostics {
    PoolBalances balances;
    LumenAccounting.ShareValue shareValue;
    LumenAccounting.FeeSolvency feeSolvency;
    uint256 physical0;
    uint256 physical1;
    uint256 recomputedInvariant;
    uint256 cachedInvariant;
    uint256 invariantDrift;
}

struct LumenExitPlan {
    uint256 userShares;
    uint256 proportional0;
    uint256 proportional1;
    uint256 oneToken0;
    uint256 oneToken1;
    uint256 accrued0;
    uint256 accrued1;
}

contract LumenQuoter {
    using LumenAccounting for PoolBalances;

    function diagnostics(
        address pool
    ) external view returns (LumenPoolDiagnostics memory data) {
        data.balances = ILumenPool(pool).getBalances();
        data.physical0 = IERC20Minimal(ILumenPool(pool).token0()).balanceOf(pool);
        data.physical1 = IERC20Minimal(ILumenPool(pool).token1()).balanceOf(pool);
        data.cachedInvariant = ILumenPool(pool).cachedInvariant();
        data.recomputedInvariant = data.balances.invariant(ILumenPool(pool).amplification());
        data.invariantDrift = data.cachedInvariant > data.recomputedInvariant
            ? data.cachedInvariant - data.recomputedInvariant
            : data.recomputedInvariant - data.cachedInvariant;
        data.shareValue = data.balances.shareValue(_totalSupply(pool), _lockedLiquidity(pool));
        data.feeSolvency = data.balances.feeSolvency();
    }

    function quoteDeposits(
        address pool,
        uint256[] calldata amounts0,
        uint256[] calldata amounts1
    ) external view returns (LiquidityQuote[] memory quotes) {
        require(amounts0.length == amounts1.length, "LEN");
        quotes = new LiquidityQuote[](amounts0.length);
        for (uint256 i; i < amounts0.length; ++i) {
            quotes[i] = ILumenPool(pool).quoteAddLiquidity(amounts0[i], amounts1[i]);
        }
    }

    function quoteSwaps(
        address pool,
        address tokenIn,
        uint256[] calldata amountsIn
    ) external view returns (SwapQuote[] memory quotes) {
        quotes = new SwapQuote[](amountsIn.length);
        for (uint256 i; i < amountsIn.length; ++i) {
            quotes[i] = ILumenPool(pool).quoteExactInput(tokenIn, amountsIn[i]);
        }
    }

    function quoteExitPlan(
        address pool,
        address account
    ) external view returns (LumenExitPlan memory plan) {
        plan.userShares = _balanceOf(pool, account);
        if (plan.userShares != 0) {
            (plan.proportional0, plan.proportional1) =
                ILumenPool(pool).quoteRemoveLiquidity(plan.userShares);
            plan.oneToken0 = ILumenPool(pool)
                .quoteRemoveLiquidityOneToken(ILumenPool(pool).token0(), plan.userShares);
            plan.oneToken1 = ILumenPool(pool)
                .quoteRemoveLiquidityOneToken(ILumenPool(pool).token1(), plan.userShares);
        }
        (plan.accrued0, plan.accrued1) = ILumenPool(pool).accruedFees(account);
    }

    function _totalSupply(
        address pool
    ) internal view returns (uint256 supply) {
        (bool success, bytes memory data) =
            pool.staticcall(abi.encodeWithSignature("totalSupply()"));
        require(success && data.length == 32, "SUPPLY");
        supply = abi.decode(data, (uint256));
    }

    function _lockedLiquidity(
        address pool
    ) internal view returns (uint256 locked) {
        (bool success, bytes memory data) =
            pool.staticcall(abi.encodeWithSignature("lockedLiquidity()"));
        require(success && data.length == 32, "LOCKED");
        locked = abi.decode(data, (uint256));
    }

    function _balanceOf(
        address pool,
        address account
    ) internal view returns (uint256 balance) {
        (bool success, bytes memory data) =
            pool.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        require(success && data.length == 32, "BALANCE");
        balance = abi.decode(data, (uint256));
    }
}
