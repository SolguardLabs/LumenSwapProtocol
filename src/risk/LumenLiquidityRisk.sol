// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "../libraries/FullMath.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { PoolBalances } from "../types/LumenTypes.sol";

library LumenLiquidityRisk {
    uint256 internal constant PPM = 1_000_000;

    error InvalidStressConfiguration();

    enum Severity {
        Green,
        Amber,
        Red
    }

    struct StressConfig {
        uint32 redemptionPpm;
        uint32 reserveHaircutPpm;
        uint32 feeHaircutPpm;
        uint32 maximumSkewPpm;
        uint32 minimumCoveragePpm;
    }

    struct TokenStress {
        uint256 grossAssets;
        uint256 virtualLiquidity;
        uint256 feeLiabilities;
        uint256 reserveFloor;
        uint256 availablePrincipal;
        uint256 eligiblePrincipal;
        uint256 stressedOutflow;
        uint256 totalUses;
        uint256 coveragePpm;
        uint256 requiredBuffer;
    }

    struct PoolStress {
        TokenStress token0;
        TokenStress token1;
        uint256 invariantBefore;
        uint256 invariantAfter;
        uint256 invariantRetentionPpm;
        uint256 projectedSkewPpm;
        uint256 worstCoveragePpm;
        uint256 requiredBuffer;
        Severity severity;
    }

    function operatingConfig() internal pure returns (StressConfig memory config) {
        config = StressConfig({
            redemptionPpm: 100_000,
            reserveHaircutPpm: 50_000,
            feeHaircutPpm: 1_000_000,
            maximumSkewPpm: 250_000,
            minimumCoveragePpm: 1_200_000
        });
    }

    function severeConfig() internal pure returns (StressConfig memory config) {
        config = StressConfig({
            redemptionPpm: 400_000,
            reserveHaircutPpm: 250_000,
            feeHaircutPpm: 1_000_000,
            maximumSkewPpm: 400_000,
            minimumCoveragePpm: 1_500_000
        });
    }

    function validate(
        StressConfig memory config
    ) internal pure {
        if (
            config.redemptionPpm > PPM || config.reserveHaircutPpm > PPM
                || config.feeHaircutPpm > PPM || config.maximumSkewPpm > PPM
                || config.minimumCoveragePpm < PPM || config.minimumCoveragePpm > 5 * PPM
        ) {
            revert InvalidStressConfiguration();
        }
    }

    function assess(
        PoolBalances memory balances,
        uint256 amplification,
        uint256 reserveFloor0,
        uint256 reserveFloor1,
        StressConfig memory config
    ) internal pure returns (PoolStress memory report) {
        validate(config);
        report.token0 = _assessToken(
            balances.gross0,
            balances.virtual0,
            balances.pendingLPFee0 + balances.protocolFee0,
            reserveFloor0,
            config
        );
        report.token1 = _assessToken(
            balances.gross1,
            balances.virtual1,
            balances.pendingLPFee1 + balances.protocolFee1,
            reserveFloor1,
            config
        );

        report.invariantBefore =
            StableSwapMath.getD(balances.virtual0, balances.virtual1, amplification);
        uint256 projected0 = balances.virtual0 > report.token0.stressedOutflow
            ? balances.virtual0 - report.token0.stressedOutflow
            : 1;
        uint256 projected1 = balances.virtual1 > report.token1.stressedOutflow
            ? balances.virtual1 - report.token1.stressedOutflow
            : 1;
        report.invariantAfter = StableSwapMath.getD(projected0, projected1, amplification);
        report.invariantRetentionPpm = report.invariantBefore == 0
            ? 0
            : FullMath.mulDiv(report.invariantAfter, PPM, report.invariantBefore);
        report.projectedSkewPpm = _skewPpm(projected0, projected1);
        report.worstCoveragePpm = report.token0.coveragePpm < report.token1.coveragePpm
            ? report.token0.coveragePpm
            : report.token1.coveragePpm;
        report.requiredBuffer = report.token0.requiredBuffer + report.token1.requiredBuffer;
        report.severity = _severity(report, config);
    }

    function _assessToken(
        uint256 grossAssets,
        uint256 virtualLiquidity,
        uint256 feeLiabilities,
        uint256 reserveFloor,
        StressConfig memory config
    ) private pure returns (TokenStress memory row) {
        row.grossAssets = grossAssets;
        row.virtualLiquidity = virtualLiquidity;
        row.feeLiabilities = feeLiabilities;
        row.reserveFloor = reserveFloor;
        row.availablePrincipal =
            virtualLiquidity > reserveFloor ? virtualLiquidity - reserveFloor : 0;
        row.eligiblePrincipal =
            FullMath.mulDiv(row.availablePrincipal, PPM - config.reserveHaircutPpm, PPM);
        uint256 eligibleFees = FullMath.mulDiv(feeLiabilities, PPM - config.feeHaircutPpm, PPM);
        row.eligiblePrincipal += eligibleFees;
        row.stressedOutflow = FullMath.mulDiv(virtualLiquidity, config.redemptionPpm, PPM);
        row.totalUses = row.stressedOutflow + feeLiabilities;
        row.coveragePpm = row.totalUses == 0
            ? type(uint256).max
            : FullMath.mulDiv(row.eligiblePrincipal, PPM, row.totalUses);
        uint256 requiredResources = FullMath.mulDiv(row.totalUses, config.minimumCoveragePpm, PPM);
        row.requiredBuffer = requiredResources > row.eligiblePrincipal
            ? requiredResources - row.eligiblePrincipal
            : 0;
    }

    function _severity(
        PoolStress memory report,
        StressConfig memory config
    ) private pure returns (Severity) {
        if (
            report.token0.coveragePpm < PPM || report.token1.coveragePpm < PPM
                || report.invariantAfter == 0
        ) {
            return Severity.Red;
        }
        if (
            report.worstCoveragePpm < config.minimumCoveragePpm
                || report.projectedSkewPpm > config.maximumSkewPpm
        ) {
            return Severity.Amber;
        }
        return Severity.Green;
    }

    function _skewPpm(
        uint256 amount0,
        uint256 amount1
    ) private pure returns (uint256) {
        uint256 total = amount0 + amount1;
        if (total == 0) return 0;
        uint256 difference = amount0 > amount1 ? amount0 - amount1 : amount1 - amount0;
        return FullMath.mulDiv(difference, PPM, total);
    }
}
