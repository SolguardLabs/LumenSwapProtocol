// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "./FullMath.sol";

library StableSwapMath {
    uint256 internal constant N_COINS = 2;
    uint256 internal constant A_PRECISION = 100;
    uint256 internal constant MAX_ITERATIONS = 255;

    error InvalidTokenIndex();
    error InvalidAmplification();
    error NoConvergence();
    error EmptyPool();

    function validateAmplification(
        uint256 amplification
    ) internal pure {
        if (amplification < A_PRECISION || amplification > 10_000 * A_PRECISION) {
            revert InvalidAmplification();
        }
    }

    function getD(
        uint256 balance0,
        uint256 balance1,
        uint256 amplification
    ) internal pure returns (uint256 d) {
        validateAmplification(amplification);
        uint256 sum = balance0 + balance1;
        if (sum == 0) return 0;
        if (balance0 == 0 || balance1 == 0) return sum;

        d = sum;
        uint256 ann = amplification * N_COINS;
        for (uint256 i; i < MAX_ITERATIONS; ++i) {
            uint256 dP = d;
            dP = FullMath.mulDiv(dP, d, balance0 * N_COINS);
            dP = FullMath.mulDiv(dP, d, balance1 * N_COINS);

            uint256 previousD = d;
            uint256 numerator = (FullMath.mulDiv(ann, sum, A_PRECISION) + dP * N_COINS) * d;
            uint256 denominator =
                FullMath.mulDiv(ann - A_PRECISION, d, A_PRECISION) + (N_COINS + 1) * dP;
            d = numerator / denominator;

            if (d > previousD) {
                if (d - previousD <= 1) return d;
            } else if (previousD - d <= 1) {
                return d;
            }
        }
        revert NoConvergence();
    }

    function getY(
        uint256 indexIn,
        uint256 indexOut,
        uint256 newBalanceIn,
        uint256 balance0,
        uint256 balance1,
        uint256 amplification
    ) internal pure returns (uint256 y) {
        if (indexIn == indexOut || indexIn >= N_COINS || indexOut >= N_COINS) {
            revert InvalidTokenIndex();
        }
        uint256 d = getD(balance0, balance1, amplification);
        if (d == 0) revert EmptyPool();

        uint256 ann = amplification * N_COINS;
        uint256 c = FullMath.mulDiv(d, d, newBalanceIn * N_COINS);
        uint256 s = newBalanceIn;

        c = FullMath.mulDiv(c, d, FullMath.mulDiv(ann, N_COINS, A_PRECISION));
        uint256 b = s + FullMath.mulDiv(d, A_PRECISION, ann);
        y = d;
        for (uint256 i; i < MAX_ITERATIONS; ++i) {
            uint256 previousY = y;
            y = (y * y + c) / (2 * y + b - d);
            if (y > previousY) {
                if (y - previousY <= 1) return y;
            } else if (previousY - y <= 1) {
                return y;
            }
        }
        revert NoConvergence();
    }

    function getYForD(
        uint256 tokenIndex,
        uint256 balanceOther,
        uint256 d,
        uint256 amplification
    ) internal pure returns (uint256 y) {
        if (tokenIndex >= N_COINS) revert InvalidTokenIndex();
        validateAmplification(amplification);
        if (d == 0) return 0;

        uint256 ann = amplification * N_COINS;
        uint256 c = d;
        c = FullMath.mulDiv(c, d, balanceOther * N_COINS);
        c = FullMath.mulDiv(c, d, FullMath.mulDiv(ann, N_COINS, A_PRECISION));
        uint256 b = balanceOther + FullMath.mulDiv(d, A_PRECISION, ann);
        y = d;
        for (uint256 i; i < MAX_ITERATIONS; ++i) {
            uint256 previousY = y;
            y = (y * y + c) / (2 * y + b - d);
            if (y > previousY) {
                if (y - previousY <= 1) return y;
            } else if (previousY - y <= 1) {
                return y;
            }
        }
        revert NoConvergence();
    }

    function quoteSharesForDeposit(
        uint256 totalSupply,
        uint256 oldD,
        uint256 newD
    ) internal pure returns (uint256 shares) {
        if (newD <= oldD) return 0;
        if (totalSupply == 0) return newD;
        shares = FullMath.mulDiv(totalSupply, newD - oldD, oldD);
    }

    function quoteSharesForWithdrawal(
        uint256 totalSupply,
        uint256 oldD,
        uint256 newD
    ) internal pure returns (uint256 shares) {
        if (newD >= oldD) return 0;
        shares = FullMath.mulDiv(totalSupply, oldD - newD, oldD);
    }

    function imbalanceScore(
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (uint256 scorePpm) {
        uint256 sum = balance0 + balance1;
        if (sum == 0) return 0;
        uint256 diff = balance0 > balance1 ? balance0 - balance1 : balance1 - balance0;
        scorePpm = FullMath.mulDiv(diff, 1_000_000, sum);
    }

    function normalizedValue(
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (uint256) {
        return balance0 + balance1;
    }
}
