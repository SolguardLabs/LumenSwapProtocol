// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PoolConfig } from "../types/LumenTypes.sol";
import { LumenPool } from "./LumenPool.sol";

contract LumenPoolDeployer {
    event PoolDeployed(bytes32 indexed salt, address indexed pool, address token0, address token1);

    function deploy(
        PoolConfig memory config,
        bytes32 salt
    ) external returns (address pool) {
        pool = address(new LumenPool{ salt: salt }(config));
        emit PoolDeployed(salt, pool, config.token0, config.token1);
    }

    function computeSalt(
        address token0,
        address token1,
        uint256 amplification
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1, amplification));
    }
}
