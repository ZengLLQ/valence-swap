// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVolatilityHook} from "./interfaces/IVolatilityHook.sol";
import {TransientLock} from "./libraries/TransientLock.sol";
import {VolatilityOracle} from "./libraries/VolatilityOracle.sol";

/// @title ValenceHook
/// @notice Uniswap v4 Dynamic Volatility Fee Hook with EIP-1153 Transient Storage.
contract ValenceHook is IVolatilityHook {
    using TransientLock for *;
    using VolatilityOracle for *;

    address public immutable owner;
    uint256 public volatilityGamma = 50; // Sensitivity factor

    // poolId => realized variance EMA
    mapping(bytes32 => uint256) public poolVolatility;
    // poolId => last observed tick
    mapping(bytes32 => int24) public lastPoolTick;

    event DynamicFeeCalculated(bytes32 indexed poolId, uint24 fee, uint256 volatility);
    event VolatilityUpdated(bytes32 indexed poolId, uint256 oldVol, uint256 newVol, int24 tickDelta);

    error OnlyOwner();
    error InvalidTickDelta();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setVolatilityGamma(uint256 newGamma) external onlyOwner {
        volatilityGamma = newGamma;
    }

    function getPoolVolatility(bytes32 poolId) external view override returns (uint256) {
        return poolVolatility[poolId];
    }

    function getDynamicFee(bytes32 poolId) public view override returns (uint24) {
        return VolatilityOracle.calculateDynamicFee(poolVolatility[poolId], volatilityGamma);
    }

    /// @notice Hook called immediately prior to swap execution
    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) external override returns (bytes4, int128, uint24) {
        // Enforce transient reentrancy guard
        TransientLock.acquireLock();

        bytes32 poolId = keccak256(abi.encode(key));
        uint24 dynamicFee = getDynamicFee(poolId);

        emit DynamicFeeCalculated(poolId, dynamicFee, poolVolatility[poolId]);

        // Uniswap v4 standard: return selector, delta 0, and dynamic fee override
        return (this.beforeSwap.selector, 0, dynamicFee);
    }

    /// @notice Hook called immediately following swap execution
    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta calldata,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        bytes32 poolId = keccak256(abi.encode(key));

        // If hookData contains post-swap tick
        if (hookData.length >= 32) {
            int24 currentTick = abi.decode(hookData, (int24));
            int24 prevTick = lastPoolTick[poolId];
            int24 tickDelta = currentTick >= prevTick ? currentTick - prevTick : prevTick - currentTick;

            uint256 oldVol = poolVolatility[poolId];
            uint256 newVol = VolatilityOracle.updateVolatilityEMA(oldVol, uint256(int256(tickDelta)));

            poolVolatility[poolId] = newVol;
            lastPoolTick[poolId] = currentTick;

            emit VolatilityUpdated(poolId, oldVol, newVol, tickDelta);
        }

        // Release transient reentrancy guard
        TransientLock.releaseLock();

        return (this.afterSwap.selector, 0);
    }
}
