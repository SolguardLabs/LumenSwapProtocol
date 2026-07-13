// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

struct TokenPair {
    address token0;
    address token1;
}

struct PoolConfig {
    address token0;
    address token1;
    address owner;
    address feeRecipient;
    address feeManager;
    address balanceGuard;
    address oracle;
    uint256 amplification;
}

struct FeeConfig {
    uint24 baseSwapFeePpm;
    uint24 adminFeePpm;
    uint24 imbalanceFeePpm;
    uint24 sizeFeePpm;
    uint24 maxFeePpm;
}

struct FeeQuote {
    uint256 totalFee;
    uint256 lpFee;
    uint256 protocolFee;
    uint24 feePpm;
}

struct PoolBalances {
    uint256 gross0;
    uint256 gross1;
    uint256 virtual0;
    uint256 virtual1;
    uint256 pendingLPFee0;
    uint256 pendingLPFee1;
    uint256 protocolFee0;
    uint256 protocolFee1;
}

struct LiquidityQuote {
    uint256 amount0;
    uint256 amount1;
    uint256 shares;
    uint256 invariantBefore;
    uint256 invariantAfter;
}

struct SwapQuote {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOut;
    uint256 lpFee;
    uint256 protocolFee;
    uint24 feePpm;
    uint256 invariantBefore;
    uint256 invariantAfter;
}

struct ImbalanceQuote {
    uint256 amount0;
    uint256 amount1;
    uint256 sharesToBurn;
    uint256 staleInvariant;
    uint256 actualInvariantAfter;
    uint256 imbalanceFeeShares;
}

struct FeeCheckpoint {
    uint256 feeGrowth0X128;
    uint256 feeGrowth1X128;
    uint256 stored0;
    uint256 stored1;
}

struct OracleObservation {
    uint32 timestamp;
    uint224 price0Cumulative;
    uint224 price1Cumulative;
    uint128 virtual0;
    uint128 virtual1;
}

struct RouteStep {
    address pool;
    address tokenIn;
}
