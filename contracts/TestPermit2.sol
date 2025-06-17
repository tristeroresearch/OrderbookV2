// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/permit2/interfaces/IPermit2.sol";
import "../lib/permit2/interfaces/ISignatureTransfer.sol";

/**
 * @title TestPermit2
 * @notice Test helper that rebuilds Permit2 parameters on-chain from minimal
 *         order data and a user-generated signature.
 *
 *         You call `testSigTransfer` from the *token owner’s* EOA.  Everything
 *         else (nonce = 0, deadline = type(uint256).max, etc.) is assembled
 *         internally so your Python script only has to sign once and push the
 *         raw bytes.
 *
 *         – direction.srcAsset       → token being spent  
 *         – funding.srcQuantity      → amount being moved & requestedAmount  
 *         – filler                   → final recipient (`to`)  
 */
contract TestPermit2 {
    /* --------------------------------------------------------------------- */
    /*                              USER TYPES                               */
    /* --------------------------------------------------------------------- */

    struct OrderDirection {
        address srcAsset;
        bytes32 dstAsset;
        uint32  dstLzc;
    }

    struct OrderFunding {
        uint96  srcQuantity;
        uint96  dstQuantity;
        uint16  bondFee;
        address bondAsset;
        uint96  bondAmount;
    }

    struct OrderExpiration {
        uint32 timestamp;
        uint16 challengeOffset;
        uint16 challengeWindow;
    }

    /* --------------------------------------------------------------------- */
    /*                        EIP-712 TYPEHASH CONSTANTS                     */
    /* --------------------------------------------------------------------- */

    bytes32 private constant _ORDER_DIRECTION_TYPEHASH = keccak256(
        "OrderDirection(address srcAsset,bytes32 dstAsset,uint32 dstLzc)"
    );

    bytes32 private constant _ORDER_FUNDING_TYPEHASH = keccak256(
        "OrderFunding(uint96 srcQuantity,uint96 dstQuantity,uint16 bondFee,address bondAsset,uint96 bondAmount)"
    );

    bytes32 private constant _ORDER_EXPIRATION_TYPEHASH = keccak256(
        "OrderExpiration(uint32 timestamp,uint16 challengeOffset,uint16 challengeWindow)"
    );

    // Full definition with referenced sub-structs appended, per EIP-712 rules
    string private constant _ORDER_WITNESS_TYPESTRING =
        "OrderWitness(address sender,OrderDirection direction,OrderFunding funding,OrderExpiration expiration,bytes32 target,address filler)"
        "OrderDirection(address srcAsset,bytes32 dstAsset,uint32 dstLzc)"
        "OrderFunding(uint96 srcQuantity,uint96 dstQuantity,uint16 bondFee,address bondAsset,uint96 bondAmount)"
        "OrderExpiration(uint32 timestamp,uint16 challengeOffset,uint16 challengeWindow)"
        "TokenPermissions(address token,uint256 amount)";

    bytes32 private constant _ORDER_WITNESS_TYPEHASH = keccak256(bytes(_ORDER_WITNESS_TYPESTRING));

    /* --------------------------------------------------------------------- */
    /*                         IMMUTABLE PERMIT2 ADDRESS                     */
    /* --------------------------------------------------------------------- */

    IPermit2 public immutable PERMIT2;

    constructor(address permit2) {
        require(permit2 != address(0), "permit2 zero");
        PERMIT2 = IPermit2(permit2);
    }

    /* --------------------------------------------------------------------- */
    /*                                  EVENT                                */
    /* --------------------------------------------------------------------- */

    event WitnessTransferExecuted(
        address indexed owner,
        address indexed to,
        address indexed token,
        uint256 amount
    );

    /* --------------------------------------------------------------------- */
    /*                       MAIN ENTRY FOR YOUR PYTHON CALL                 */
    /* --------------------------------------------------------------------- */
    function testSigTransfer(
        OrderDirection memory direction,
        OrderFunding   memory funding,
        OrderExpiration memory expiration,
        bytes32         target,
        address         filler,
        bytes calldata  signature
    ) external {
        /* ----------------------- 1. Build witness hash -------------------- */

        bytes32 witnessHash = keccak256(
            abi.encode(
                _ORDER_WITNESS_TYPEHASH,
                /* sender   */ msg.sender,
                /* direction*/ keccak256(
                    abi.encode(
                        _ORDER_DIRECTION_TYPEHASH,
                        direction.srcAsset,
                        direction.dstAsset,
                        direction.dstLzc
                    )
                ),
                /* funding  */ keccak256(
                    abi.encode(
                        _ORDER_FUNDING_TYPEHASH,
                        funding.srcQuantity,
                        funding.dstQuantity,
                        funding.bondFee,
                        funding.bondAsset,
                        funding.bondAmount
                    )
                ),
                /* expiration */ keccak256(
                    abi.encode(
                        _ORDER_EXPIRATION_TYPEHASH,
                        expiration.timestamp,
                        expiration.challengeOffset,
                        expiration.challengeWindow
                    )
                ),
                /* target */ target,
                /* filler */ filler
            )
        );

        /* ----------------------- 2. Build Permit2 args -------------------- */
        ISignatureTransfer.TokenPermissions memory permitted = ISignatureTransfer.TokenPermissions({
            token:  direction.srcAsset,
            amount: uint160(funding.srcQuantity)         // down-cast (safe: srcQuantity ≤ 2¹⁶⁰-1 ?)
        });
        // (a) permit = what is allowed to be spent
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: permitted,
            nonce: 0,
            deadline: type(uint256).max
        });

        // (b) transferDetails = where the tokens should end up
        ISignatureTransfer.SignatureTransferDetails memory xfer = ISignatureTransfer.SignatureTransferDetails({
            to: filler,
            requestedAmount: funding.srcQuantity
        });

        /* -------------------- 3. Forward to Permit2 ----------------------- */
        PERMIT2.permitWitnessTransferFrom(
            permit,
            xfer,
            /* owner   */ msg.sender,
            /* witness */ witnessHash,
            /* typeStr */ _ORDER_WITNESS_TYPESTRING,
            /* sig     */ signature
        );

        emit WitnessTransferExecuted(msg.sender, filler, direction.srcAsset, funding.srcQuantity);
    }

    /* ------------------- optional: token rescue helper ------------------- */
    function sweepToken(address token, address to, uint256 amount) external {
        IERC20(token).transfer(to, amount);
    }
}
