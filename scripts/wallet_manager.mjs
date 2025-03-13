import { getPass } from 'getpass';
import ethers from 'ethers';
import process, { argv } from 'process';
import crypto from 'crypto';

/**
 * Performs text encryption which yields similar resulust to running the following openSSL command:
 * echo "plaintext" | openssl enc -aes-256-cbc -a -md sha1 -pbkdf2 -pass pass:"pass" -S "salt_in_hex"
 * @param {*} plaintext 
 * @param {*} pass 
 * @param {*} salt 
 * @returns 
 */
export const encrypt_text = async (plaintext, pass, salt = null) => {
    return new Promise((resolve, reject) => {
        try {
            if (!salt) {
                salt = crypto.randomBytes(8); // 8 bytes salt
            }

            if (!Buffer.isBuffer(salt)) {
                throw new Error('Salt must be a Buffer. Did you forget Buffer.from(salt, \'base64\') ?');
            }

            // OpenSSL key derivation
            const keyIv = crypto.pbkdf2Sync(pass, salt, 10000, 48, 'sha1'); // 48 bytes for key and IV // Fix 1/3 apply the iteration count 10000
            const key = keyIv.slice(0, 32); // first 32 bytes for key
            const iv = keyIv.slice(32); // remaining 16 bytes for IV

            // Create cipher
            const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
            let encrypted = cipher.update(plaintext + '\n', 'utf8'); // Fix 2/3 append the line break
            encrypted = Buffer.concat([encrypted, cipher.final()]);

            // Combine all parts
            const result = encrypted; // Fix 3/3 Don't apply the prefix Salted__|<salt>

            const encrypted_text = result.toString('base64');

            resolve({ salt: salt.toString('base64'), encrypted_text: encrypted_text });
        } catch (error) {
            console.error('Error encrypting text.');
            reject(error);
        }
    });
}

/**
 * Performs text decryption which yields similar resulust to running the following openSSL command:
 * echo "encrypted_text" | openssl enc -d -aes-256-cbc -a -md sha1 -pbkdf2 -pass pass:"pass" -S "salt_in_hex"
 * @param {*} encryptedText 
 * @param {*} pass 
 * @param {*} salt 
 * @returns 
 */
export const decrypt_text = async (encryptedText, pass, salt = null) => {
    return new Promise((resolve, reject) => {
        try {
            if (!salt) {
                // For decryption, we need to know the salt used during encryption.
                throw new Error('Salt must be provided for decryption');
            }

            if (!Buffer.isBuffer(salt)) {
                throw new Error('Salt must be a Buffer. Did you forget Buffer.from(salt, \'base64\') ?');
            }

            // OpenSSL key derivation
            const keyIv = crypto.pbkdf2Sync(pass, salt, 10000, 48, 'sha1'); // 48 bytes for key and IV
            const key = keyIv.slice(0, 32); // first 32 bytes for key
            const iv = keyIv.slice(32); // remaining 16 bytes for IV

            // Decode the base64 encrypted text
            const encryptedBuffer = Buffer.from(encryptedText, 'base64');

            // Create decipher
            const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
            let decrypted = decipher.update(encryptedBuffer, 'base64', 'utf8');
            decrypted += decipher.final('utf8');

            // Remove the appended newline character
            decrypted = decrypted.replace(/\n$/, '');

            resolve(decrypted);
        } catch (error) {
            console.error('Error decrypting text.');
            reject(error);
        }
    });
}

export async function decrypt_mnemonic(encrypted_mnemonic) {
    return new Promise((resolve, reject) => {
        getPass({ prompt: 'Enter password' }, async (err, password) => {
            if (err) {
                reject(err);
            } else {
                const mnemonic = await decrypt_text(encrypted_mnemonic.encrypted_text, password, Buffer.from(encrypted_mnemonic.salt, 'base64'));
                resolve(mnemonic);
            }
        })
    })
}

// Function to generate a HD wallet and encrypted seed phrase
export const make_hd_wallet = async (password, k = null) => {
    // Generate HD Wallet
    const mnemonic = ethers.utils.entropyToMnemonic(ethers.utils.randomBytes(16));
    const wallet = ethers.Wallet.fromMnemonic(mnemonic);

    // Generate first 5 wallet addresses
    const derived_wallet_addresses = [];
    for (let i = 0; i < 5; i++) {
        const derivedWallet = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`);
        derived_wallet_addresses.push(derivedWallet.address);
    }

    // Encrypt the seed phrase
    try {
        const { salt, encrypted_text } = await encrypt_text(mnemonic, password);

        if (k) {
            const kth_wallet = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${k}`)
            const kth_wallet_address = kth_wallet.address

            return { address: wallet.address, encryptedSeedPhrase: { salt, encrypted_text }, derivedWalletAddresses: derived_wallet_addresses, k: k, kth_wallet_address: kth_wallet_address };
        }

        return { address: wallet.address, encryptedSeedPhrase: { salt, encrypted_text }, derivedWalletAddresses: derived_wallet_addresses };
    } catch (error) {
        console.error('Error encrypting seed phrase:', error.message);
        return null;
    }
};

// Command functions
const commands = {
    'make-hdwallet': async () => {
        const k = parseInt(argv[3]);

        console.log("k=", k)

        getPass({ prompt: 'Enter the password' }, (err, password1) => {
            if (err) {
                console.error('Error getting password:', err);
                return;
            }
            getPass({ prompt: 'Enter the password again' }, async (err, password2) => {
                if (err) {
                    console.error('Error getting password again:', err);
                    return;
                }
                if (password1 !== password2) {
                    console.error('Passwords do not match.');
                    return;
                }

                const walletDetails = await make_hd_wallet(password1, k);

                if (walletDetails) {
                    console.log(walletDetails);
                }
            });
        });
    },

    'encrypt-text': async () => {
        const plaintext = argv[3];
        if (!plaintext) {
            console.error('Plaintext argument is required.');
            process.exit(1);
        }

        getPass({ prompt: 'Enter password' }, async (err, password1) => {
            if (err) {
                console.error('Error getting password:', err);
                return;
            }
            getPass({ prompt: 'Enter password again' }, async (err, password2) => {
                if (err) {
                    console.error('Error getting password again', err);
                    return;
                }
                if (password1 !== password2) {
                    console.error('Passwords do not match.');
                    return;
                }

                try {
                    const enc_text = await encrypt_text(plaintext, password1);
                    console.log(enc_text);
                } catch (error) {
                    console.error('Error encrypting text:', error);
                }
            });

        });
    },

    'decrypt-text': async () => {
        const enc_text = argv[3];
        const salt = argv[4];

        if (!enc_text) {
            console.error('Encrypted text argument is required.');
            process.exit(1);
        }


        if (!salt) {
            console.error('Salt (base64) argument is required.');
            process.exit(1);
        }

        getPass({ prompt: 'Enter the decryption password' }, async (err, password) => {
            if (err) {
                console.error('Error getting password:', err);
                return;
            }

            try {
                const decryptedText = await decrypt_text(enc_text, password, Buffer.from(salt, 'base64'));
                console.log(decryptedText);
            } catch (error) {
                console.error('Error decrypting text:', error);
            }
        });
    },

    'check-enc-dec': async () => {
        // Sample data for testing
        const plaintext = 'This is a test.';
        const password = 'mysecretpassword';

        check_encrypt_decrypt(plaintext, password);
    },
};


if (process.argv[1] && process.argv[1].includes("wallet_manager.mjs") && process.argv[2]) {
    const command = argv[2];

    if (commands[command]) {
        commands[command]();
    } else {
        console.error('Invalid command. Available commands: make-hdwallet, hash-password, decrypt-text, encrypt-text');
        process.exit(1);
    }
}