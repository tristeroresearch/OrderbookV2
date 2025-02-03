require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.28", // Specify your Solidity version
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  networks: {
    // Define your networks here
    // Example for Ethereum Mainnet and Ropsten Testnet
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    ethereum_mainnet: {
      url: process.env.ETHEREUM_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    arbitrum_mainnet: {
      url: process.env.ARBITRUM_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    optimism_mainnet: {
      url: process.env.OPTIMISM_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    polygon_mainnet: {
      url: process.env.POLYGON_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    base_mainnet: {
      url: process.env.BASE_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    avalanche_mainnet: {
      url: process.env.AVALANCHE_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    bsc_mainnet: {
      url: process.env.BSC_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    celo_mainnet: {
      url: process.env.CELO_MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    // Add other networks as needed
  },
  namedAccounts: {
    deployer: {
      default: 0, // Here, 0 refers to the first account in the mnemonic
    },
  },
};