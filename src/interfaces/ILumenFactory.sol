// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PoolConfig } from "../types/LumenTypes.sol";

interface ILumenFactory {
    event PoolCreated(
        address indexed token0, address indexed token1, address indexed pool, uint256 amplification
    );
    event DefaultFeeManagerUpdated(address indexed feeManager);
    event DefaultBalanceGuardUpdated(address indexed balanceGuard);
    event DefaultFeeRecipientUpdated(address indexed feeRecipient);

    function getPool(
        address tokenA,
        address tokenB
    ) external view returns (address pool);
    function allPools(
        uint256 index
    ) external view returns (address pool);
    function allPoolsLength() external view returns (uint256 length);
    function createPool(
        address tokenA,
        address tokenB,
        uint256 amplification
    ) external returns (address pool);
    function createPoolWithConfig(
        PoolConfig calldata config
    ) external returns (address pool);
}
