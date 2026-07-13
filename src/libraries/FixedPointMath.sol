// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "./FullMath.sol";

library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant PPM = 1_000_000;
    uint256 internal constant Q128 = 1 << 128;

    function min(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function mulWad(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(a, b, WAD);
    }

    function divWad(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(a, WAD, b);
    }

    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function ppmOf(
        uint256 amount,
        uint256 ppm
    ) internal pure returns (uint256) {
        if (amount == 0 || ppm == 0) return 0;
        return FullMath.mulDiv(amount, ppm, PPM);
    }

    function bpsOf(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return 0;
        return FullMath.mulDiv(amount, bps, BPS);
    }

    function sqrt(
        uint256 x
    ) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = 1;
        uint256 y = x;
        if (y >= 1 << 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 1 << 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 1 << 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 1 << 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 1 << 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 1 << 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 1 << 2) z <<= 1;

        unchecked {
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            uint256 roundedDown = x / z;
            return z < roundedDown ? z : roundedDown;
        }
    }

    function clamp(
        uint256 value,
        uint256 low,
        uint256 high
    ) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }
}
