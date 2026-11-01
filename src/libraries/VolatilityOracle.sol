// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title VolatilityOracle
/// @notice Computes realized volatility and dynamic fee curves to protect LPs from Loss-Versus-Rebalancing (LVR).
library VolatilityOracle {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant ALPHA_BPS = 200; // 20% smoothing factor (EMA weight)
    uint256 internal constant BPS_DIVISOR = 1000;

    uint24 internal constant MIN_FEE = 500;   // 5 bps (0.05%)
    uint24 internal constant MAX_FEE = 10000; // 100 bps (1.00%)

    /// @notice Updates realized volatility EMA using absolute tick change
    /// @param prevVol Current variance EMA
    /// @param tickDelta Absolute tick movement during swap
    /// @return newVol Updated variance EMA
    function updateVolatilityEMA(uint256 prevVol, uint256 tickDelta) internal pure returns (uint256 newVol) {
        uint256 squaredDelta = tickDelta * tickDelta;
        // EMA: alpha * delta^2 + (1 - alpha) * prevVol
        newVol = (ALPHA_BPS * squaredDelta + (BPS_DIVISOR - ALPHA_BPS) * prevVol) / BPS_DIVISOR;
    }

    /// @notice Calculates dynamic swap fee based on realized volatility
    /// @param variance Current variance EMA
    /// @param gamma Scaling multiplier
    /// @return fee Computed fee in hundredths of bps (e.g. 500 = 5 bps, 10000 = 100 bps)
    function calculateDynamicFee(uint256 variance, uint256 gamma) internal pure returns (uint24 fee) {
        if (variance == 0) {
            return MIN_FEE;
        }

        // Integer square root for standard deviation sigma = sqrt(variance)
        uint256 sigma = sqrt(variance);
        uint256 dynamicAddition = (sigma * gamma) / 100;

        uint256 calculated = uint256(MIN_FEE) + dynamicAddition;
        if (calculated > MAX_FEE) {
            return MAX_FEE;
        }
        return uint24(calculated);
    }

    /// @notice Babylonian integer square root algorithm
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
