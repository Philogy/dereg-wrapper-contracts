// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {ICircuitBreaker} from "./ICircuitBreaker.sol";
import {CrispyERC1155} from "./CrispyERC1155.sol";
import {LogicProxy} from "./utils/LogicProxy.sol";
import {Ownable2Step} from "@openzeppelin/access/Ownable2Step.sol";

/// @author philogy <https://github.com/philogy>
/// @notice Optimized for minimal storage access
contract CircuitBreaker is ICircuitBreaker, CrispyERC1155, Ownable2Step {
    error NotAuthorizedTrigger();
    error NotLogic();

    address payable public immutable logic;
    address public immutable factory;

    // Mutable Queue Variables (1 slot)
    uint128 internal nextWithdrawalId;
    GCBState internal cbState;
    uint64 internal defaultDelay;
    bytes7 internal ___queueVarGap;

    // Mutable Settlement Variables (1 slot)
    uint64 internal globalDelayStart;
    uint64 internal globalDelay;
    uint64 internal lastFreezeStart;
    ReentrancyLock internal reentrancyLockState;
    TriggerAuth internal triggerAuth;
    uint48 internal nextFreezeId;

    // Trigger if `triggerAuth` configured to `TriggerAuth.OTHER`
    address internal trigger;

    modifier onlyTrigger() {
        _checkTrigger(triggerAuth);
        _;
    }

    modifier onlyLogic() {
        if (logic != msg.sender) revert NotLogic();
        _;
    }

    /// @dev No receive restrictions to save gas
    receive() external payable {}

    constructor(address _startImplementation) {
        factory = msg.sender;
        logic = payable(new LogicProxy(_startImplementation));
        reentrancyLockState = ReentrancyLock.UNLOCKED;
    }

    function state() external returns (GCBState) {
        return cbState;
    }

    function _checkTrigger(TriggerAuth _triggerAuth) internal {
        if (_triggerAuth == TriggerAuth.Factory) {
            if (msg.sender == factory) return;
        } else if (_triggerAuth == TriggerAuth.Other) {
            if (msg.sender == trigger) return;
        }
        // Auth failed or auth type `OnlyOwner`, check
        if (msg.sender == owner()) return;
        revert NotAuthorizedTrigger();
    }
}
