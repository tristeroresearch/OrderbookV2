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

// Network configuration - can be adjusted as needed
const RPC_URL = process.env.BASE_RPC
const EXPLORER_URL = process.env.BASE_EXPLORER_URL
const CONTRACT_NAME = "DebugPermit2"
const CHAIN_CURRENCY = 'ETH'
const CHAIN_NAME = 'Base'
const HARDHAT_NETWORK_NAME = 'base_mainnet'

// Default Permit2 addresses on different networks
const PERMIT2_ADDRESSES = {
    'base': '0x000000000022d473030f116ddee9f6b43ac78ba3', // Universal Permit2 address (same on all networks)
    'mainnet': '0x000000000022d473030f116ddee9f6b43ac78ba3',
    'apechain': '0x000000000022d473030f116ddee9f6b43ac78ba3',
    // Add other networks as needed
};

const main = async () => {
    const provider = new ethers.providers.JsonRpcProvider({ url: RPC_URL, timeout: 600000 });

    const seedPhrase = await decrypt_mnemonic(ENCRYPTED_WALLET)
    const wallet = Wallet.fromMnemonic(seedPhrase)
    const deployer_wallet = wallet.connect(provider);

    console.log(`Deployer Wallet is ${deployer_wallet.address}`)
    let balance = await provider.getBalance(deployer_wallet.address)
    console.log("Balance of", deployer_wallet.address, `on ${CHAIN_NAME} =`, utils.formatEther(balance), `${CHAIN_CURRENCY}`);

    // Get TestPermit2 contract factory
    const Constructor = (await hardhat.ethers.getContractFactory(CONTRACT_NAME)).connect(deployer_wallet);

    // Get Permit2 address for this network or prompt for custom address
    let permit2Address = PERMIT2_ADDRESSES[HARDHAT_NETWORK_NAME] || '0x000000000022d473030f116ddee9f6b43ac78ba3';
    let useCustomPermit2 = confirmAction(`Use default Permit2 address (${permit2Address})? (Y) or provide custom address (N): `);
    
    if (!useCustomPermit2) {
        permit2Address = prompt('Enter Permit2 contract address: ');
        if (!ethers.utils.isAddress(permit2Address)) {
            console.error('Invalid Ethereum address provided. Aborting deployment.');
            return;
        }
    }

    const ConstructorArgs = [
        permit2Address  // Permit2 contract address
    ];

    console.log(`Will deploy ${CONTRACT_NAME} on ${CHAIN_NAME} with Permit2 address: ${permit2Address}`);

    if (confirmAction('Do you want to proceed with the deployment? (Y/N) ')) {
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
