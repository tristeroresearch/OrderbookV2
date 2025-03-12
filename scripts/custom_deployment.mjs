import hardhat from 'hardhat';
import PromptSync from 'prompt-sync';
import { Wallet, ethers, utils } from 'ethers';
import { decrypt_mnemonic } from './wallet_manager.mjs';

const prompt = PromptSync();

// Function to prompt the user for confirmation
const confirmAction = (t) => {
    let answer = prompt(t);
    return answer.toLowerCase() === 'y';
};

// Put the encrypted wallet here, which you generated
// with the wallet manager script using
// `node ./wallet_manager.mjs make-hdwallet`
const ENCRYPTED_WALLET = JSON.parse(process.env.ENCRYPTED_WALLET)

// const RPC_URL = "https://eth-sepolia.public.blastapi.io"
// const EXPLORER_URL = "https://sepolia.etherscan.io"
// const CONTRACT_NAME = "Orderbook"
// const CHAIN_CURRENCY = 'ETH'
// const CHAIN_NAME = 'Sepolia'
// const HARDHAT_NETWORK_NAME = 'sepolia'

const RPC_URL = process.env.MANTLE_RPC
const EXPLORER_URL = process.env.MANTLE_EXPLORER_URL
const CONTRACT_NAME = "Orderbook"
const CHAIN_CURRENCY = 'MNT'
const CHAIN_NAME = 'Mantle'
const HARDHAT_NETWORK_NAME = 'mantle'
// Mantle deployed to https://mantlescan.xyz/address/0xE15f0BD64033cCCD807129D98732392C7aebceD6#code

const main = async () => {
    const provider = new ethers.providers.JsonRpcProvider({ url: RPC_URL, timeout: 600000 });

    const seedPhrase = await decrypt_mnemonic(ENCRYPTED_WALLET)
    const wallet = Wallet.fromMnemonic(seedPhrase)
    const deployer_wallet = wallet.connect(provider);

    console.log(`Deployer Wallet is ${deployer_wallet.address}`)
    let balance = await provider.getBalance(deployer_wallet.address)
    console.log("Balance of", deployer_wallet.address, `on ${CHAIN_NAME} =`, utils.formatEther(balance), `${CHAIN_CURRENCY}`);

    const Constructor = (await hardhat.ethers.getContractFactory(CONTRACT_NAME)).connect(deployer_wallet);

    const ConstructorArgs = [
        "0x1a44076050125825900e736c501f859c50fE728c",  // Replace with actual endpoint address if needed
        "0x451F52446EBD4376d4a05f4267eF1a03Acf1aAf4",  // Owner address
        30181,                                         // Replace with actual LayerZero EID if needed
    ];

    console.log(`Will ${CONTRACT_NAME} on ${CHAIN_NAME} with args:`, ConstructorArgs);

    if (confirmAction('Do you want to proceed with the deployment? (Y/N)  ')) {
        console.log(`Waiting for transaction...`)

        const DeployedContract = await Constructor.deploy(...ConstructorArgs);

        await DeployedContract.deployed()

        console.log(`${CONTRACT_NAME} deployed: ${EXPLORER_URL}/address/${DeployedContract.address}`);
        console.log(`To verify, run: npx hardhat verify --network ${HARDHAT_NETWORK_NAME} "${DeployedContract.address}" ${ConstructorArgs.map(arg => `"${arg}"`).join(" ")}`)
    } else {
        console.log('Deployment aborted by the user.');
    }
}

main();
