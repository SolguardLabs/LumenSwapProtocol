// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "../libraries/FullMath.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { PoolBalances } from "../types/LumenTypes.sol";

library LumenAccounting {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant PPM = 1_000_000;

    struct Reconciliation {
        uint256 physical0;
        uint256 physical1;
        uint256 expectedGross0;
        uint256 expectedGross1;
        uint256 activeValue;
        uint256 liabilityValue;
        uint256 surplus0;
        uint256 surplus1;
        bool grossMatchesPhysical;
        bool liabilitiesCovered;
    }

    struct ShareValue {
        uint256 virtualValue;
        uint256 feeValue;
        uint256 protocolValue;
        uint256 navPerShareWad;
        uint256 principalPerShareWad;
        uint256 lpFeePerShareWad;
    }

    struct FeeSolvency {
        uint256 pendingLPFees;
        uint256 protocolFees;
        uint256 totalLiabilities;
        uint256 grossAssets;
        uint256 virtualAssets;
        uint256 excessAssets;
        bool solvent;
    }

    function reconcile(
        PoolBalances memory balances,
        uint256 physical0,
        uint256 physical1
    ) internal pure returns (Reconciliation memory data) {
        data.physical0 = physical0;
        data.physical1 = physical1;
        data.expectedGross0 = balances.virtual0 + balances.pendingLPFee0 + balances.protocolFee0;
        data.expectedGross1 = balances.virtual1 + balances.pendingLPFee1 + balances.protocolFee1;
        data.activeValue = balances.virtual0 + balances.virtual1;
        data.liabilityValue = balances.pendingLPFee0 + balances.pendingLPFee1
            + balances.protocolFee0 + balances.protocolFee1;
        data.surplus0 = physical0 > balances.gross0 ? physical0 - balances.gross0 : 0;
        data.surplus1 = physical1 > balances.gross1 ? physical1 - balances.gross1 : 0;
        data.grossMatchesPhysical = physical0 == balances.gross0 && physical1 == balances.gross1;
        data.liabilitiesCovered = balances.gross0 >= balances.pendingLPFee0 + balances.protocolFee0
            && balances.gross1 >= balances.pendingLPFee1 + balances.protocolFee1;
    }

    function shareValue(
        PoolBalances memory balances,
        uint256 totalSupply,
        uint256 lockedLiquidity
    ) internal pure returns (ShareValue memory value) {
        uint256 feeBearingSupply = totalSupply > lockedLiquidity ? totalSupply - lockedLiquidity : 0;
        value.virtualValue = balances.virtual0 + balances.virtual1;
        value.feeValue = balances.pendingLPFee0 + balances.pendingLPFee1;
        value.protocolValue = balances.protocolFee0 + balances.protocolFee1;
        if (totalSupply != 0) {
            value.navPerShareWad =
                FullMath.mulDiv(value.virtualValue + value.feeValue, WAD, totalSupply);
            value.principalPerShareWad = FullMath.mulDiv(value.virtualValue, WAD, totalSupply);
        }
        if (feeBearingSupply != 0) {
            value.lpFeePerShareWad = FullMath.mulDiv(value.feeValue, WAD, feeBearingSupply);
        }
    }

    function feeSolvency(
        PoolBalances memory balances
    ) internal pure returns (FeeSolvency memory data) {
        data.pendingLPFees = balances.pendingLPFee0 + balances.pendingLPFee1;
        data.protocolFees = balances.protocolFee0 + balances.protocolFee1;
        data.totalLiabilities = data.pendingLPFees + data.protocolFees;
        data.grossAssets = balances.gross0 + balances.gross1;
        data.virtualAssets = balances.virtual0 + balances.virtual1;
        data.excessAssets =
            data.grossAssets > data.totalLiabilities ? data.grossAssets - data.totalLiabilities : 0;
        data.solvent = balances.gross0 >= balances.pendingLPFee0 + balances.protocolFee0
            && balances.gross1 >= balances.pendingLPFee1 + balances.protocolFee1;
    }

    function proRataAmounts(
        PoolBalances memory balances,
        uint256 shares,
        uint256 totalSupply
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (totalSupply == 0) return (0, 0);
        amount0 = FullMath.mulDiv(shares, balances.virtual0, totalSupply);
        amount1 = FullMath.mulDiv(shares, balances.virtual1, totalSupply);
    }

    function invariant(
        PoolBalances memory balances,
        uint256 amplification
    ) internal pure returns (uint256) {
        return StableSwapMath.getD(balances.virtual0, balances.virtual1, amplification);
    }

    function virtualCoveragePpm(
        PoolBalances memory balances
    ) internal pure returns (uint256 token0Coverage, uint256 token1Coverage) {
        token0Coverage =
            balances.gross0 == 0 ? 0 : FullMath.mulDiv(balances.virtual0, PPM, balances.gross0);
        token1Coverage =
            balances.gross1 == 0 ? 0 : FullMath.mulDiv(balances.virtual1, PPM, balances.gross1);
    }

    function liabilityCoveragePpm(
        PoolBalances memory balances
    ) internal pure returns (uint256 token0Coverage, uint256 token1Coverage) {
        uint256 liability0 = balances.pendingLPFee0 + balances.protocolFee0;
        uint256 liability1 = balances.pendingLPFee1 + balances.protocolFee1;
        token0Coverage =
            liability0 == 0 ? type(uint256).max : FullMath.mulDiv(balances.gross0, PPM, liability0);
        token1Coverage =
            liability1 == 0 ? type(uint256).max : FullMath.mulDiv(balances.gross1, PPM, liability1);
    }

    function withdrawalHeadroom(
        PoolBalances memory balances,
        uint256 minReserve
    ) internal pure returns (uint256 headroom0, uint256 headroom1) {
        headroom0 = balances.virtual0 > minReserve ? balances.virtual0 - minReserve : 0;
        headroom1 = balances.virtual1 > minReserve ? balances.virtual1 - minReserve : 0;
    }
}
