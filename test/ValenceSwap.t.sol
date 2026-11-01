// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ValenceHook} from "../src/ValenceHook.sol";
import {ValencePool} from "../src/ValencePool.sol";

contract ValenceSwapTest is Test {
    ValenceHook hook;
    ValencePool pool;

    address token0 = address(0x1111);
    address token1 = address(0x2222);

    function setUp() public {
        hook = new ValenceHook();
        pool = new ValencePool(token0, token1, address(hook));

        // Seed pool with 1,000,000 token0 and 1,000,000 token1
        pool.addLiquidity(1_000_000 ether, 1_000_000 ether);
    }

    function test_initial_swap_uses_base_fee() public {
        bytes32 poolId = pool.getPoolId();
        assertEq(hook.getDynamicFee(poolId), 500); // 5 bps

        uint256 amountOut = pool.swap(true, 100 ether);
        assertGt(amountOut, 0);

        // After small swap, fee remains near base fee
        assertEq(hook.getDynamicFee(poolId), 500);
    }

    function test_high_volatility_scales_fee_upwards() public {
        bytes32 poolId = pool.getPoolId();

        // Perform multiple large alternating swaps causing large tick swings
        for (uint256 i = 0; i < 5; i++) {
            pool.swap(true, 50_000 ether);
            pool.swap(false, 50_000 ether);
        }

        uint256 vol = hook.getPoolVolatility(poolId);
        assertGt(vol, 0);

        uint24 dynamicFee = hook.getDynamicFee(poolId);
        assertGt(dynamicFee, 500); // Elevated above 5 bps base fee
        assertLe(dynamicFee, 10000); // Within 100 bps max cap
    }

    function test_fuzz_swap_positive_output(uint256 amountIn) public {
        vm.assume(amountIn >= 1 ether && amountIn <= 10_000 ether);

        uint256 out0 = pool.swap(true, amountIn);
        assertGt(out0, 0);

        uint256 out1 = pool.swap(false, amountIn);
        assertGt(out1, 0);
    }
}
