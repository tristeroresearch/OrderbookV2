// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract MockOpenOceanRouter {
    address public tokenIn;
    address public tokenOut;

    constructor(address _tokenIn, address _tokenOut) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
    }

    function swap(address to, uint256 amountIn, bool isCrossChain) external returns (uint256 amountOut) {
        // Pull tokenIn from caller (MMRouter)
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
        
        // Calculate output amount (1% fee)
        amountOut = (amountIn * 99) / 100;

        if (!isCrossChain) {
            // Single-chain case: send tokenOut to MMRouter
            require(IERC20(tokenOut).transfer(msg.sender, amountOut), "Transfer failed");
        } else {
            // Cross-chain case: send tokenIn back to MMRouter
            require(IERC20(tokenIn).transfer(msg.sender, amountOut), "Transfer failed");
        }

        return amountOut;
    }
}