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
        uint32 dstLzc;
    }

    struct OrderFunding {
        uint96 srcQuantity;
        uint96 dstQuantity;
        uint16 bondFee;
        address bondAsset;
        uint96 bondAmount;
    }

    struct OrderExpiration {
        uint32 timestamp;
        uint16 challengeOffset;
        uint16 challengeWindow;
    }

    struct PermitParams {
        address sender;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    /* --------------------------------------------------------------------- */
    /*                        EIP-712 TYPEHASH CONSTANTS                     */
    /* --------------------------------------------------------------------- */

    bytes32 private constant _ORDER_DIRECTION_TYPEHASH =
        keccak256(
            "OrderDirection(address srcAsset,bytes32 dstAsset,uint32 dstLzc)"
        );

    bytes32 private constant _ORDER_FUNDING_TYPEHASH =
        keccak256(
            "OrderFunding(uint96 srcQuantity,uint96 dstQuantity,uint16 bondFee,address bondAsset,uint96 bondAmount)"
        );

    bytes32 private constant _ORDER_EXPIRATION_TYPEHASH =
        keccak256(
            "OrderExpiration(uint32 timestamp,uint16 challengeOffset,uint16 challengeWindow)"
        );

    // Full definition with referenced sub-structs appended, per EIP-712 rules
    string private constant _ORDER_WITNESS_TYPESTRING =
        "OrderWitness(address sender,OrderDirection direction,OrderFunding funding,OrderExpiration expiration,bytes32 target,address filler)"
        "OrderDirection(address srcAsset,bytes32 dstAsset,uint32 dstLzc)"
        "OrderFunding(uint96 srcQuantity,uint96 dstQuantity,uint16 bondFee,address bondAsset,uint96 bondAmount)"
        "OrderExpiration(uint32 timestamp,uint16 challengeOffset,uint16 challengeWindow)"
        "TokenPermissions(address token,uint256 amount)";

    bytes32 private constant _ORDER_WITNESS_TYPEHASH =
        keccak256(bytes(_ORDER_WITNESS_TYPESTRING));

    function _calcWitnessHash(
        address sender,
        OrderDirection calldata d,
        OrderFunding calldata f,
        OrderExpiration calldata e,
        bytes32 target,
        address filler
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _ORDER_WITNESS_TYPEHASH,
                    sender,
                    keccak256(
                        abi.encode(
                            _ORDER_DIRECTION_TYPEHASH,
                            d.srcAsset,
                            d.dstAsset,
                            d.dstLzc
                        )
                    ),
                    keccak256(
                        abi.encode(
                            _ORDER_FUNDING_TYPEHASH,
                            f.srcQuantity,
                            f.dstQuantity,
                            f.bondFee,
                            f.bondAsset,
                            f.bondAmount
                        )
                    ),
                    keccak256(
                        abi.encode(
                            _ORDER_EXPIRATION_TYPEHASH,
                            e.timestamp,
                            e.challengeOffset,
                            e.challengeWindow
                        )
                    ),
                    target,
                    filler
                )
            );
    }

    function _forwardToPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory xfer,
        PermitParams calldata p,
        bytes32 witnessHash
    ) private {
        PERMIT2.permitWitnessTransferFrom(
            permit,
            xfer,
            p.sender,
            witnessHash,
            _ORDER_WITNESS_TYPESTRING,
            p.signature
        );
    }

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
        address indexed sender,
        address indexed to,
        address indexed token,
        uint256 amount
    );

    /* --------------------------------------------------------------------- */
    /*                       MAIN ENTRY FOR YOUR PYTHON CALL                 */
    /* --------------------------------------------------------------------- */
    function testSigTransfer(
        PermitParams calldata p,
        OrderDirection calldata d,
        OrderFunding calldata f,
        OrderExpiration calldata e,
        bytes32 target,
        address filler
    ) external {
        bytes32 witnessHash = _calcWitnessHash(
            p.sender,
            d,
            f,
            e,
            target,
            filler
        );

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer
            .PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: d.srcAsset,
                    amount: f.srcQuantity
                }),
                nonce: p.nonce,
                deadline: p.deadline
            });

        ISignatureTransfer.SignatureTransferDetails
            memory xfer = ISignatureTransfer.SignatureTransferDetails({
                to: filler,
                requestedAmount: f.srcQuantity
            });

        _forwardToPermit2(permit, xfer, p, witnessHash);

        emit WitnessTransferExecuted(
            p.sender,
            filler,
            d.srcAsset,
            f.srcQuantity
        );
    }

    /* ------------------- optional: token rescue helper ------------------- */
    function sweepToken(address token, address to, uint256 amount) external {
        IERC20(token).transfer(to, amount);
    }
}
