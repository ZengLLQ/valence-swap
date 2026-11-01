// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title TransientLock
/// @notice Gas-efficient reentrancy guard and transient session balance tracker powered by EIP-1153 (tstore/tload).
library TransientLock {
    // keccak256("valence.transient.reentrancy.lock")
    bytes32 internal constant REENTRANCY_SLOT = 0x8a92e106dc9572b847fa2c40c345a55b3f2c5e5c0245a1f6a15291cb05f1df6a;

    error ReentrancyGuardReentrantCall();

    /// @notice Acquires transient lock for current transaction
    function acquireLock() internal {
        assembly {
            if tload(REENTRANCY_SLOT) {
                // Revert with ReentrancyGuardReentrantCall()
                mstore(0x00, 0x3ee5aeb5)
                revert(0x1c, 0x04)
            }
            tstore(REENTRANCY_SLOT, 1)
        }
    }

    /// @notice Releases transient lock
    function releaseLock() internal {
        assembly {
            tstore(REENTRANCY_SLOT, 0)
        }
    }

    /// @notice Sets transient delta balance for an account and token
    function setTransientDelta(address account, address token, int256 delta) internal {
        bytes32 slot = keccak256(abi.encodePacked("valence.transient.delta", account, token));
        assembly {
            tstore(slot, delta)
        }
    }

    /// @notice Retrieves transient delta balance
    function getTransientDelta(address account, address token) internal view returns (int256 delta) {
        bytes32 slot = keccak256(abi.encodePacked("valence.transient.delta", account, token));
        assembly {
            delta := tload(slot)
        }
    }

    /// @notice Clears transient delta balance
    function clearTransientDelta(address account, address token) internal {
        bytes32 slot = keccak256(abi.encodePacked("valence.transient.delta", account, token));
        assembly {
            tstore(slot, 0)
        }
    }
}
