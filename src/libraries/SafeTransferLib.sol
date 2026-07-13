// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library SafeTransferLib {
    error TransferFailed();
    error TransferFromFailed();
    error ApproveFailed();

    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        bool success;
        assembly ("memory-safe") {
            let freeMemoryPointer := mload(0x40)
            mstore(
                freeMemoryPointer,
                0xa9059cbb00000000000000000000000000000000000000000000000000000000
            )
            mstore(add(freeMemoryPointer, 4), to)
            mstore(add(freeMemoryPointer, 36), amount)
            success := call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
            if and(success, returndatasize()) {
                success := and(eq(returndatasize(), 32), eq(mload(0), 1))
            }
        }
        if (!success) revert TransferFailed();
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bool success;
        assembly ("memory-safe") {
            let freeMemoryPointer := mload(0x40)
            mstore(
                freeMemoryPointer,
                0x23b872dd00000000000000000000000000000000000000000000000000000000
            )
            mstore(add(freeMemoryPointer, 4), from)
            mstore(add(freeMemoryPointer, 36), to)
            mstore(add(freeMemoryPointer, 68), amount)
            success := call(gas(), token, 0, freeMemoryPointer, 100, 0, 32)
            if and(success, returndatasize()) {
                success := and(eq(returndatasize(), 32), eq(mload(0), 1))
            }
        }
        if (!success) revert TransferFromFailed();
    }

    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        bool success;
        assembly ("memory-safe") {
            let freeMemoryPointer := mload(0x40)
            mstore(
                freeMemoryPointer,
                0x095ea7b300000000000000000000000000000000000000000000000000000000
            )
            mstore(add(freeMemoryPointer, 4), spender)
            mstore(add(freeMemoryPointer, 36), amount)
            success := call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
            if and(success, returndatasize()) {
                success := and(eq(returndatasize(), 32), eq(mload(0), 1))
            }
        }
        if (!success) revert ApproveFailed();
    }
}
