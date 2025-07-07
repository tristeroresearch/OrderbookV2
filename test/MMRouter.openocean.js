const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MMRouter - Post-swap settlement", function () {
  let owner, user, refundTo;
  let TokenIn, TokenOut, tokenIn, tokenOut;
  let MockOrderbook, mockOrderbook;
  let MMRouter, mmRouter;

  beforeEach(async function () {
    [owner, user, refundTo] = await ethers.getSigners();

    // Deploy mock tokens
    TokenIn = await ethers.getContractFactory("MockERC20");
    TokenOut = await ethers.getContractFactory("MockERC20");
    
    tokenIn = await (await TokenIn.deploy("TokenIn", "TIN", 18)).waitForDeployment();
    tokenOut = await (await TokenOut.deploy("TokenOut", "TOUT", 18)).waitForDeployment();

    // Deploy mock Orderbook
    MockOrderbook = await ethers.getContractFactory("MockOrderbook");
    mockOrderbook = await (await MockOrderbook.deploy()).waitForDeployment();

    // Deploy MMRouter
    MMRouter = await ethers.getContractFactory("MMRouter");
    mmRouter = await (await MMRouter.deploy(await mockOrderbook.getAddress())).waitForDeployment();
  });

  it("should handle fillSwap after external DEX swap (single-chain)", async function () {
    const swapResult = ethers.parseEther("9.9"); // Amount after DEX swap (with slippage)
    const minOut = ethers.parseEther("9.5"); // Minimum acceptable

    // Simulate: DEX swap already happened and tokens are now in MMRouter
    await tokenOut.mint(await mmRouter.getAddress(), swapResult);

    // Prepare OrderDirection struct
    const direction = {
      srcAsset: await tokenIn.getAddress(),
      dstAsset: ethers.zeroPadValue(await tokenOut.getAddress(), 32),
      dstLzc: 1, // single-chain
    };

    // Log balances before settlement
    console.log("Before settlement:");
    console.log("MMRouter tokenOut balance:", ethers.formatEther(await tokenOut.balanceOf(await mmRouter.getAddress())));
    console.log("Orderbook tokenOut balance:", ethers.formatEther(await tokenOut.balanceOf(await mockOrderbook.getAddress())));

    // Call fillSwap to settle with orderbook
    await expect(
      mmRouter.fillSwap(
        direction,
        0, // orderIndex
        minOut,
        refundTo.address
      )
    ).to.emit(mockOrderbook, "FillSwapCalled");

    // Log balances after settlement
    console.log("\nAfter settlement:");
    console.log("MMRouter tokenOut balance:", ethers.formatEther(await tokenOut.balanceOf(await mmRouter.getAddress())));
    console.log("Orderbook tokenOut balance:", ethers.formatEther(await tokenOut.balanceOf(await mockOrderbook.getAddress())));

    // Check that orderbook received the tokens
    const orderbookBalance = await tokenOut.balanceOf(await mockOrderbook.getAddress());
    expect(orderbookBalance).to.equal(swapResult);
  });

  it("should handle executeMatch after external DEX swap (cross-chain)", async function () {
    const swapResult = ethers.parseEther("9.9"); // Amount after DEX swap (with slippage)
    const minOut = ethers.parseEther("9.5"); // Minimum acceptable

    // Simulate: DEX swap already happened and tokens are now in MMRouter
    await tokenIn.mint(await mmRouter.getAddress(), swapResult);

    // Prepare OrderDirection struct
    const direction = {
      srcAsset: await tokenIn.getAddress(),
      dstAsset: ethers.zeroPadValue(await tokenOut.getAddress(), 32),
      dstLzc: 2, // cross-chain
    };

    // Log balances before settlement
    console.log("Before settlement:");
    console.log("MMRouter tokenIn balance:", ethers.formatEther(await tokenIn.balanceOf(await mmRouter.getAddress())));
    console.log("Orderbook tokenIn balance:", ethers.formatEther(await tokenIn.balanceOf(await mockOrderbook.getAddress())));

    // Call executeMatch to settle with orderbook
    await expect(
      mmRouter.executeMatch(
        direction,
        0, // takerIndex
        user.address, // taker
        false, // isUnwrap
        minOut,
        refundTo.address
      )
    ).to.emit(mockOrderbook, "ExecuteMatchCalled");

    // Log balances after settlement
    console.log("\nAfter settlement:");
    console.log("MMRouter tokenIn balance:", ethers.formatEther(await tokenIn.balanceOf(await mmRouter.getAddress())));
    console.log("Orderbook tokenIn balance:", ethers.formatEther(await tokenIn.balanceOf(await mockOrderbook.getAddress())));

    // Check that orderbook received the tokens
    const orderbookBalance = await tokenIn.balanceOf(await mockOrderbook.getAddress());
    expect(orderbookBalance).to.equal(swapResult);
  });

  it("should revert if insufficient balance after DEX swap", async function () {
    const swapResult = ethers.parseEther("5.0"); // Less than minimum
    const minOut = ethers.parseEther("9.5"); // Higher than what we have

    // Simulate: DEX swap happened but didn't get enough tokens
    await tokenOut.mint(await mmRouter.getAddress(), swapResult);

    const direction = {
      srcAsset: await tokenIn.getAddress(),
      dstAsset: ethers.zeroPadValue(await tokenOut.getAddress(), 32),
      dstLzc: 1,
    };

    // Should revert due to insufficient balance
    await expect(
      mmRouter.fillSwap(direction, 0, minOut, refundTo.address)
    ).to.be.revertedWith("MMRouter: insufficient balance");
  });
});

// --- Mock contracts ---

// MockERC20, MockOpenOceanRouter, and MockOrderbook should be implemented in Solidity in the test/mocks directory or inline for the test. 