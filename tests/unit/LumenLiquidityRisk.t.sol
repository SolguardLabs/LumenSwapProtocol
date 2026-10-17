// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    ExitLadderStep,
    LumenScenarioSimulator
} from "../../src/periphery/LumenScenarioSimulator.sol";
import { LumenLiquidityRisk } from "../../src/risk/LumenLiquidityRisk.sol";
import { PoolBalances } from "../../src/types/LumenTypes.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";

contract LumenLiquidityRiskTest is PoolTestBase {
    function test_OperatingStressKeepsBalancedPoolGreen() public {
        _initializePool();
        LumenLiquidityRisk.PoolStress memory report = LumenLiquidityRisk.assess(
            pool.getBalances(),
            AMP,
            1_000_000 ether,
            1_000_000 ether,
            LumenLiquidityRisk.operatingConfig()
        );

        assertEq(uint256(report.severity), uint256(LumenLiquidityRisk.Severity.Green));
        assertEq(report.projectedSkewPpm, 0);
        assertEq(report.invariantRetentionPpm, 900_000);
        assertGt(report.worstCoveragePpm, 1_200_000);
        assertEq(report.requiredBuffer, 0);
    }

    function test_SevereStressPublishesInvariantRetentionAndCoverage() public {
        _initializePool();
        LumenLiquidityRisk.PoolStress memory report = LumenLiquidityRisk.assess(
            pool.getBalances(),
            AMP,
            1_000_000 ether,
            1_000_000 ether,
            LumenLiquidityRisk.severeConfig()
        );

        assertEq(report.invariantRetentionPpm, 600_000);
        assertEq(report.worstCoveragePpm, 1_687_500);
        assertEq(uint256(report.severity), uint256(LumenLiquidityRisk.Severity.Green));
    }

    function test_SevereCustomShockTurnsCoverageRed() public {
        _initializePool();
        LumenLiquidityRisk.StressConfig memory config = LumenLiquidityRisk.StressConfig({
            redemptionPpm: 900_000,
            reserveHaircutPpm: 500_000,
            feeHaircutPpm: 1_000_000,
            maximumSkewPpm: 500_000,
            minimumCoveragePpm: 1_200_000
        });
        LumenLiquidityRisk.PoolStress memory report = LumenLiquidityRisk.assess(
            pool.getBalances(), AMP, 1_000_000 ether, 1_000_000 ether, config
        );

        assertEq(uint256(report.severity), uint256(LumenLiquidityRisk.Severity.Red));
        assertEq(report.worstCoveragePpm, 500_000);
        assertGt(report.requiredBuffer, 0);
    }

    function test_ProjectingSkewMovesOtherwiseCoveredPoolToAmber() public pure {
        PoolBalances memory balances = PoolBalances({
            gross0: 10_000_000 ether,
            gross1: 2_000_000 ether,
            virtual0: 10_000_000 ether,
            virtual1: 2_000_000 ether,
            pendingLPFee0: 0,
            pendingLPFee1: 0,
            protocolFee0: 0,
            protocolFee1: 0
        });
        LumenLiquidityRisk.PoolStress memory report = LumenLiquidityRisk.assess(
            balances, AMP, 1_000_000 ether, 0, LumenLiquidityRisk.operatingConfig()
        );

        assertGt(report.projectedSkewPpm, 250_000);
        assertEq(uint256(report.severity), uint256(LumenLiquidityRisk.Severity.Amber));
    }

    function test_FeeLiabilitiesAreIncludedInStressUses() public {
        _initializePool();
        _swap(TRADER, token0, 1_000_000 ether);
        PoolBalances memory balances = pool.getBalances();
        LumenLiquidityRisk.PoolStress memory report = LumenLiquidityRisk.assess(
            balances, AMP, 1_000_000 ether, 1_000_000 ether, LumenLiquidityRisk.operatingConfig()
        );

        assertGt(report.token0.feeLiabilities, 0);
        assertEq(
            report.token0.totalUses, report.token0.stressedOutflow + report.token0.feeLiabilities
        );
    }

    function test_SimulatorExposesStressAndProportionalExitLadder() public {
        _initializePool();
        LumenScenarioSimulator simulator = new LumenScenarioSimulator();
        LumenLiquidityRisk.PoolStress memory report =
            simulator.operatingStress(address(pool), 1_000_000 ether, 1_000_000 ether);
        ExitLadderStep[] memory ladder =
            simulator.proportionalExitLadder(address(pool), pool.totalSupply() / 20, 3);

        assertEq(uint256(report.severity), uint256(LumenLiquidityRisk.Severity.Green));
        assertGt(ladder[0].amount0, 0);
        assertGt(ladder[1].invariantAfter, 0);
        assertLt(ladder[2].supplyAfter, ladder[0].supplyAfter);
    }

    function test_InvalidStressConfigurationReverts() public {
        LumenLiquidityRisk.StressConfig memory config = LumenLiquidityRisk.operatingConfig();
        config.redemptionPpm = 1_000_001;
        vm.expectRevert(LumenLiquidityRisk.InvalidStressConfiguration.selector);
        this.validateConfig(config);
    }

    function validateConfig(
        LumenLiquidityRisk.StressConfig calldata config
    ) external pure {
        LumenLiquidityRisk.validate(config);
    }
}
