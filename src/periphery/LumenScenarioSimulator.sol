// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { LumenLiquidityRisk } from "../risk/LumenLiquidityRisk.sol";
import { PoolBalances, SwapQuote } from "../types/LumenTypes.sol";

struct SwapSensitivity {
    uint256 amountIn;
    uint256 amountOut;
    uint256 feePpm;
    uint256 lpFee;
    uint256 protocolFee;
    uint256 invariantAfter;
    uint256 priceImpactPpm;
}

struct ExitLadderStep {
    uint256 shares;
    uint256 amount0;
    uint256 amount1;
    uint256 supplyAfter;
    uint256 virtual0After;
    uint256 virtual1After;
    uint256 invariantAfter;
}

contract LumenScenarioSimulator {
    uint256 internal constant PPM = 1_000_000;

    function operatingStress(
        address pool,
        uint256 reserveFloor0,
        uint256 reserveFloor1
    ) external view returns (LumenLiquidityRisk.PoolStress memory report) {
        report = _stress(pool, reserveFloor0, reserveFloor1, LumenLiquidityRisk.operatingConfig());
    }

    function severeStress(
        address pool,
        uint256 reserveFloor0,
        uint256 reserveFloor1
    ) external view returns (LumenLiquidityRisk.PoolStress memory report) {
        report = _stress(pool, reserveFloor0, reserveFloor1, LumenLiquidityRisk.severeConfig());
    }

    function customStress(
        address pool,
        uint256 reserveFloor0,
        uint256 reserveFloor1,
        LumenLiquidityRisk.StressConfig calldata config
    ) external view returns (LumenLiquidityRisk.PoolStress memory report) {
        report = _stress(pool, reserveFloor0, reserveFloor1, config);
    }

    function swapSensitivity(
        address pool,
        address tokenIn,
        uint256 startAmount,
        uint256 stepAmount,
        uint256 points
    ) external view returns (SwapSensitivity[] memory sensitivities) {
        sensitivities = new SwapSensitivity[](points);
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        bool zeroForOne = tokenIn == ILumenPool(pool).token0();
        uint256 reserveIn = zeroForOne ? balances.virtual0 : balances.virtual1;
        uint256 reserveOut = zeroForOne ? balances.virtual1 : balances.virtual0;

        for (uint256 i; i < points; ++i) {
            uint256 amountIn = startAmount + stepAmount * i;
            SwapQuote memory quote = ILumenPool(pool).quoteExactInput(tokenIn, amountIn);
            uint256 noImpactOut =
                reserveIn == 0 ? 0 : FullMath.mulDiv(amountIn, reserveOut, reserveIn);
            uint256 impact = noImpactOut > quote.amountOut ? noImpactOut - quote.amountOut : 0;
            sensitivities[i] = SwapSensitivity({
                amountIn: amountIn,
                amountOut: quote.amountOut,
                feePpm: quote.feePpm,
                lpFee: quote.lpFee,
                protocolFee: quote.protocolFee,
                invariantAfter: quote.invariantAfter,
                priceImpactPpm: noImpactOut == 0 ? 0 : FullMath.mulDiv(impact, PPM, noImpactOut)
            });
        }
    }

    function proportionalExitLadder(
        address pool,
        uint256 sharesPerStep,
        uint256 steps
    ) external view returns (ExitLadderStep[] memory ladder) {
        ladder = new ExitLadderStep[](steps);
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        uint256 supply = _totalSupply(pool);
        uint256 amplification = ILumenPool(pool).amplification();

        for (uint256 i; i < steps; ++i) {
            if (sharesPerStep == 0 || sharesPerStep > supply) break;
            uint256 amount0 = FullMath.mulDiv(sharesPerStep, balances.virtual0, supply);
            uint256 amount1 = FullMath.mulDiv(sharesPerStep, balances.virtual1, supply);
            balances.virtual0 -= amount0;
            balances.virtual1 -= amount1;
            supply -= sharesPerStep;
            ladder[i] = ExitLadderStep({
                shares: sharesPerStep,
                amount0: amount0,
                amount1: amount1,
                supplyAfter: supply,
                virtual0After: balances.virtual0,
                virtual1After: balances.virtual1,
                invariantAfter: StableSwapMath.getD(
                    balances.virtual0, balances.virtual1, amplification
                )
            });
        }
    }

    function _stress(
        address pool,
        uint256 reserveFloor0,
        uint256 reserveFloor1,
        LumenLiquidityRisk.StressConfig memory config
    ) internal view returns (LumenLiquidityRisk.PoolStress memory report) {
        report = LumenLiquidityRisk.assess(
            ILumenPool(pool).getBalances(),
            ILumenPool(pool).amplification(),
            reserveFloor0,
            reserveFloor1,
            config
        );
    }

    function _totalSupply(
        address pool
    ) internal view returns (uint256 supply) {
        (bool success, bytes memory data) =
            pool.staticcall(abi.encodeWithSignature("totalSupply()"));
        require(success && data.length == 32, "SUPPLY");
        supply = abi.decode(data, (uint256));
    }
}
