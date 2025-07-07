// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20}          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TradeInterface}  from "./interfaces/IOptimistic.sol";

contract MMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

/* ──────────────────────────── Storage ────────────────────────────────── */
    TradeInterface public immutable orderBook;
    constructor(TradeInterface _ob) { orderBook = _ob; }

/* ======================================================================= */
/*                         SINGLE-CHAIN  ─  fillSwap                       */
/* ======================================================================= */

    function fillSwap(
        TradeInterface.OrderDirection calldata direction,
        uint32                        orderIndex,
        uint256                       minOut,
        address                       refundTo
    ) external payable nonReentrant {

        // Convert dstAsset (bytes32) → address for ERC-20 handling
        address dstAssetAddr = _bytes32ToAddress(direction.dstAsset);
        IERC20  payToken     = IERC20(dstAssetAddr);

        // Check balance - assumes DEX swap already completed and tokens are in this contract
        uint256 bal = payToken.balanceOf(address(this));
        require(bal >= minOut, "MMRouter: insufficient balance");

        // Approve and call orderbook
        payToken.safeIncreaseAllowance(address(orderBook), bal);
        orderBook.fillSwap(direction, orderIndex);

        // Refund any remaining dust
        _refundDust(refundTo, payToken);
    }

/* ======================================================================= */
/*                       CROSS-CHAIN  ─  executeMatch                      */
/* ======================================================================= */

    function executeMatch(
        TradeInterface.OrderDirection calldata direction,
        uint32                        takerIndex,
        address                       taker,
        bool                          isUnwrap,
        uint256                       minOut,
        address                       refundTo
    ) external payable nonReentrant {

        // Use srcAsset as payToken (no conversion needed for cross-chain)
        IERC20 payToken = IERC20(direction.srcAsset);
        
        // Check balance - assumes DEX swap already completed and tokens are in this contract
        uint256 bal = payToken.balanceOf(address(this));
        require(bal >= minOut, "MMRouter: insufficient balance");

        // Infer payoutQty from actual balance
        uint96 payoutQty = uint96(bal);
        require(payoutQty == bal, "MMRouter: amount overflow");

        // Approve and call orderbook
        payToken.safeIncreaseAllowance(address(orderBook), bal);
        orderBook.executeMatch(
            direction,
            takerIndex,
            taker,
            payoutQty,
            isUnwrap
        );

        // Refund any remaining dust
        _refundDust(refundTo, payToken);
    }

/* ─────────────────────── internal helpers ───────────────────────────── */

    function _refundDust(address refundTo, IERC20 payToken) private {
        uint256 dust = payToken.balanceOf(address(this));
        if (dust > 0) payToken.safeTransfer(refundTo, dust);

        // Also refund any ETH dust
        uint256 ethDust = address(this).balance;
        if (ethDust > 0) {
            (bool s, ) = refundTo.call{value: ethDust}("");
            require(s, "MMRouter: ETH refund failed");
        }
    }

    /* Helper: cast bytes32 → address (lower 20 bytes) */
    function _bytes32ToAddress(bytes32 b) private pure returns (address) {
        return address(uint160(uint256(b)));
    }

    // Allow receiving ETH and tokens
    receive() external payable {}
} 