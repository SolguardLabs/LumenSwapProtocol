// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenReentrancy } from "../types/LumenErrors.sol";

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status = NOT_ENTERED;

    modifier nonReentrant() {
        if (_status == ENTERED) revert LumenReentrancy();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}
