// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransientLock} from "../src/libraries/TransientLock.sol";

contract ReentrantAttacker {
    using TransientLock for *;

    function enterOnce() external {
        TransientLock.acquireLock();
    }

    function reenter() external {
        TransientLock.acquireLock();
        // Malicious second call within same transaction
        TransientLock.acquireLock();
    }

    function exit() external {
        TransientLock.releaseLock();
    }
}

contract TransientLockTest is Test {
    ReentrantAttacker attacker;

    function setUp() public {
        attacker = new ReentrantAttacker();
    }

    function test_acquire_and_release_lock() public {
        attacker.enterOnce();
        attacker.exit();
        // Should succeed again after release
        attacker.enterOnce();
        attacker.exit();
    }

    function test_revert_on_reentrant_call() public {
        vm.expectRevert(TransientLock.ReentrancyGuardReentrantCall.selector);
        attacker.reenter();
    }

    function test_transient_delta_tracking() public {
        address user = address(0xCAFE);
        address token = address(0xBEEF);

        TransientLock.setTransientDelta(user, token, 1500 ether);
        assertEq(TransientLock.getTransientDelta(user, token), 1500 ether);

        TransientLock.clearTransientDelta(user, token);
        assertEq(TransientLock.getTransientDelta(user, token), 0);
    }
}
