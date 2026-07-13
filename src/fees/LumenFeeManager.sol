// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILumenFeeManager } from "../interfaces/ILumenFeeManager.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { StableSwapMath } from "../libraries/StableSwapMath.sol";
import { LumenInvalidFee } from "../types/LumenErrors.sol";
import { FeeConfig, FeeQuote } from "../types/LumenTypes.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

contract LumenFeeManager is ILumenFeeManager, Ownable2Step {
    using FixedPointMath for uint256;

    FeeConfig private _config;

    event FeeConfigUpdated(
        uint24 baseSwapFeePpm,
        uint24 adminFeePpm,
        uint24 imbalanceFeePpm,
        uint24 sizeFeePpm,
        uint24 maxFeePpm
    );

    constructor(
        address owner_,
        FeeConfig memory config_
    ) Ownable2Step(owner_) {
        _setConfig(config_);
    }

    function config() external view returns (FeeConfig memory) {
        return _config;
    }

    function setConfig(
        FeeConfig calldata newConfig
    ) external onlyOwner {
        _setConfig(newConfig);
    }

    function quoteSwapFee(
        address,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (FeeQuote memory quote) {
        FeeConfig memory local = _config;
        uint256 sizeComponent;
        uint256 imbalanceComponent;

        if (reserveIn != 0 && amountIn != 0) {
            uint256 sizePpm = FixedPointMath.min(
                FixedPointMath.mulDiv(amountIn, 1_000_000, reserveIn + amountIn), 1_000_000
            );
            sizeComponent = FixedPointMath.mulDiv(sizePpm, local.sizeFeePpm, 1_000_000);
        }

        uint256 imbalance = StableSwapMath.imbalanceScore(reserveIn, reserveOut);
        imbalanceComponent = FixedPointMath.mulDiv(imbalance, local.imbalanceFeePpm, 1_000_000);

        uint256 feePpm = uint256(local.baseSwapFeePpm) + sizeComponent + imbalanceComponent;
        if (feePpm > local.maxFeePpm) feePpm = local.maxFeePpm;

        // forge-lint: disable-next-line(unsafe-typecast)
        quote.feePpm = uint24(feePpm);
        quote.totalFee = amountIn.ppmOf(feePpm);
        quote.protocolFee = quote.totalFee.ppmOf(local.adminFeePpm);
        quote.lpFee = quote.totalFee - quote.protocolFee;
    }

    function quoteImbalanceFeeShares(
        address,
        uint256 totalSupply,
        uint256 invariant,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint256 shares) {
        if (totalSupply == 0 || invariant == 0) return 0;
        uint256 valueOut = amount0 + amount1;
        uint256 baseShares = FixedPointMath.mulDiv(totalSupply, valueOut, invariant);
        shares = baseShares.ppmOf(_config.imbalanceFeePpm);
        if (shares == 0 && valueOut != 0) shares = 1;
    }

    function _setConfig(
        FeeConfig memory newConfig
    ) internal {
        if (
            newConfig.baseSwapFeePpm > 100_000 || newConfig.adminFeePpm > 1_000_000
                || newConfig.imbalanceFeePpm > 200_000 || newConfig.sizeFeePpm > 100_000
                || newConfig.maxFeePpm > 200_000 || newConfig.baseSwapFeePpm > newConfig.maxFeePpm
        ) {
            revert LumenInvalidFee();
        }
        _config = newConfig;
        emit FeeConfigUpdated(
            newConfig.baseSwapFeePpm,
            newConfig.adminFeePpm,
            newConfig.imbalanceFeePpm,
            newConfig.sizeFeePpm,
            newConfig.maxFeePpm
        );
    }
}
