// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenUnauthorized, LumenZeroAddress } from "../types/LumenErrors.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

struct BreakerConfig {
    bool enabled;
    uint256 windowSeconds;
    uint256 maxToken0Out;
    uint256 maxToken1Out;
    uint256 maxSwapCount;
}

struct BreakerState {
    uint256 windowStartedAt;
    uint256 token0Out;
    uint256 token1Out;
    uint256 swapCount;
}

contract LumenCircuitBreaker is Ownable2Step {
    mapping(address pool => BreakerConfig config) public configs;
    mapping(address pool => BreakerState state) public states;
    mapping(address keeper => bool allowed) public keepers;

    event KeeperUpdated(address indexed keeper, bool allowed);
    event BreakerConfigured(
        address indexed pool,
        bool enabled,
        uint256 windowSeconds,
        uint256 maxToken0Out,
        uint256 maxToken1Out,
        uint256 maxSwapCount
    );
    event FlowRecorded(
        address indexed pool, uint256 token0Out, uint256 token1Out, uint256 swapCount
    );
    event WindowReset(address indexed pool, uint256 timestamp);

    constructor(
        address owner_
    ) Ownable2Step(owner_) { }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && !keepers[msg.sender]) revert LumenUnauthorized();
        _;
    }

    function setKeeper(
        address keeper,
        bool allowed
    ) external onlyOwner {
        if (keeper == address(0)) revert LumenZeroAddress();
        keepers[keeper] = allowed;
        emit KeeperUpdated(keeper, allowed);
    }

    function configurePool(
        address pool,
        BreakerConfig calldata config
    ) external onlyOwner {
        if (pool == address(0)) revert LumenZeroAddress();
        configs[pool] = config;
        if (states[pool].windowStartedAt == 0) {
            states[pool].windowStartedAt = block.timestamp;
        }
        emit BreakerConfigured(
            pool,
            config.enabled,
            config.windowSeconds,
            config.maxToken0Out,
            config.maxToken1Out,
            config.maxSwapCount
        );
    }

    function recordWithdrawal(
        address pool,
        uint256 token0Out,
        uint256 token1Out
    ) external onlyKeeperOrOwner returns (bool allowed) {
        _rollWindowIfNeeded(pool);
        BreakerConfig memory config = configs[pool];
        BreakerState storage state = states[pool];
        if (!config.enabled) return true;

        allowed = state.token0Out + token0Out <= config.maxToken0Out
            && state.token1Out + token1Out <= config.maxToken1Out;
        if (allowed) {
            state.token0Out += token0Out;
            state.token1Out += token1Out;
            emit FlowRecorded(pool, state.token0Out, state.token1Out, state.swapCount);
        }
    }

    function recordSwap(
        address pool,
        uint256 token0Out,
        uint256 token1Out
    ) external onlyKeeperOrOwner returns (bool allowed) {
        _rollWindowIfNeeded(pool);
        BreakerConfig memory config = configs[pool];
        BreakerState storage state = states[pool];
        if (!config.enabled) return true;

        allowed = state.token0Out + token0Out <= config.maxToken0Out
            && state.token1Out + token1Out <= config.maxToken1Out
            && state.swapCount + 1 <= config.maxSwapCount;
        if (allowed) {
            state.token0Out += token0Out;
            state.token1Out += token1Out;
            state.swapCount += 1;
            emit FlowRecorded(pool, state.token0Out, state.token1Out, state.swapCount);
        }
    }

    function remainingCapacity(
        address pool
    )
        external
        view
        returns (uint256 token0Remaining, uint256 token1Remaining, uint256 swapsRemaining)
    {
        BreakerConfig memory config = configs[pool];
        BreakerState memory state = _previewState(pool);
        if (!config.enabled) {
            return (type(uint256).max, type(uint256).max, type(uint256).max);
        }
        token0Remaining =
            state.token0Out >= config.maxToken0Out ? 0 : config.maxToken0Out - state.token0Out;
        token1Remaining =
            state.token1Out >= config.maxToken1Out ? 0 : config.maxToken1Out - state.token1Out;
        swapsRemaining =
            state.swapCount >= config.maxSwapCount ? 0 : config.maxSwapCount - state.swapCount;
    }

    function resetWindow(
        address pool
    ) external onlyKeeperOrOwner {
        states[pool] = BreakerState({
            windowStartedAt: block.timestamp, token0Out: 0, token1Out: 0, swapCount: 0
        });
        emit WindowReset(pool, block.timestamp);
    }

    function _rollWindowIfNeeded(
        address pool
    ) internal {
        BreakerConfig memory config = configs[pool];
        BreakerState storage state = states[pool];
        if (state.windowStartedAt == 0) {
            state.windowStartedAt = block.timestamp;
            return;
        }
        // forge-lint: disable-next-line(block-timestamp)
        bool expired = block.timestamp >= state.windowStartedAt + config.windowSeconds;
        if (config.windowSeconds != 0 && expired) {
            state.windowStartedAt = block.timestamp;
            state.token0Out = 0;
            state.token1Out = 0;
            state.swapCount = 0;
            emit WindowReset(pool, block.timestamp);
        }
    }

    function _previewState(
        address pool
    ) internal view returns (BreakerState memory state) {
        BreakerConfig memory config = configs[pool];
        state = states[pool];
        // forge-lint: disable-next-line(block-timestamp)
        bool expired = block.timestamp >= state.windowStartedAt + config.windowSeconds;
        if (config.windowSeconds != 0 && state.windowStartedAt != 0 && expired) {
            state.token0Out = 0;
            state.token1Out = 0;
            state.swapCount = 0;
            state.windowStartedAt = block.timestamp;
        }
    }
}
