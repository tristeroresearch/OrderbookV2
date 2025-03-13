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

const RPC_URL = process.env.APE_RPC
const EXPLORER_URL = process.env.APE_EXPLORER_URL
const CONTRACT_NAME = "Orderbook"
const CHAIN_CURRENCY = 'APE'
const CHAIN_NAME = 'ApeChain'
const HARDHAT_NETWORK_NAME = 'apechain'
const LZ_ENDPOINT = "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B"
const LZ_EID = 30312
// Mantle deployment https://mantlescan.xyz/address/0xcF46728E4d3613Bcde64EC3B3d6c1565eD92664f#code
// Apechain deployment: https://apescan.io/address/0xE15f0BD64033cCCD807129D98732392C7aebceD6#code

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
        LZ_ENDPOINT,  // Replace with actual endpoint address if needed
        "0x451F52446EBD4376d4a05f4267eF1a03Acf1aAf4",  // OApp Owner address
        "0x033a1B4b586EFc07f7377c522E693fd855a505b1",  // Contract Owner address
        LZ_EID,                                         // Replace with actual LayerZero EID if needed
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

// This function transfers ownership of an already deployed contract.
const transfer_contract_ownership = async () => {
    const contractAddress = prompt("Enter the deployed contract address: ");
    const newOwnerAddress = prompt("Enter the new owner address: ");

    const provider = new ethers.providers.JsonRpcProvider({ url: RPC_URL, timeout: 600000 });
    const seedPhrase = await decrypt_mnemonic(ENCRYPTED_WALLET);
    const wallet = Wallet.fromMnemonic(seedPhrase);
    const signer = wallet.connect(provider);

    // Get the contract factory and attach to the deployed contract
    const ContractFactory = await hardhat.ethers.getContractFactory(CONTRACT_NAME);
    const contract = ContractFactory.attach(contractAddress).connect(signer);

    console.log(`Preparing to transfer ownership of contract ${contractAddress} to ${newOwnerAddress}`);
    if (confirmAction('Do you want to proceed with the ownership transfer? (Y/N) ')) {
        let gasLimit;
        try {
            console.log("Estimating gas for the transferOwnership call...");
            const estimatedGas = await contract.estimateGas.transferOwnership(newOwnerAddress);
            // Increase the estimate by 20% as a safety margin
            gasLimit = estimatedGas.mul(120).div(100);
            console.log(`Estimated Gas: ${estimatedGas.toString()}, using Gas Limit: ${gasLimit.toString()}`);
        } catch (err) {
            console.error("Gas estimation failed:", err.message);
            // Optionally, you can prompt the user for a manual gas limit if you're sure the call should succeed.
            const manualGasInput = prompt("Enter a manual gas limit (or press Enter to use fallback 2000000): ");
            gasLimit = manualGasInput ? ethers.BigNumber.from(manualGasInput) : ethers.BigNumber.from("2000000");
        }
        console.log("Sending transaction to transfer ownership...");
        const tx = await contract.transferOwnership(newOwnerAddress, { gasLimit });
        console.log("Waiting for transaction confirmation...");
        await tx.wait();
        console.log(`Ownership transferred. Check transaction: ${EXPLORER_URL}/tx/${tx.hash}`);
    } else {
        console.log("Ownership transfer aborted by the user.");
    }
};

// Check for a command line argument to decide which action to take
if (process.argv[2] === 'transfer') {
    transfer_contract_ownership();
} else {
    main();
}
