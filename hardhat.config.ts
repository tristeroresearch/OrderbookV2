require("@nomiclabs/hardhat-ethers");
require('@nomicfoundation/hardhat-verify');
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
    sepolia: {
      // gasPrice: 3e1,
      chainId: 11155111,
      gas: 2e11,
      gasLimit: 2e11,
      url: process.env['SEPOLIA_RPC'] || '',
      accounts: process.env['TESTNET_PRIVKEY']
        ? [process.env['TESTNET_PRIVKEY']]
        : [],
    },
    mantle: {
      // gasPrice: 3e1,
      chainId: 5000,
      gas: 2e11,
      gasLimit: 2e11,
      url: process.env['MANTLE_RPC'] || '',
      accounts: process.env['PRIVATE_KEY']
        ? [process.env['PRIVATE_KEY']]
        : [],
    },
    // Add other networks as needed
  },
  etherscan: {
    apiKey: {
      sepolia: process.env['ETHERSCAN_API_KEY'],
      mainnet: process.env['ETHERSCAN_API_KEY'],
      arbitrumOne: process.env['ARBISCAN_API_KEY'],
      bsc: process.env['BSCSCAN_API_KEY'],
      base: process.env['BASESCAN_API_KEY'],
      blast: process.env['BLASTSCAN_API_KEY'],
      mantle: process.env['MANTLESCAN_API_KEY']
    },
    sourcify: {
      // Disabled by default
      // Doesn't need an API key
      enabled: true
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: process.env['BASE_MAINNET_EXPLORER_URL']
        }
      },
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.blastscan.io/api",
          browserURL: process.env['BLAST_MAINNET_EXPLORER_URL']
        }
      },
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://api.mantlescan.xyz/api",
          browserURL: process.env['MANTLE_EXPLORER_URL']
        }
      }
    ]
  },
  namedAccounts: {
    deployer: {
      default: 0, // Here, 0 refers to the first account in the mnemonic
    },
  },
};