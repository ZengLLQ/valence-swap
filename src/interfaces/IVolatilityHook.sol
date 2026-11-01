// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Permissions and interfaces for Uniswap v4 dynamic fee volatility hooks.
interface IVolatilityHook {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct BalanceDelta {
        int128 amount0;
        int128 amount1;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns current realized volatility for a given pool
    function getPoolVolatility(bytes32 poolId) external view returns (uint256);

    /// @notice Returns current dynamic fee in basis points (1 bp = 0.01% = 100 in hundredths of bps)
    function getDynamicFee(bytes32 poolId) external view returns (uint24);

    /// @notice Hook called before swap execution to set dynamic fee and record tick displacement
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, int128, uint24);

    /// @notice Hook called after swap execution to update realized volatility EMA
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta calldata delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);
}
