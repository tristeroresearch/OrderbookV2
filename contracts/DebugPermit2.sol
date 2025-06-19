// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/permit2/interfaces/IPermit2.sol";
import "../lib/permit2/interfaces/ISignatureTransfer.sol";
import "../lib/permit2/interfaces/IERC1271.sol";

contract DebugPermit2 {
    struct PermitParams {
        address sender;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }
    
    IPermit2 public immutable PERMIT2;

    constructor(address permit2) {
        require(permit2 != address(0), "permit2 zero");
        PERMIT2 = IPermit2(permit2);
    }

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = 
        keccak256("TokenPermissions(address token,uint256 amount)");

    string public constant _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    /**
     * @notice Compute the type hash used for witness signing
     * @param witnessTypeString The witness type string to append to the stub
     * @return typeHash The full type hash used in EIP-712 signing
     */
    function computeTypeHash(string calldata witnessTypeString) public pure returns (bytes32 typeHash) {
        return keccak256(abi.encodePacked(_PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB, witnessTypeString));
    }
    
    /**
     * @notice Compute the token permissions hash
     * @param permitted The token permissions struct
     * @return Hash of the token permissions
     */
    function computeTokenPermissionsHash(
        ISignatureTransfer.TokenPermissions memory permitted
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permitted));
    }
    
    /**
     * @notice Compute the full witness hash as it would be in PermitHash.hashWithWitness
     * @param permit The permit data
     * @param witness The witness data
     * @param witnessTypeString The witness type string
     * @param spender The address that will be used in place of msg.sender in the hash
     * @return witnessHash The hash that would be created by PermitHash.hashWithWitness
     */
    function computeWitnessHash(
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes32 witness,
        string calldata witnessTypeString,
        address spender
    ) public pure returns (bytes32 witnessHash) {
        bytes32 typeHash = computeTypeHash(witnessTypeString);
        bytes32 tokenPermissionsHash = computeTokenPermissionsHash(permit.permitted);
        
        return keccak256(abi.encode(typeHash, tokenPermissionsHash, spender, permit.nonce, permit.deadline, witness));
    }

    /**
     * @notice Compute the EIP-712 digest for signing
     * @param witnessHash The hash from computeWitnessHash
     * @param domainSeparator The domain separator
     * @return digest The EIP-712 digest for signing
     */
    function computeDigest(bytes32 witnessHash, bytes32 domainSeparator) public pure returns (bytes32 digest) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, witnessHash));
    }
    
    /**
     * @notice Get the domain separator from Permit2
     * @return The domain separator
     */
    function getDomainSeparator() public view returns (bytes32) {
        return PERMIT2.DOMAIN_SEPARATOR();
    }
    
    /**
     * @notice Recover a signer from a signature and digest
     * @param signature The signature bytes
     * @param digest The digest that was signed
     * @return signer The recovered signer address
     */
    function recoverSigner(bytes calldata signature, bytes32 digest) public pure returns (address signer) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        if (signature.length == 65) {
            assembly {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 32))
                v := byte(0, calldataload(add(signature.offset, 64)))
            }
        } else if (signature.length == 64) {
            // EIP-2098
            bytes32 vs;
            assembly {
                r := calldataload(signature.offset)
                vs := calldataload(add(signature.offset, 32))
            }
            s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            v = uint8(uint256(vs >> 255)) + 27;
        } else {
            revert("Invalid signature length");
        }
        
        return ecrecover(digest, v, r, s);
    }

    /**
     * @notice Debug the full witness verification flow with your witnessTypeString
     * @param permit The permit data
     * @param witness The witness data
     * @param witnessTypeString The witness type string to test
     * @param owner The claimed owner address
     * @param signature The signature to verify
     * @return isValid Whether the signature is valid
     * @return witnessHash The computed witness hash
     * @return digest The EIP-712 digest
     * @return recoveredSigner The address recovered from the signature
     */
    function debugWitnessTypeString(
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes32 witness,
        string calldata witnessTypeString,
        address spender,
        address owner,
        bytes calldata signature
    ) public view returns (
        bool isValid,
        bytes32 witnessHash,
        bytes32 digest,
        address recoveredSigner
    ) {
        // Get domain separator from Permit2
        bytes32 domainSeparator = getDomainSeparator();
        
        // Compute the witness hash as it would be in the library
        witnessHash = computeWitnessHash(permit, witness, witnessTypeString, spender);
        
        // Compute the digest that should be signed
        digest = computeDigest(witnessHash, domainSeparator);
        
        // Recover the signer from the signature
        recoveredSigner = recoverSigner(signature, digest);
        
        // Check if valid
        isValid = (recoveredSigner == owner);
        
        return (isValid, witnessHash, digest, recoveredSigner);
    }

    function forwardToPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory xfer,
        PermitParams calldata p,
        string memory witnessTypeString,
        bytes32 witnessHash
    ) public {
        PERMIT2.permitWitnessTransferFrom(
            permit,
            xfer,
            p.sender,
            witnessHash,
            witnessTypeString,
            p.signature
        );
    }
}
