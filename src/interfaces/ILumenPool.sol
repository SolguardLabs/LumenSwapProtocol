// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ImbalanceQuote, LiquidityQuote, PoolBalances, SwapQuote } from "../types/LumenTypes.sol";

interface ILumenPool {
    event LiquidityAdded(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        uint256 invariant
    );
    event LiquidityRemoved(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        uint256 invariant
    );
    event ImbalanceWithdrawal(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 sharesBurned,
        uint256 invariantBefore,
        uint256 actualInvariant
    );
    event Swap(
        address indexed sender,
        address indexed recipient,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 lpFee,
        uint256 protocolFee,
        uint256 invariant
    );
    event LPFeesClaimed(
        address indexed owner, address indexed recipient, uint256 amount0, uint256 amount1
    );
    event ProtocolFeesCollected(address indexed recipient, uint256 amount0, uint256 amount1);
    event FeeManagerUpdated(address indexed feeManager);
    event BalanceGuardUpdated(address indexed guard);
    event FeeRecipientUpdated(address indexed recipient);
    event AmplificationRampScheduled(uint256 start, uint256 target, uint64 endTime);
    event AmplificationRampStopped(uint256 value);

    function token0() external view returns (address);
    function token1() external view returns (address);
    function amplification() external view returns (uint256);
    function amplificationRamp()
        external
        view
        returns (uint256 start, uint256 target, uint64 startTime, uint64 endTime);
    function rampAmplification(
        uint256 target,
        uint64 endTime
    ) external;
    function stopAmplificationRamp() external;
    function cachedInvariant() external view returns (uint256);
    function feeRecipient() external view returns (address);
    function feeManager() external view returns (address);
    function balanceGuard() external view returns (address);
    function oracle() external view returns (address);
    function getBalances() external view returns (PoolBalances memory balances);
    function virtualBalances() external view returns (uint256 balance0, uint256 balance1);
    function grossBalances() external view returns (uint256 balance0, uint256 balance1);
    function feeGrowthGlobalX128() external view returns (uint256 growth0, uint256 growth1);
    function accruedFees(
        address owner
    ) external view returns (uint256 amount0, uint256 amount1);

    function quoteAddLiquidity(
        uint256 amount0,
        uint256 amount1
    ) external view returns (LiquidityQuote memory quote);
    function quoteRemoveLiquidity(
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1);
    function quoteRemoveLiquidityOneToken(
        address tokenOut,
        uint256 shares
    ) external view returns (uint256 amountOut);
    function quoteRemoveLiquidityImbalanced(
        uint256 amount0,
        uint256 amount1
    ) external view returns (ImbalanceQuote memory quote);
    function quoteExactInput(
        address tokenIn,
        uint256 amountIn
    ) external view returns (SwapQuote memory quote);

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 shares);
    function removeLiquidity(
        uint256 shares,
        uint256 minAmount0,
        uint256 minAmount1,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);
    function removeLiquidityOneToken(
        address tokenOut,
        uint256 shares,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);
    function removeLiquidityImbalanced(
        uint256 amount0,
        uint256 amount1,
        uint256 maxShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 sharesBurned);
    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);
    function claimFees(
        address recipient
    ) external returns (uint256 amount0, uint256 amount1);
    function collectProtocolFees() external returns (uint256 amount0, uint256 amount1);
}
