// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "../libraries/FullMath.sol";
import {
    LumenInvalidObservation,
    LumenOracleNotReady,
    LumenUnauthorized,
    LumenZeroAddress
} from "../types/LumenErrors.sol";
import { OracleObservation } from "../types/LumenTypes.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

contract LumenOracle is Ownable2Step {
    uint256 public constant CARDINALITY = 64;

    address public pool;
    uint16 public index;
    uint16 public count;

    OracleObservation[CARDINALITY] private _observations;

    event PoolBound(address indexed pool);
    event ObservationWritten(
        uint16 indexed index,
        uint32 timestamp,
        uint224 price0Cumulative,
        uint224 price1Cumulative,
        uint128 virtual0,
        uint128 virtual1
    );

    constructor(
        address owner_
    ) Ownable2Step(owner_) { }

    modifier onlyPool() {
        if (msg.sender != pool) revert LumenUnauthorized();
        _;
    }

    function bindPool(
        address pool_
    ) external onlyOwner {
        if (pool_ == address(0)) revert LumenZeroAddress();
        if (pool != address(0)) revert LumenInvalidObservation();
        pool = pool_;
        emit PoolBound(pool_);
    }

    function observation(
        uint256 slot
    ) external view returns (OracleObservation memory) {
        if (slot >= CARDINALITY) revert LumenInvalidObservation();
        return _observations[slot];
    }

    function latest() external view returns (OracleObservation memory obs) {
        if (count == 0) revert LumenOracleNotReady();
        return _observations[index];
    }

    function write(
        uint256 virtual0,
        uint256 virtual1
    ) external onlyPool returns (uint16 writtenIndex) {
        uint32 timestamp = uint32(block.timestamp);
        OracleObservation memory previous =
            count == 0 ? OracleObservation(0, 0, 0, 0, 0) : _observations[index];
        uint224 cumulative0 = previous.price0Cumulative;
        uint224 cumulative1 = previous.price1Cumulative;

        if (previous.timestamp != 0 && timestamp > previous.timestamp) {
            uint256 elapsed = timestamp - previous.timestamp;
            if (previous.virtual0 != 0 && previous.virtual1 != 0) {
                cumulative0 += _toUint224(
                    FullMath.mulDiv(uint256(previous.virtual1), 1e18, previous.virtual0) * elapsed
                );
                cumulative1 += _toUint224(
                    FullMath.mulDiv(uint256(previous.virtual0), 1e18, previous.virtual1) * elapsed
                );
            }
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        writtenIndex = count == 0 ? 0 : uint16((index + 1) % CARDINALITY);
        _observations[writtenIndex] = OracleObservation({
            timestamp: timestamp,
            price0Cumulative: cumulative0,
            price1Cumulative: cumulative1,
            virtual0: _toUint128(virtual0),
            virtual1: _toUint128(virtual1)
        });
        index = writtenIndex;
        if (count < CARDINALITY) count++;
        emit ObservationWritten(
            writtenIndex,
            timestamp,
            cumulative0,
            cumulative1,
            _toUint128(virtual0),
            _toUint128(virtual1)
        );
    }

    function consult(
        uint256 secondsAgo
    ) external view returns (uint256 price0Average, uint256 price1Average) {
        if (secondsAgo == 0 || count < 2) revert LumenOracleNotReady();
        OracleObservation memory newest = _observations[index];
        OracleObservation memory beforeOrAt = _findBefore(block.timestamp - secondsAgo);
        if (beforeOrAt.timestamp == 0 || newest.timestamp <= beforeOrAt.timestamp) {
            revert LumenOracleNotReady();
        }
        uint256 elapsed = newest.timestamp - beforeOrAt.timestamp;
        price0Average = (newest.price0Cumulative - beforeOrAt.price0Cumulative) / elapsed;
        price1Average = (newest.price1Cumulative - beforeOrAt.price1Cumulative) / elapsed;
    }

    function _findBefore(
        uint256 target
    ) internal view returns (OracleObservation memory best) {
        for (uint256 i; i < count; ++i) {
            OracleObservation memory candidate = _observations[i];
            if (candidate.timestamp <= target && candidate.timestamp >= best.timestamp) {
                best = candidate;
            }
        }
    }

    function _toUint224(
        uint256 value
    ) internal pure returns (uint224 result) {
        if (value > type(uint224).max) revert LumenInvalidObservation();
        // forge-lint: disable-next-line(unsafe-typecast)
        result = uint224(value);
    }

    function _toUint128(
        uint256 value
    ) internal pure returns (uint128 result) {
        if (value > type(uint128).max) revert LumenInvalidObservation();
        // forge-lint: disable-next-line(unsafe-typecast)
        result = uint128(value);
    }
}
