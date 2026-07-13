// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PoolBalances, SwapQuote } from "../../src/types/LumenTypes.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";

contract LumenSwapFeesTest is PoolTestBase {
    function test_SwapExactInputMatchesQuoteAndMovesBalances() public {
        _initializePool();
        SwapQuote memory quote = pool.quoteExactInput(address(token0), 100_000 ether);
        uint256 beforeOut = token1.balanceOf(TRADER);
        uint256 invariantBefore = pool.cachedInvariant();

        uint256 amountOut = _swap(TRADER, token0, 100_000 ether);

        assertEq(amountOut, quote.amountOut);
        assertEq(token1.balanceOf(TRADER) - beforeOut, quote.amountOut);
        assertGe(pool.cachedInvariant(), invariantBefore);
        _assertAccountingReconciles();
    }

    function test_SwapAccumulatesLPAndProtocolFeesOnInputToken() public {
        _initializePool();
        SwapQuote memory quote = pool.quoteExactInput(address(token0), 250_000 ether);

        _swap(TRADER, token0, 250_000 ether);

        PoolBalances memory balances = pool.getBalances();
        assertEq(balances.pendingLPFee0, quote.lpFee);
        assertEq(balances.protocolFee0, quote.protocolFee);
        assertEq(balances.pendingLPFee1, 0);
        assertEq(balances.protocolFee1, 0);
        _assertAccountingReconciles();
    }

    function test_LiquidityProviderCanClaimAccruedFees() public {
        _initializePool();
        _swap(TRADER, token0, 300_000 ether);
        (uint256 accrued0, uint256 accrued1) = pool.accruedFees(ALICE);
        uint256 before = token0.balanceOf(BOB);

        vm.prank(ALICE);
        (uint256 claimed0, uint256 claimed1) = pool.claimFees(BOB);

        assertEq(claimed0, accrued0);
        assertEq(claimed1, accrued1);
        assertEq(token0.balanceOf(BOB) - before, claimed0);
        assertGt(claimed0, 0);
        _assertAccountingReconciles();
    }

    function test_ProtocolFeesAreCollectedByFeeRecipient() public {
        _initializePool();
        _swap(TRADER, token1, 300_000 ether);
        PoolBalances memory beforeBalances = pool.getBalances();
        uint256 before = token1.balanceOf(FEE_RECIPIENT);

        vm.prank(FEE_RECIPIENT);
        (uint256 amount0, uint256 amount1) = pool.collectProtocolFees();

        assertEq(amount0, 0);
        assertEq(amount1, beforeBalances.protocolFee1);
        assertEq(token1.balanceOf(FEE_RECIPIENT) - before, amount1);
        _assertAccountingReconciles();
    }
}
