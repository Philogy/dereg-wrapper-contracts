// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {DeRegDEX} from "./DeRegDEX.sol";

/// @author philogy <https://github.com/philogy>
contract VulnerableDeRegDEX is DeRegDEX {
    function vulnerableFillOrder(uint256 _orderId) external initializer {
        Order memory order = getOrder[_orderId];
        if (order.tokenBeingSold == address(0)) revert NonexistentOrder();
        transferERC20(order.tokenBeingSold, msg.sender, order.amountBeingSold);
    }
}
