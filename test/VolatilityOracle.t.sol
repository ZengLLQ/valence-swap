// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VolatilityOracle} from "../src/libraries/VolatilityOracle.sol";

contract VolatilityOracleTest is Test {
    function test_zero_variance_gives_min_fee() public pure {
        uint24 fee = VolatilityOracle.calculateDynamicFee(0, 50);
        assertEq(fee, 500); // 5 bps
    }

    function test_ema_updates_monotonically() public pure {
        uint256 vol0 = 0;
        uint256 vol1 = VolatilityOracle.updateVolatilityEMA(vol0, 100);
        assertGt(vol1, 0);

        uint256 vol2 = VolatilityOracle.updateVolatilityEMA(vol1, 100);
        assertGt(vol2, vol1);
    }

    function test_fee_caps_at_max_fee() public pure {
        // Enormous variance
        uint256 hugeVariance = 1_000_000_000;
        uint24 fee = VolatilityOracle.calculateDynamicFee(hugeVariance, 500);
        assertEq(fee, 10000); // 100 bps cap
    }

    function test_sqrt_accuracy(uint256 val) public pure {
        vm.assume(val > 0 && val < type(uint128).max);
        uint256 s = VolatilityOracle.sqrt(val);
        // s^2 <= val < (s+1)^2
        assertLe(s * s, val);
        assertGt((s + 1) * (s + 1), val);
    }
}
