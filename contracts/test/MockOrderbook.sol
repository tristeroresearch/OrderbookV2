// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOptimistic.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MockOrderbook is TradeInterface {
    event FillSwapCalled(address caller, bytes data);
    event ExecuteMatchCalled(address caller, bytes data);

    // Amount to take from the MMRouter (simulating actual orderbook behavior)
    uint256 constant TAKE_AMOUNT = 9.9 ether; // 9.9 tokens, matching minOut in tests

    function fillSwap(
        OrderDirection memory direction,
        uint32 orderIndex
    ) external override {
        // Transfer dstAsset from caller to this contract
        address dstToken = address(uint160(uint256(direction.dstAsset)));
        IERC20(dstToken).transferFrom(msg.sender, address(this), TAKE_AMOUNT);
        emit FillSwapCalled(msg.sender, abi.encode(direction));
    }

    function executeMatch(
        OrderDirection memory direction,
        uint32 takerIndex,
        address taker,
        uint96 payoutQuantity,
        bool isUnwrap
    ) external override {
        // Transfer srcAsset from caller to this contract
        IERC20(direction.srcAsset).transferFrom(msg.sender, address(this), TAKE_AMOUNT);
        emit ExecuteMatchCalled(msg.sender, abi.encode(direction));
    }

    // Required interface implementations with empty bodies
    function placeOrder(
        OrderDirection memory direction,
        OrderFunding memory funding,
        OrderExpiration memory expiration,
        bytes32 target,
        address filler
    ) external override {}

    function createMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes32 counterparty,
        uint96 srcQuantity
    ) external override {}

    function confirmMatch(
        OrderDirection memory direction,
        uint32 srcIndex
    ) external override {}

    function cancelOrder(
        OrderDirection memory direction,
        uint32 orderIndex
    ) external override {}

    function unwindMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bool isUnwrap
    ) external override {}

    function challengeMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions
    ) external payable override {}
}