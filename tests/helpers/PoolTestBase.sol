// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenPool } from "../../src/core/LumenPool.sol";
import { LumenFeeManager } from "../../src/fees/LumenFeeManager.sol";
import { LumenBalanceGuard } from "../../src/risk/LumenBalanceGuard.sol";
import { FeeConfig, PoolBalances, PoolConfig } from "../../src/types/LumenTypes.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { TestBase } from "./TestBase.sol";

abstract contract PoolTestBase is TestBase {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TRADER = address(0xA7A);
    address internal constant OPERATIONS = address(0x0A11);
    address internal constant FEE_RECIPIENT = address(0xFEE1);

    uint256 internal constant AMP = 200 * 100;
    uint256 internal constant INITIAL_LIQUIDITY = 10_000_000 ether;
    uint256 internal constant USER_FLOAT = 20_000_000 ether;
    uint256 internal constant DEADLINE = type(uint256).max;

    MockERC20 internal token0;
    MockERC20 internal token1;
    LumenFeeManager internal feeManager;
    LumenBalanceGuard internal guard;
    LumenPool internal pool;

    function setUp() public virtual {
        token0 = new MockERC20("Mock USD A", "mUSDA", 18);
        token1 = new MockERC20("Mock USD B", "mUSDB", 18);

        feeManager = new LumenFeeManager(
            address(this),
            FeeConfig({
                baseSwapFeePpm: 400,
                adminFeePpm: 500_000,
                imbalanceFeePpm: 500,
                sizeFeePpm: 0,
                maxFeePpm: 5000
            })
        );
        guard = new LumenBalanceGuard(address(this), 1 ether, 1_000_000, 9500);
        pool = new LumenPool(
            PoolConfig({
                token0: address(token0),
                token1: address(token1),
                owner: address(this),
                feeRecipient: FEE_RECIPIENT,
                feeManager: address(feeManager),
                balanceGuard: address(guard),
                oracle: address(0),
                amplification: AMP
            })
        );

        _labelAccounts();
        _mintAndApprove(ALICE);
        _mintAndApprove(BOB);
        _mintAndApprove(TRADER);
        _mintAndApprove(OPERATIONS);
    }

    function _initializePool() internal returns (uint256 shares) {
        vm.prank(ALICE);
        shares = pool.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0, ALICE, DEADLINE);
    }

    function _addLiquidity(
        address user,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 shares) {
        vm.prank(user);
        shares = pool.addLiquidity(amount0, amount1, 0, user, DEADLINE);
    }

    function _swap(
        address user,
        MockERC20 tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        vm.prank(user);
        amountOut = pool.swapExactInput(address(tokenIn), amountIn, 0, user, DEADLINE);
    }

    function _assertAccountingReconciles() internal view {
        PoolBalances memory balances = pool.getBalances();
        assertEq(token0.balanceOf(address(pool)), balances.gross0);
        assertEq(token1.balanceOf(address(pool)), balances.gross1);
        assertEq(
            balances.gross0, balances.virtual0 + balances.pendingLPFee0 + balances.protocolFee0
        );
        assertEq(
            balances.gross1, balances.virtual1 + balances.pendingLPFee1 + balances.protocolFee1
        );
    }

    function _mintAndApprove(
        address user
    ) internal {
        token0.mint(user, USER_FLOAT);
        token1.mint(user, USER_FLOAT);
        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _labelAccounts() internal {
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
        vm.label(TRADER, "TRADER");
        vm.label(OPERATIONS, "OPERATIONS");
        vm.label(FEE_RECIPIENT, "FEE_RECIPIENT");
        vm.label(address(pool), "LumenPool");
        vm.label(address(token0), "Token0");
        vm.label(address(token1), "Token1");
    }
}
