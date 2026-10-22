// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { StableSwapMath } from "../../src/libraries/StableSwapMath.sol";
import { ImbalanceQuote, LiquidityQuote, PoolBalances } from "../../src/types/LumenTypes.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";

contract LumenLiquidityTest is PoolTestBase {
    function test_InitialLiquidityMintsLockedSupplyAndTracksInvariant() public {
        uint256 shares = _initializePool();
        PoolBalances memory balances = pool.getBalances();

        assertEq(balances.gross0, INITIAL_LIQUIDITY);
        assertEq(balances.gross1, INITIAL_LIQUIDITY);
        assertEq(balances.virtual0, INITIAL_LIQUIDITY);
        assertEq(balances.virtual1, INITIAL_LIQUIDITY);
        assertEq(pool.totalSupply(), shares + pool.MINIMUM_LIQUIDITY());
        assertEq(pool.lockedLiquidity(), pool.MINIMUM_LIQUIDITY());
        assertGt(pool.cachedInvariant(), 0);
        _assertAccountingReconciles();
    }

    function test_SecondDepositUsesCurrentInvariantDelta() public {
        _initializePool();
        LiquidityQuote memory quote = pool.quoteAddLiquidity(500_000 ether, 500_000 ether);

        uint256 shares = _addLiquidity(BOB, 500_000 ether, 500_000 ether);

        assertEq(shares, quote.shares);
        assertEq(pool.balanceOf(BOB), shares);
        assertEq(pool.cachedInvariant(), quote.invariantAfter);
        _assertAccountingReconciles();
    }

    function test_ProportionalRemoveLiquidityReturnsBothStablecoins() public {
        uint256 minted = _initializePool();
        uint256 shares = minted / 5;
        (uint256 expected0, uint256 expected1) = pool.quoteRemoveLiquidity(shares);
        uint256 before0 = token0.balanceOf(ALICE);
        uint256 before1 = token1.balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 amount0, uint256 amount1) =
            pool.removeLiquidity(shares, expected0, expected1, ALICE, DEADLINE);

        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(token0.balanceOf(ALICE) - before0, amount0);
        assertEq(token1.balanceOf(ALICE) - before1, amount1);
        assertEq(pool.balanceOf(ALICE), minted - shares);
        _assertAccountingReconciles();
    }

    function test_OneTokenWithdrawalUsesInvariantCurve() public {
        uint256 minted = _initializePool();
        uint256 shares = minted / 20;
        uint256 quoted = pool.quoteRemoveLiquidityOneToken(address(token1), shares);
        uint256 before = token1.balanceOf(ALICE);

        vm.prank(ALICE);
        uint256 amountOut =
            pool.removeLiquidityOneToken(address(token1), shares, quoted, ALICE, DEADLINE);

        assertEq(amountOut, quoted);
        assertEq(token1.balanceOf(ALICE) - before, amountOut);
        _assertAccountingReconciles();
    }

    function test_ImbalancedWithdrawalPreviewMatchesSettlementPath() public {
        _initializePool();
        _addLiquidity(BOB, 200_000 ether, 200_000 ether);
        ImbalanceQuote memory quote = pool.quoteRemoveLiquidityImbalanced(0, 50_000 ether);
        uint256 before = token1.balanceOf(BOB);

        vm.prank(BOB);
        uint256 burned =
            pool.removeLiquidityImbalanced(0, 50_000 ether, quote.sharesToBurn, BOB, DEADLINE);

        assertEq(burned, quote.sharesToBurn);
        assertEq(token1.balanceOf(BOB) - before, 50_000 ether);
        assertEq(pool.cachedInvariant(), quote.actualInvariantAfter);
        _assertAccountingReconciles();
    }

    function test_ImbalancedQuoteIncludesInvariantChangeAndFee() public {
        _initializePool();
        ImbalanceQuote memory quote = pool.quoteRemoveLiquidityImbalanced(0, 50_000 ether);
        uint256 baseShares = StableSwapMath.quoteSharesForWithdrawal(
            pool.totalSupply(), quote.invariantBefore, quote.actualInvariantAfter
        );
        assertGt(baseShares, 0);
        assertEq(quote.sharesToBurn, baseShares + quote.imbalanceFeeShares);
    }
}
