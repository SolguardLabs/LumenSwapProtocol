// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ILumenFactory } from "../interfaces/ILumenFactory.sol";
import {
    LumenIdenticalTokens,
    LumenPoolExists,
    LumenPoolNotFound,
    LumenZeroAddress
} from "../types/LumenErrors.sol";
import { PoolConfig } from "../types/LumenTypes.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";
import { LumenPool } from "./LumenPool.sol";

contract LumenFactory is ILumenFactory, Ownable2Step {
    address public defaultFeeManager;
    address public defaultBalanceGuard;
    address public defaultFeeRecipient;

    mapping(bytes32 key => address pool) private _pools;
    address[] private _allPools;

    constructor(
        address owner_,
        address defaultFeeRecipient_,
        address defaultFeeManager_,
        address defaultBalanceGuard_
    ) Ownable2Step(owner_) {
        if (defaultFeeRecipient_ == address(0)) revert LumenZeroAddress();
        defaultFeeRecipient = defaultFeeRecipient_;
        defaultFeeManager = defaultFeeManager_;
        defaultBalanceGuard = defaultBalanceGuard_;
    }

    function allPools(
        uint256 index
    ) external view returns (address pool) {
        return _allPools[index];
    }

    function allPoolsLength() external view returns (uint256 length) {
        return _allPools.length;
    }

    function getPool(
        address tokenA,
        address tokenB
    ) public view returns (address pool) {
        (address token0, address token1) = _sort(tokenA, tokenB);
        pool = _pools[_key(token0, token1)];
    }

    function setDefaultFeeRecipient(
        address recipient
    ) external onlyOwner {
        if (recipient == address(0)) revert LumenZeroAddress();
        defaultFeeRecipient = recipient;
        emit DefaultFeeRecipientUpdated(recipient);
    }

    function setDefaultFeeManager(
        address manager
    ) external onlyOwner {
        defaultFeeManager = manager;
        emit DefaultFeeManagerUpdated(manager);
    }

    function setDefaultBalanceGuard(
        address guard
    ) external onlyOwner {
        defaultBalanceGuard = guard;
        emit DefaultBalanceGuardUpdated(guard);
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint256 amplification
    ) external returns (address pool) {
        (address token0, address token1) = _sort(tokenA, tokenB);
        PoolConfig memory config = PoolConfig({
            token0: token0,
            token1: token1,
            owner: owner,
            feeRecipient: defaultFeeRecipient,
            feeManager: defaultFeeManager,
            balanceGuard: defaultBalanceGuard,
            oracle: address(0),
            amplification: amplification
        });
        pool = _create(config);
    }

    function createPoolWithConfig(
        PoolConfig calldata config
    ) external returns (address pool) {
        (address token0, address token1) = _sort(config.token0, config.token1);
        PoolConfig memory sorted = PoolConfig({
            token0: token0,
            token1: token1,
            owner: config.owner == address(0) ? owner : config.owner,
            feeRecipient: config.feeRecipient == address(0)
                ? defaultFeeRecipient
                : config.feeRecipient,
            feeManager: config.feeManager,
            balanceGuard: config.balanceGuard,
            oracle: config.oracle,
            amplification: config.amplification
        });
        pool = _create(sorted);
    }

    function requirePool(
        address tokenA,
        address tokenB
    ) external view returns (address pool) {
        pool = getPool(tokenA, tokenB);
        if (pool == address(0)) revert LumenPoolNotFound();
    }

    function _create(
        PoolConfig memory config
    ) internal returns (address pool) {
        bytes32 key = _key(config.token0, config.token1);
        if (_pools[key] != address(0)) revert LumenPoolExists();
        pool = address(new LumenPool(config));
        _pools[key] = pool;
        _allPools.push(pool);
        emit PoolCreated(config.token0, config.token1, pool, config.amplification);
    }

    function _sort(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == address(0) || tokenB == address(0)) revert LumenZeroAddress();
        if (tokenA == tokenB) revert LumenIdenticalTokens();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _key(
        address token0,
        address token1
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1));
    }
}
