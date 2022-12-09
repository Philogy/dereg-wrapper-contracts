// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract DeRegDEX {
    error NonexistentOrder();
    error OrderExpired();
    error InsufficientAmount();
    error ZeroAddress();

    struct Order {
        address tokenBeingSold;
        uint256 amountBeingSold;
        address tokenBeingBought;
        uint256 minBuyAmount;
        address recipient;
        uint256 expiresAt;
    }

    mapping(uint256 => Order) public getOrder;
    uint256 public nextOrderId;

    // initializer not necessary since `assetLayer` already set
    // function initialize() external virtual reinitializer(2) {}

    function createOrder(
        address _tokenToSell,
        uint256 _depositAmount,
        address _tokenToBuy,
        uint256 _minReceiveAmount,
        uint256 _orderExpiry
    ) external {
        if (_tokenToSell == address(0)) revert ZeroAddress();
        SafeTransferLib.safeTransferFrom(_tokenToSell, msg.sender, address(this), _depositAmount);
        getOrder[nextOrderId++] = Order({
            tokenBeingSold: _tokenToSell,
            amountBeingSold: _depositAmount,
            tokenBeingBought: _tokenToBuy,
            minBuyAmount: _minReceiveAmount,
            recipient: msg.sender,
            expiresAt: _orderExpiry
        });
    }

    function fillOrder(uint256 _orderId, uint256 _amount) external {
        Order memory order = getOrder[_orderId];
        if (order.tokenBeingSold == address(0)) revert NonexistentOrder();
        if (order.expiresAt <= block.timestamp) revert OrderExpired();
        delete getOrder[_orderId];
        SafeTransferLib.safeTransferFrom(order.tokenBeingBought, msg.sender, order.recipient, _amount);
        if (_amount < order.minBuyAmount) revert InsufficientAmount();
        SafeTransferLib.safeTransfer(order.tokenBeingSold, msg.sender, order.amountBeingSold);
    }
}
