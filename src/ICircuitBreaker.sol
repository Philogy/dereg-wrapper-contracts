// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IERC1155} from "@openzeppelin/token/ERC1155/IERC1155.sol";

interface ICircuitBreaker is IERC1155 {
    enum GCBState {
        Running, // Circuit breaker is active and processing withdrawals
        Blocked, // Settlement of pending and new withdrawals blocked
        Frozen //
    }

    enum ReentrancyLock {
        Uninitialized,
        Unlocked,
        Locked
    }

    enum TriggerAuth {
        Factory,
        OnlyOwner,
        Other
    }
}
