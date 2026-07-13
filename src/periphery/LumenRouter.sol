// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { ILumenPool } from "../interfaces/ILumenPool.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import {
    LumenInvalidToken,
    LumenOutputBelowMinimum,
    LumenZeroAddress
} from "../types/LumenErrors.sol";
import { RouteStep, SwapQuote } from "../types/LumenTypes.sol";

contract LumenRouter {
    using SafeTransferLib for address;

    event RoutedAddLiquidity(
        address indexed pool, address indexed payer, address indexed recipient, uint256 shares
    );
    event RoutedRemoveLiquidity(
        address indexed pool, address indexed owner, address indexed recipient, uint256 shares
    );
    event RoutedSwap(
        address indexed pool,
        address indexed tokenIn,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );

    function addLiquidity(
        address pool,
        uint256 amount0,
        uint256 amount1,
        uint256 minShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 shares) {
        if (pool == address(0) || recipient == address(0)) revert LumenZeroAddress();
        address token0 = ILumenPool(pool).token0();
        address token1 = ILumenPool(pool).token1();
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        token0.safeApprove(pool, amount0);
        token1.safeApprove(pool, amount1);
        shares = ILumenPool(pool).addLiquidity(amount0, amount1, minShares, recipient, deadline);
        emit RoutedAddLiquidity(pool, msg.sender, recipient, shares);
    }

    function removeLiquidity(
        address pool,
        uint256 shares,
        uint256 minAmount0,
        uint256 minAmount1,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1) {
        if (pool == address(0) || recipient == address(0)) revert LumenZeroAddress();
        pool.safeTransferFrom(msg.sender, address(this), shares);
        (amount0, amount1) =
            ILumenPool(pool).removeLiquidity(shares, minAmount0, minAmount1, recipient, deadline);
        emit RoutedRemoveLiquidity(pool, msg.sender, recipient, shares);
    }

    function removeLiquidityImbalanced(
        address pool,
        uint256 amount0,
        uint256 amount1,
        uint256 maxShares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 sharesBurned) {
        if (pool == address(0) || recipient == address(0)) revert LumenZeroAddress();
        sharesBurned =
        ILumenPool(pool).quoteRemoveLiquidityImbalanced(amount0, amount1).sharesToBurn;
        pool.safeTransferFrom(msg.sender, address(this), sharesBurned);
        sharesBurned = ILumenPool(pool)
            .removeLiquidityImbalanced(amount0, amount1, maxShares, recipient, deadline);
        emit RoutedRemoveLiquidity(pool, msg.sender, recipient, sharesBurned);
    }

    function swapExactInput(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) public returns (uint256 amountOut) {
        if (pool == address(0) || recipient == address(0)) revert LumenZeroAddress();
        SwapQuote memory quote = ILumenPool(pool).quoteExactInput(tokenIn, amountIn);
        if (quote.tokenIn != tokenIn) revert LumenInvalidToken();
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenIn.safeApprove(pool, amountIn);
        amountOut =
            ILumenPool(pool).swapExactInput(tokenIn, amountIn, minAmountOut, recipient, deadline);
        emit RoutedSwap(pool, tokenIn, recipient, amountIn, amountOut);
    }

    function swapExactInputRoute(
        RouteStep[] calldata route,
        uint256 amountIn,
        uint256 minFinalOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (recipient == address(0)) revert LumenZeroAddress();
        uint256 currentAmount = amountIn;
        address currentHolder = msg.sender;

        for (uint256 i; i < route.length; ++i) {
            RouteStep calldata step = route[i];
            address nextRecipient = i + 1 == route.length ? recipient : address(this);
            if (currentHolder == msg.sender) {
                step.tokenIn.safeTransferFrom(msg.sender, address(this), currentAmount);
                currentHolder = address(this);
            }
            step.tokenIn.safeApprove(step.pool, currentAmount);
            currentAmount = ILumenPool(step.pool)
                .swapExactInput(step.tokenIn, currentAmount, 0, nextRecipient, deadline);
            emit RoutedSwap(step.pool, step.tokenIn, nextRecipient, amountIn, currentAmount);
        }

        amountOut = currentAmount;
        if (amountOut < minFinalOut) revert LumenOutputBelowMinimum();
    }

    function recoverToken(
        address token,
        address recipient,
        uint256 amount
    ) external {
        if (recipient == address(0)) revert LumenZeroAddress();
        token.safeTransfer(recipient, amount);
    }

    function quoteRoute(
        RouteStep[] calldata route,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        amountOut = amountIn;
        for (uint256 i; i < route.length; ++i) {
            amountOut =
            ILumenPool(route[i].pool).quoteExactInput(route[i].tokenIn, amountOut).amountOut;
        }
    }

    function tokenBalance(
        address token,
        address account
    ) external view returns (uint256) {
        return IERC20Minimal(token).balanceOf(account);
    }
}
