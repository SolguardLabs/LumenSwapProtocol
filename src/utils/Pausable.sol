// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenNotPaused, LumenPaused } from "../types/LumenErrors.sol";

abstract contract Pausable {
    bool public paused;

    event Paused(address indexed account);
    event Unpaused(address indexed account);

    modifier whenNotPaused() {
        if (paused) revert LumenPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert LumenNotPaused();
        _;
    }

    function _pause() internal whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
