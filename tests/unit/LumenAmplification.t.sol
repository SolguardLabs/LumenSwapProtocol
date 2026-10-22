// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenPool } from "../../src/core/LumenPool.sol";
import { LumenNotOwner } from "../../src/types/LumenErrors.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";

contract LumenAmplificationTest is PoolTestBase {
    function test_RampInterpolatesWithinGovernanceBounds() public {
        uint64 endTime = uint64(block.timestamp + 2 days);
        pool.rampAmplification(1000 * 100, endTime);

        (uint256 start, uint256 target, uint64 startTime, uint64 recordedEnd) =
            pool.amplificationRamp();
        assertEq(start, AMP);
        assertEq(target, 1000 * 100);
        assertEq(startTime, block.timestamp);
        assertEq(recordedEnd, endTime);
        assertEq(pool.amplification(), AMP);

        vm.warp(block.timestamp + 1 days);
        assertEq(pool.amplification(), 600 * 100);
        vm.warp(endTime);
        assertEq(pool.amplification(), 1000 * 100);
    }

    function test_StopRampFreezesCurrentParameter() public {
        pool.rampAmplification(1000 * 100, uint64(block.timestamp + 2 days));
        vm.warp(block.timestamp + 1 days);
        pool.stopAmplificationRamp();
        assertEq(pool.amplification(), 600 * 100);
        vm.warp(block.timestamp + 10 days);
        assertEq(pool.amplification(), 600 * 100);
    }

    function test_RampRejectsShortDurationAndExcessiveChange() public {
        vm.expectRevert(LumenPool.InvalidAmplificationRamp.selector);
        pool.rampAmplification(1000 * 100, uint64(block.timestamp + 1 hours));

        vm.expectRevert(LumenPool.InvalidAmplificationRamp.selector);
        pool.rampAmplification(2001 * 100, uint64(block.timestamp + 1 days));
    }

    function test_OnlyOwnerMayScheduleOrStopRamp() public {
        vm.expectRevert(LumenNotOwner.selector);
        vm.prank(BOB);
        pool.rampAmplification(1000 * 100, uint64(block.timestamp + 2 days));

        vm.expectRevert(LumenNotOwner.selector);
        vm.prank(BOB);
        pool.stopAmplificationRamp();
    }

    function test_ActiveRampCannotBeReplacedBeforeItsEnd() public {
        pool.rampAmplification(1000 * 100, uint64(block.timestamp + 2 days));
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(LumenPool.InvalidAmplificationRamp.selector);
        pool.rampAmplification(2000 * 100, uint64(block.timestamp + 2 days));
    }
}
