// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenFactory } from "../src/core/LumenFactory.sol";
import { LumenFeeManager } from "../src/fees/LumenFeeManager.sol";
import { LumenBalanceGuard } from "../src/risk/LumenBalanceGuard.sol";
import { FeeConfig } from "../src/types/LumenTypes.sol";

contract DeployLumen {
    function deploy(
        address owner,
        address feeRecipient
    ) external returns (LumenFeeManager feeManager, LumenBalanceGuard guard, LumenFactory factory) {
        feeManager = new LumenFeeManager(
            owner,
            FeeConfig({
                baseSwapFeePpm: 400,
                adminFeePpm: 500_000,
                imbalanceFeePpm: 500,
                sizeFeePpm: 0,
                maxFeePpm: 5000
            })
        );
        guard = new LumenBalanceGuard(owner, 1 ether, 1_000_000, 9500);
        factory = new LumenFactory(owner, feeRecipient, address(feeManager), address(guard));
    }
}
