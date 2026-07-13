// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenAccounting } from "../accounting/LumenAccounting.sol";
import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { ImbalanceQuote, PoolBalances, SwapQuote } from "../types/LumenTypes.sol";

struct DrainStep {
    uint256 amount0;
    uint256 amount1;
    uint256 vulnerableShares;
    uint256 correctedShares;
    uint256 invariantBefore;
    uint256 invariantAfter;
    uint256 supplyAfterVulnerableBurn;
    uint256 virtual0After;
    uint256 virtual1After;
}

struct DrainSimulation {
    uint256 totalAmount0;
    uint256 totalAmount1;
    uint256 totalVulnerableShares;
    uint256 totalCorrectedShares;
    uint256 finalInvariant;
    uint256 finalVirtual0;
    uint256 finalVirtual1;
    uint256 aggregateDiscountPpm;
    DrainStep[] steps;
}

struct SwapSensitivity {
    uint256 amountIn;
    uint256 amountOut;
    uint256 feePpm;
    uint256 lpFee;
    uint256 protocolFee;
    uint256 invariantAfter;
    uint256 priceImpactPpm;
}

contract LumenScenarioSimulator {
    using LumenAccounting for PoolBalances;

    uint256 internal constant PPM = 1_000_000;

    function simulateSingleSidedDrain(
        address pool,
        bool withdrawToken0,
        uint256 amountPerStep,
        uint256 steps
    ) external view returns (DrainSimulation memory simulation) {
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        uint256 supply = _totalSupply(pool);
        uint256 invariant = ILumenPool(pool).cachedInvariant();
        uint256 amplification = ILumenPool(pool).amplification();

        simulation.steps = new DrainStep[](steps);
        for (uint256 i; i < steps; ++i) {
            uint256 amount0 = withdrawToken0 ? _boundedAmount(amountPerStep, balances.virtual0) : 0;
            uint256 amount1 = withdrawToken0 ? 0 : _boundedAmount(amountPerStep, balances.virtual1);
            if (amount0 == 0 && amount1 == 0) break;

            DrainStep memory step =
                _simulateDrainStep(balances, supply, invariant, amplification, amount0, amount1);
            simulation.steps[i] = step;
            simulation.totalAmount0 += amount0;
            simulation.totalAmount1 += amount1;
            simulation.totalVulnerableShares += step.vulnerableShares;
            simulation.totalCorrectedShares += step.correctedShares;

            balances.virtual0 = step.virtual0After;
            balances.virtual1 = step.virtual1After;
            balances.gross0 = balances.gross0 > amount0 ? balances.gross0 - amount0 : 0;
            balances.gross1 = balances.gross1 > amount1 ? balances.gross1 - amount1 : 0;
            invariant = step.invariantAfter;
            supply = step.supplyAfterVulnerableBurn;
        }

        simulation.finalInvariant = invariant;
        simulation.finalVirtual0 = balances.virtual0;
        simulation.finalVirtual1 = balances.virtual1;
        simulation.aggregateDiscountPpm =
            _discountPpm(simulation.totalVulnerableShares, simulation.totalCorrectedShares);
    }

    function simulateBalancedExitPressure(
        address pool,
        uint256 sharesPerStep,
        uint256 steps
    ) external view returns (DrainSimulation memory simulation) {
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        uint256 supply = _totalSupply(pool);
        uint256 invariant = ILumenPool(pool).cachedInvariant();
        uint256 amplification = ILumenPool(pool).amplification();
        simulation.steps = new DrainStep[](steps);

        for (uint256 i; i < steps; ++i) {
            if (supply == 0 || sharesPerStep == 0 || sharesPerStep > supply) break;
            uint256 amount0 = FullMath.mulDiv(sharesPerStep, balances.virtual0, supply);
            uint256 amount1 = FullMath.mulDiv(sharesPerStep, balances.virtual1, supply);
            DrainStep memory step =
                _simulateDrainStep(balances, supply, invariant, amplification, amount0, amount1);
            step.vulnerableShares = sharesPerStep;
            step.correctedShares = sharesPerStep;
            step.supplyAfterVulnerableBurn = supply - sharesPerStep;
            simulation.steps[i] = step;

            simulation.totalAmount0 += amount0;
            simulation.totalAmount1 += amount1;
            simulation.totalVulnerableShares += sharesPerStep;
            simulation.totalCorrectedShares += sharesPerStep;
            balances.virtual0 = step.virtual0After;
            balances.virtual1 = step.virtual1After;
            invariant = step.invariantAfter;
            supply = step.supplyAfterVulnerableBurn;
        }

        simulation.finalInvariant = invariant;
        simulation.finalVirtual0 = balances.virtual0;
        simulation.finalVirtual1 = balances.virtual1;
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

    function correctedImbalanceQuote(
        address pool,
        uint256 amount0,
        uint256 amount1
    )
        external
        view
        returns (
            ImbalanceQuote memory protocolQuote,
            uint256 correctedShares,
            uint256 underburnedShares,
            uint256 discountPpm
        )
    {
        protocolQuote = ILumenPool(pool).quoteRemoveLiquidityImbalanced(amount0, amount1);
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        uint256 correctedInvariant = StableSwapMath.getD(
            balances.virtual0 - amount0,
            balances.virtual1 - amount1,
            ILumenPool(pool).amplification()
        );
        correctedShares = StableSwapMath.quoteSharesForWithdrawal(
            _totalSupply(pool), ILumenPool(pool).cachedInvariant(), correctedInvariant
        ) + protocolQuote.imbalanceFeeShares;
        underburnedShares = correctedShares > protocolQuote.sharesToBurn
            ? correctedShares - protocolQuote.sharesToBurn
            : 0;
        discountPpm = _discountPpm(protocolQuote.sharesToBurn, correctedShares);
    }

    function batchCorrectedImbalanceQuotes(
        address pool,
        uint256[] calldata amounts0,
        uint256[] calldata amounts1
    )
        external
        view
        returns (
            ImbalanceQuote[] memory protocolQuotes,
            uint256[] memory correctedShares,
            uint256[] memory underburnedShares,
            uint256[] memory discountPpm
        )
    {
        require(amounts0.length == amounts1.length, "LEN");
        protocolQuotes = new ImbalanceQuote[](amounts0.length);
        correctedShares = new uint256[](amounts0.length);
        underburnedShares = new uint256[](amounts0.length);
        discountPpm = new uint256[](amounts0.length);
        for (uint256 i; i < amounts0.length; ++i) {
            (protocolQuotes[i], correctedShares[i], underburnedShares[i], discountPpm[i]) =
                this.correctedImbalanceQuote(pool, amounts0[i], amounts1[i]);
        }
    }

    function maxSingleSidedWithdrawalBeforeReserve(
        address pool,
        bool token0Side,
        uint256 minReserve
    ) external view returns (uint256 amount) {
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        uint256 reserve = token0Side ? balances.virtual0 : balances.virtual1;
        amount = reserve > minReserve ? reserve - minReserve : 0;
    }

    function estimateSharesLeftAfterDrain(
        address pool,
        bool withdrawToken0,
        uint256 amountPerStep,
        uint256 steps
    ) external view returns (uint256 vulnerableSupply, uint256 correctedSupply) {
        PoolBalances memory balances = ILumenPool(pool).getBalances();
        vulnerableSupply = _totalSupply(pool);
        correctedSupply = vulnerableSupply;
        uint256 invariant = ILumenPool(pool).cachedInvariant();
        uint256 amplification = ILumenPool(pool).amplification();

        for (uint256 i; i < steps; ++i) {
            uint256 amount0 = withdrawToken0 ? _boundedAmount(amountPerStep, balances.virtual0) : 0;
            uint256 amount1 = withdrawToken0 ? 0 : _boundedAmount(amountPerStep, balances.virtual1);
            if (amount0 == 0 && amount1 == 0) break;
            DrainStep memory step = _simulateDrainStep(
                balances, vulnerableSupply, invariant, amplification, amount0, amount1
            );
            vulnerableSupply = vulnerableSupply > step.vulnerableShares
                ? vulnerableSupply - step.vulnerableShares
                : 0;
            correctedSupply =
                correctedSupply > step.correctedShares ? correctedSupply - step.correctedShares : 0;
            balances.virtual0 = step.virtual0After;
            balances.virtual1 = step.virtual1After;
            invariant = step.invariantAfter;
        }
    }

    function _simulateDrainStep(
        PoolBalances memory balances,
        uint256 supply,
        uint256 invariant,
        uint256 amplification,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (DrainStep memory step) {
        uint256 feeShares = _localImbalanceFeeShares(supply, invariant, amount0, amount1);
        LumenAccounting.ImbalanceComparison memory comparison = balances.compareImbalanceBurn(
            supply, invariant, amplification, amount0, amount1, feeShares
        );
        step = DrainStep({
            amount0: amount0,
            amount1: amount1,
            vulnerableShares: comparison.staleShares,
            correctedShares: comparison.correctedShares,
            invariantBefore: invariant,
            invariantAfter: comparison.correctedInvariant,
            supplyAfterVulnerableBurn: supply > comparison.staleShares
                ? supply - comparison.staleShares
                : 0,
            virtual0After: balances.virtual0 - amount0,
            virtual1After: balances.virtual1 - amount1
        });
    }

    function _localImbalanceFeeShares(
        uint256 supply,
        uint256 invariant,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 shares) {
        if (supply == 0 || invariant == 0 || amount0 + amount1 == 0) return 0;
        uint256 baseShares = FullMath.mulDiv(supply, amount0 + amount1, invariant);
        shares = FullMath.mulDiv(baseShares, 500, PPM);
        if (shares == 0) shares = 1;
    }

    function _boundedAmount(
        uint256 requested,
        uint256 available
    ) internal pure returns (uint256) {
        if (available == 0) return 0;
        if (requested >= available) return available - 1;
        return requested;
    }

    function _discountPpm(
        uint256 vulnerableShares,
        uint256 correctedShares
    ) internal pure returns (uint256) {
        if (correctedShares == 0 || vulnerableShares >= correctedShares) return 0;
        return FullMath.mulDiv(correctedShares - vulnerableShares, PPM, correctedShares);
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
