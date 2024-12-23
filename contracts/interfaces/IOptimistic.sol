// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface TradeInterface {
    //PART 1: FUNCTIONS

    /**
     * @dev Submits a new order.
     * @param direction The direction parameters of the order (source asset, destination asset, and destination chain ID).
     * @param funding The funding parameters of the order (amount, minimum output, bond fee, bond asset, and bond amount).
     * @param expiration The expiration parameters of the order (timestamp, challenge offset, and challenge window).
     * @param target The address of the wallet where the funds will be delivered
     * @param filler The specified address has permissons to fill this order at some later time via createMatch (if multichain) and fillSwap (if singleChain). Set to address(0) to place order without access controls.
     */
    function placeOrder(
        OrderDirection memory direction,
        OrderFunding memory funding,
        OrderExpiration memory expiration,
        bytes32 target,
        address filler
    ) external;


    /**
     * @dev Creates a new match between orders.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param orderIndex The index of the order. This is equivelent to srcIndex in other parts of the code
     */
    function fillSwap(
        OrderDirection memory direction,
        uint32 orderIndex
    ) external;

    /**
     * @dev Creates a new match between orders.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param srcIndex The index of the source order.
     * @param counterparty The wallet on the destination chain. This must be the same address as dest_order.sender
     * @param srcQuantity The quantity of srcAsset in the match.
     */
    function createMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes32 counterparty,
        uint96 srcQuantity
    ) external;

    /**
     * @dev Executes an existing match.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param takerIndex The index of the taker order. I.e. the index of the order not on this chain.
     * @param taker The address to which funds will be sent
     * @param payoutQuantity The quantity of srcAsset in the payout.
     * @param isUnwrap set to true if dealing with a wrapped gas token like WETH
     */
    function executeMatch(
        OrderDirection memory direction,
        uint32 takerIndex,
        address taker,
        uint96 payoutQuantity,
        bool isUnwrap
    ) external;

    /**
     * @dev Confirms a match.
     * @param srcIndex The index of the source order.
     */
    function confirmMatch(
        OrderDirection memory direction,
        uint32 srcIndex
    ) external;

    /**
     * @dev Cancels an order.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param orderIndex The index of the order.
     */
    function cancelOrder(
        OrderDirection memory direction,
        uint32 orderIndex
    ) external;

    /**
     * @dev Challenges an existing match.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param srcIndex The nonce of the match.
     */
    function unwindMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bool isUnwrap
    ) external;


    /**
     * @dev Challenges an existing match.
     * @param direction The direction parameters of the source order (source asset, destination asset, and destination chain ID).
     * @param srcIndex The nonce of the match.
     */
    function challengeMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes calldata _extraSendOptions, // gas settings for A -> B
        bytes calldata _extraReturnOptions // gas settings for B -> A
    ) external payable;


    // PART 2: STRUCTS
    
    
    /**
     * @dev Struct representing an order.
     * @param sender The address of the order creator.
     * @param direction The direction parameters of the order.
     * @param funding The funding parameters of the order.
     * @param expiration The expiration parameters of the order.
     * @param filler Gives the specified address permissons to fill this order at some later time 
     */
    struct Order {
        address sender;
        OrderFunding funding;
        OrderExpiration expiration;
        uint96 settled;
        bytes32 target;
        address filler;
    }
    /**
     * @dev Struct for direction parameters of an order.
     * @param srcAsset The source asset being offered.
     * @param dstAsset The destination asset desired.
     * @param dstLzc The chain ID of the destination chain.
     */
    struct OrderDirection {
        address srcAsset;
        bytes32 dstAsset;
        uint32 dstLzc;
    }

    /**
     * @dev Struct for funding parameters of an order.
     * @param srcQuantity The quantity of srcAsset being offered.
     * @param dstQuantity The minimum quantity of dstAsset to be received.
     * @param bondFee The basis points percentage which will go to the bonder.
     * @param bondAsset The asset used for the bond.
     * @param bondAmount The amount of the bond asset.
     */
    struct OrderFunding {
        uint96 srcQuantity;
        uint96 dstQuantity;
        uint16 bondFee;
        address bondAsset; 
        uint96 bondAmount;
    }

    /**
     * @dev Struct for expiration parameters of an order.
     * @param timestamp The timestamp when the order was created.
     * @param challengeOffset The offset for the challenge window start.
     * @param challengeWindow The duration of the challenge window in seconds.
     */
    struct OrderExpiration {
        uint32 timestamp;
        uint16 challengeOffset; 
        uint16 challengeWindow;
    }


    /**
    * @dev Represents a match between orders in the trading system.
    * @param dstIndex Index of the destination order.
    * @param srcQuantity Quantity of srcAsset in the match.
    * @param dstQuantity Quantity of dstAsset in the match.
    * @param receiver Address to receive the destination asset.
    * @param bonder Address of the bonder.
    * @param blockNumber Block number when the match was created.
    * @param finalized Whether the match has been executed.
    * @param challenged Whether the match is locked.
    */
    struct Match {
        // Index
        uint32 index;
        // Pricing
        uint96 srcQuantity;           // Quantity of srcAsset in the match
        uint96 dstQuantity;           // Quantity of dstAsset in the match
        // Counterparty
        bytes32 maker;                // Address which will fill the match
        bytes32 target;               // Destination Wallet
        address bonder;               // Address of the bonder
        // Security
        uint96 blockNumber;           // Block number when the match was created
        bool finalized;               // Whether the match has been finalized
        bool challenged;              // Whether the match is locked.
    }


    struct Pair {
        address             src;
        address             dst;
        uint16              lzc;
        Order[] orders;
        mapping(uint => Match) matches; //indexed by taker order id
        mapping(uint => mapping (bytes32 => uint)) receipts; // indexed by taker order id and uint payoutQuantity
    }

    struct Payload {
        address challenger;
        address srcToken;
        bytes32 dstToken;
        uint32 srcIndex;
        bytes32 counterparty;
        bytes32 target;
        uint minAmount;
        uint status; //0 means undecided, 1 means challenge is true and succeeded, 2 means challenge failed
    }

}