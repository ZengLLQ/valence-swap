// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVolatilityHook} from "./interfaces/IVolatilityHook.sol";
import {TransientLock} from "./libraries/TransientLock.sol";

/// @title ValencePool
/// @notice Concentrated AMM liquidity pool integrated with ValenceHook and EIP-1153 transient accounting.
contract ValencePool {
    using TransientLock for *;

    address public immutable token0;
    address public immutable token1;
    IVolatilityHook public immutable hook;

    uint256 public reserve0;
    uint256 public reserve1;
    int24 public currentTick;

    IVolatilityHook.PoolKey public poolKey;

    event SwapExecuted(
        address indexed sender,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        uint24 feeApplied,
        int24 newTick
    );
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1);

    error InsufficientLiquidity();
    error InsufficientInput();
    error ZeroOutput();

    constructor(address _token0, address _token1, address _hook) {
        token0 = _token0;
        token1 = _token1;
        hook = IVolatilityHook(_hook);

        poolKey = IVolatilityHook.PoolKey({
            currency0: _token0,
            currency1: _token1,
            fee: 0, // dynamic fee
            tickSpacing: 60,
            hooks: _hook
        });

        currentTick = 0;
    }

    /// @notice Returns the unique identifier for this pool
    function getPoolId() public view returns (bytes32) {
        return keccak256(abi.encode(poolKey));
    }

    /// @notice Seeds pool with initial reserves
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        if (amount0 == 0 || amount1 == 0) revert InsufficientInput();

        reserve0 += amount0;
        reserve1 += amount1;

        emit LiquidityAdded(msg.sender, amount0, amount1);
    }

    /// @notice Executes swap with dynamic volatility-adjusted fee from ValenceHook
    /// @param zeroForOne If true, swaps token0 for token1; otherwise swaps token1 for token0
    /// @param amountIn Exact input amount
    /// @return amountOut Output token amount received
    function swap(bool zeroForOne, uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInput();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        IVolatilityHook.SwapParams memory params = IVolatilityHook.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: 0
        });

        // 1. Invoke beforeSwap hook -> get dynamic volatility fee
        (, , uint24 dynamicFee) = hook.beforeSwap(msg.sender, poolKey, params, "");

        // 2. Deduct dynamic fee (fee in hundredths of bps: 100% = 1,000,000)
        uint256 feeDeduction = (amountIn * uint256(dynamicFee)) / 1_000_000;
        uint256 netAmountIn = amountIn - feeDeduction;

        // 3. Constant product swap logic (x * y = k)
        int24 tickDisplacement;
        if (zeroForOne) {
            // token0 in -> token1 out
            amountOut = (reserve1 * netAmountIn) / (reserve0 + netAmountIn);
            if (amountOut == 0) revert ZeroOutput();

            reserve0 += amountIn;
            reserve1 -= amountOut;

            // Tick moves down
            tickDisplacement = -int24(int256((netAmountIn * 100) / reserve0 + 1));
        } else {
            // token1 in -> token0 out
            amountOut = (reserve0 * netAmountIn) / (reserve1 + netAmountIn);
            if (amountOut == 0) revert ZeroOutput();

            reserve1 += amountIn;
            reserve0 -= amountOut;

            // Tick moves up
            tickDisplacement = int24(int256((netAmountIn * 100) / reserve1 + 1));
        }

        currentTick += tickDisplacement;

        // 4. Invoke afterSwap hook with updated tick
        bytes memory hookData = abi.encode(currentTick);
        IVolatilityHook.BalanceDelta memory delta = IVolatilityHook.BalanceDelta({
            amount0: zeroForOne ? int128(int256(amountIn)) : -int128(int256(amountOut)),
            amount1: zeroForOne ? -int128(int256(amountOut)) : int128(int256(amountIn))
        });

        hook.afterSwap(msg.sender, poolKey, params, delta, hookData);

        emit SwapExecuted(msg.sender, zeroForOne, amountIn, amountOut, dynamicFee, currentTick);
    }
}
