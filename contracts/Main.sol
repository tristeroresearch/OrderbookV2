// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interfaces/IOptimistic.sol";
import "./interfaces/IWrapped.sol";

import { OApp, MessagingFee, Origin } from "./lzApp//lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "./lzApp/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract Orderbook is OApp, OAppOptionsType3, TradeInterface, ReentrancyGuard {

    mapping(uint => mapping(bytes32 => mapping(address => Pair))) public book;
    uint32                    public srcLzc;
    uint                      private constant BASIS_POINTS=10000;
    uint16                    private constant SEND = 1;
    uint16                    public maxFee = 1001;
    //Constructor
    constructor(address _endpoint, address _owner, uint32 _lzEid) OApp(_endpoint, _owner) Ownable(msg.sender) {
        srcLzc = _lzEid;
    }
    
    function setMaxFee(uint16 _newMaxFee) public onlyOwner {
        maxFee = _newMaxFee;
    }
    

    event OrderPlaced(address indexed sender, OrderDirection direction, uint32 orderIndex, OrderFunding funding, OrderExpiration expiration, bytes32 target, address filler);
    event SwapFilled(address indexed maker,  OrderDirection direction, uint32 orderIndex, uint96 srcQuantity, uint96 dstQuantity, address taker, address target, uint96 blockNumber);
    event MatchCreated(address indexed bonder, OrderDirection direction, uint32 orderIndex, uint96 srcQuantity, uint96 dstQuantity, address taker, bytes32 maker, uint96 blockNumber);
    event MatchExecuted(address indexed maker, OrderDirection direction, uint32 takerIndex, uint96 takerQuantity, address target);
    event MatchConfirmed(address indexed bonder, OrderDirection direction, uint32 orderIndex, uint16 bondFee);
    event MatchUnwound(address indexed bonder, OrderDirection direction, uint32 orderIndex);
    event ChallengeRaised(address indexed challenger, OrderDirection direction, uint32 srcIndex, address bonder, uint32 dstIndex);
    event OrderCancelled(address indexed sender,  OrderDirection direction, uint32 orderIndex);
    event ChallengeResult(bool challenge_status);

    //PlaceTrade Functions
    function placeOrder(
        OrderDirection memory direction,
        OrderFunding memory funding,
        OrderExpiration memory expiration,
        bytes32 target, //wallet where funds will be delivered
        address filler //set filler to address(0) if you want the order to be public
    ) public {

        //checks
        require((expiration.challengeOffset + expiration.challengeWindow) < 1e5 , "!maxWindow"); 
        require(funding.bondFee < maxFee , "!maxFee");
        require(bytes32ToAddress(target) != address(0), "!destWallet");

        //action
        Order[] storage orders=book[direction.dstLzc][direction.dstAsset][direction.srcAsset].orders;

        Order memory newOrder = Order({
            sender: msg.sender,
            funding: funding,
            expiration: expiration,
            settled: uint96(0),
            target: target,
            filler: filler
        });

        uint32 orderIndex=uint32(orders.length);
        orders.push(newOrder);

        //event 
        emit OrderPlaced(
            msg.sender,
            direction,
            orderIndex,
            funding,
            expiration,
            target,
            filler        
        );
        
        //an intent...no funds are pulled
    }

    //Read Functions
    function getOrders(address srcAsset, bytes32 dstAsset, uint dstLzc) public view returns (Order[] memory orders) {
        orders=book[dstLzc][dstAsset][srcAsset].orders;
    }

    function getOrder(address srcAsset, bytes32 dstAsset, uint dstLzc, uint index) public view returns (Order memory _order) {
        _order=book[dstLzc][dstAsset][srcAsset].orders[index];
    } 

    function getReceipt(address srcAsset, bytes32 dstAsset, uint dstLzc, uint srcIndex, bytes32 target) public view returns (uint _receipt) {
        _receipt=book[dstLzc][dstAsset][srcAsset].receipts[srcIndex][target];
    } 

    function getMatch(address srcAsset, bytes32 dstAsset, uint dstLzc, uint index) public view returns (Match memory _match) {
        _match=book[dstLzc][dstAsset][srcAsset].matches[index];
    } 

    function getCurrentBlockNumber() public view returns (uint256) {
        return block.number;
    }

    //Single Chain Swap
    function fillSwap(OrderDirection memory direction, uint32 orderIndex) public nonReentrant {
        
        //Chain Control
        require(direction.dstLzc == srcLzc, "!OnlySingleChain");

        //Load Order
        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];
        require(orderIndex < selected_pair.orders.length, "!InvalidOrderIndex");
        Order storage order = selected_pair.orders[orderIndex];

        OrderFunding memory funding = order.funding;
        OrderExpiration memory expiration = order.expiration;

        address taker = order.sender;
        address target = bytes32ToAddress(order.target);
        uint96 srcQuantity = funding.srcQuantity;
        uint96 dstQuantity = funding.dstQuantity;
        uint96 blockNumber=uint96(block.number);

        //check - Flow Controls
        require(order.filler == msg.sender, "!ProhibitedFiller");
        require(order.settled == 0, "!Settled");
        require(expiration.timestamp >= block.timestamp, "!Expired");
        require(srcQuantity > 0, "!ZeroMatch");


        //update
        Match memory TakerMatch = Match({
          index: orderIndex,
          srcQuantity: srcQuantity,
          dstQuantity: dstQuantity,
          maker: addressToBytes32(msg.sender),
          target: addressToBytes32(target),
          bonder: address(0),
          blockNumber: blockNumber,
          finalized: true,
          challenged: false
        });

        selected_pair.matches[orderIndex]=TakerMatch; //read only

        //state change
        order.settled+=srcQuantity;

        //transfer - taker "X" maker
        transferFrom(direction.srcAsset, taker, srcQuantity); //pull taker
        transferFrom(bytes32ToAddress(direction.dstAsset), msg.sender, dstQuantity); //pull maker

        transferTo(bytes32ToAddress(direction.dstAsset), target, dstQuantity); //pay taker at dest. wallet
        transferTo(direction.srcAsset, msg.sender, srcQuantity); //pay maker

        
        emit SwapFilled(msg.sender, direction, orderIndex, srcQuantity, dstQuantity, taker, target, blockNumber);
    }



    //Core Functions Multichain
    function createMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes32 counterparty,
        uint96 srcQuantity
    ) public nonReentrant {

        //Chain Control
        require(direction.dstLzc != srcLzc, "!OnlyCrossChain");

        //Load Order
        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];
        require(srcIndex < selected_pair.orders.length, "!InvalidOrderIndex");
        Order storage order = selected_pair.orders[srcIndex];

        OrderFunding memory funding = order.funding;
        OrderExpiration memory expiration = order.expiration;
        uint96 blockNumber=uint96(block.number);

        //check - Flow Controls
        if (order.filler != address(0)) {
            require(order.filler == msg.sender, "!ProhibitedFiller");
        }
        require(order.settled == 0, "!Settled");
        require(bytes32ToAddress(counterparty) != address(0), "!NullAddress");
        require(funding.srcQuantity == srcQuantity, "!PartialFill");
        require(expiration.timestamp >= block.timestamp, "!Expired");

        //update
        Match memory TakerMatch = Match({
          index: srcIndex,
          srcQuantity: srcQuantity,
          dstQuantity: funding.dstQuantity,
          maker: counterparty,
          target: order.target,
          bonder: msg.sender,
          blockNumber: blockNumber,
          finalized: false,
          challenged: false
        });

        //state change
        selected_pair.matches[srcIndex]=TakerMatch; //onlyBonder
        order.settled=srcQuantity;

        //transferIN
        transferFrom(funding.bondAsset, msg.sender, funding.bondAmount); //bonder
        transferFrom(direction.srcAsset, order.sender, srcQuantity); //taker

        //event
        emit MatchCreated(msg.sender, direction, srcIndex, srcQuantity, funding.dstQuantity, order.sender, counterparty, blockNumber);
    }


    function executeMatch(
        OrderDirection memory direction,
        uint32 takerIndex,
        address target,
        uint96 payoutQuantity,
        bool isUnwrap
    ) public nonReentrant {
        //Chain Control
        require(direction.dstLzc != srcLzc, "!OnlyCrossChain");

        //Load Order
        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];

        // checks - loose protections for makers
        require(payoutQuantity > 0, "Zero valued match");
        require(target != address(0), "!zeroAddress");

        transferFrom(direction.srcAsset, msg.sender, payoutQuantity); //pull in fund funds
        
        if (isUnwrap) {
            //Unwrap the token and transfer srcQuantity of the native gas token to the user
            IWrapped wrappedToken = IWrapped(direction.srcAsset);
            wrappedToken.withdraw(payoutQuantity);
            // //send the gas token
            (bool sent,) = target.call{value: payoutQuantity}("");
            require(sent, "!WrappedTokenTransfer");
        }

        else {
            transferTo(direction.srcAsset, target, payoutQuantity); //pay taker's target
        }

        // update add receipt
        selected_pair.receipts[takerIndex][addressToBytes32(target)] += payoutQuantity;

        //event
        emit MatchExecuted(msg.sender, direction, takerIndex, payoutQuantity, target);
    }

    function confirmMatch(
        OrderDirection memory direction,
        uint32 srcIndex
    ) public {

        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];
        Order storage _order= selected_pair.orders[srcIndex];
        Match storage _match=selected_pair.matches[srcIndex];

        //cache
        OrderFunding memory funding = _order.funding;
        OrderExpiration memory expiration = _order.expiration;
        address bonder = _match.bonder;
        address maker = bytes32ToAddress(_match.maker);
        uint validBlock = _match.blockNumber + expiration.challengeOffset + expiration.challengeWindow;
        
        //check
        require(!_match.finalized && !_match.challenged, "!Match is closed");
        require(msg.sender==bonder || msg.sender==maker, "!OnlyMakerOrBonder");
        require(block.number > validBlock, "Must wait before confirming match");
        
        //math
        uint order_amount = funding.srcQuantity;
        uint16 fee =funding.bondFee;
        uint maker_payout=applyFee(order_amount, fee);
        uint bonder_fee_payout=bondFee(order_amount, fee);

        //state
        _match.finalized=true; 

        //transfer
        transferTo(direction.srcAsset, maker, maker_payout); //pay counterparty
        transferTo(direction.srcAsset, bonder, bonder_fee_payout); //pay bonder fee
        transferTo(funding.bondAsset, bonder, funding.bondAmount); //give back bonder his bond

        //event
        emit MatchConfirmed(bonder, direction, srcIndex, fee);
    }

    function cancelOrder(
        OrderDirection memory direction,
        uint32 orderIndex
    ) public nonReentrant{
        Order storage order= book[direction.dstLzc][direction.dstAsset][direction.srcAsset].orders[orderIndex];
        address sender=order.sender;
        //check
        require(msg.sender==sender, "!onlySender");
        require(order.settled < order.funding.srcQuantity, "!alreadyMatched");

        //action
        order.funding.srcQuantity = 0;
        order.funding.dstQuantity = 0;

        //event
        emit OrderCancelled(sender, direction, orderIndex);
    }

    function unwindMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bool isUnwrap
    ) public nonReentrant{
        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];
        Order storage _order= selected_pair.orders[srcIndex];
        Match storage _match=selected_pair.matches[srcIndex];

        //check
        require(msg.sender == bytes32ToAddress(_match.maker), "!onlyMaker");
        require(!_match.finalized && !_match.challenged, "!Match is closed");

        //updates
        _match.finalized = true;

        if (isUnwrap) {
            //Unwrap the token and transfer srcQuantity of the native gas token to the user
            IWrapped wrappedToken = IWrapped(direction.srcAsset);
            wrappedToken.withdraw(_order.funding.srcQuantity);
            // //send the gas token
            (bool sent,) = _order.sender.call{value: _order.funding.srcQuantity}("");
            require(sent, "!WrappedTokenTransfer");
        }

        else {
            transferTo(direction.srcAsset, _order.sender, _order.funding.srcQuantity); //refund user
        }
        
        //transfer
        transferTo(_order.funding.bondAsset, _match.bonder, _order.funding.bondAmount); //give back bonder his bond
        
        _order.funding.srcQuantity = 0;

        //emit
        emit MatchUnwound(_match.bonder, direction, srcIndex);
    }



    //LayerZero Functions
    event MessageSent(bytes message, uint32 dstEid);      // @notice Emitted when a challenge is sent on source chain to dest chain (src -> dst).
    event ReturnMessageSent(string message, uint32 dstEid);     // @notice Emitted when a challenge is judges on the dest chain (src -> dst).
    event MessageReceived(string message, uint32 senderEid, bytes32 sender);     // @notice Emitted when a message is received from another chain.

    //Challenge Pattern: A->B->A

    function decodeMessage(bytes calldata encodedMessage) public pure returns (Payload memory message, uint16 msgType, uint256 extraOptionsStart, uint256 extraOptionsLength) {
        extraOptionsStart = 256;  // Starting offset after _message, _msgType, and extraOptionsLength
        Payload memory _message;
        uint16 _msgType;

        // Decode the first part of the message
        (_message, _msgType, extraOptionsLength) = abi.decode(encodedMessage, (Payload, uint16, uint256));

        // // Slice out _extraReturnOptions
        // bytes memory _extraReturnOptions = abi.decode(encodedMessage[extraOptionsStart:extraOptionsStart + extraOptionsLength], (bytes));
        
        return (_message, _msgType, extraOptionsStart, extraOptionsLength);
    }
    
    /**
     * @notice Sends a message to a specified destination chain.
     * @param direction._dstEid Destination endpoint ID for the message.
     * @param _extraSendOptions Options for sending the message, such as gas settings.
     * @param _extraReturnOptions Additional options for the return message.
     */
    function challengeMatch(
        OrderDirection memory direction,
        uint32 srcIndex,
        bytes calldata _extraSendOptions, // gas settings for A -> B
        bytes calldata _extraReturnOptions // gas settings for B -> A
    ) external payable {
        //loads
        Pair storage selected_pair=book[direction.dstLzc][direction.dstAsset][direction.srcAsset];
        Order storage _order= selected_pair.orders[srcIndex];
        Match storage _match=selected_pair.matches[srcIndex];
        
        //checks
        require(!_match.finalized && !_match.challenged, "!MatchClosed");
        if (msg.sender != _match.bonder) {
            require(block.number > (_match.blockNumber+_order.expiration.challengeOffset), "!challengeOffse");
        }
        //lz variables
        uint16 _msgType = 2; //SEND_ABA
        uint32 _dstEid = direction.dstLzc;
        uint256 extraOptionsLength = _extraReturnOptions.length;
        bytes memory options = combineOptions(_dstEid, _msgType, _extraSendOptions);


        //encode packet
        Payload memory newPayload = Payload({
            challenger: msg.sender,
            srcToken: direction.srcAsset,
            dstToken: direction.dstAsset,
            srcIndex: srcIndex,
            target: _match.target,
            counterparty: _match.maker,
            minAmount: _order.funding.dstQuantity,
            status: 0 //0 means undecided, 1 means challenge is true and succeeded, 2 means challenge failed
        });

        bytes memory lzPacket=abi.encode(newPayload, _msgType, extraOptionsLength, _extraReturnOptions, extraOptionsLength);
        
        //Layer-zero send

        _lzSend(
            _dstEid,
            lzPacket,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender) 
        );

        //state updates
        _match.challenged=true;
        //events
        emit MessageSent(lzPacket, _dstEid);
        //emit ChallengeRaised(msg.sender, direction.srcAsset, direction.dstAsset, direction.dstLzc, srcIndex, _match.bonder, _match.dstIndex);

    }

    /**
     * @notice Internal function to handle receiving messages from another chain.
     * @dev Decodes and processes the received message based on its type.
     * @param _origin Data about the origin of the received message.
     * @param _guid Globally unique identifier of the message.
     * @param _packet The received message content.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _packet,
        address,  // Executor address as specified by the OApp.
        bytes calldata  // Any extra data or options to trigger on receipt.
    ) internal override {
        //if message types == 2. Means B leg of ABA contract will respons, if message type == 1 means last leg of ABA, contract will just recieve. 

        (Payload memory _payload, uint16 _msgType, uint256 extraOptionsStart, uint256 extraOptionsLength) = decodeMessage(_packet);
        uint32 makerEid=_origin.srcEid;
        
        if (_msgType == 2) {


            Pair storage selected_pair=book[makerEid][addressToBytes32(_payload.srcToken)][bytes32ToAddress(_payload.dstToken)];
            uint _receipt=selected_pair.receipts[_payload.srcIndex][_payload.target];

            if ((_receipt >=  _payload.minAmount)) {
                _payload.status=2;
            }
            else {
                _payload.status=1;
            }


            //send back the payload
            bytes memory _options = combineOptions(makerEid, 1, _packet[extraOptionsStart:extraOptionsStart + extraOptionsLength]);
            _lzSend(
                makerEid,
                abi.encode(_payload, 1),
                _options,
                MessagingFee(msg.value, 0),
                payable(address(this)) 
            );
        }
                    
        else {
            Pair storage selected_pair=book[srcLzc][_payload.dstToken][_payload.srcToken];
            Order storage _order= selected_pair.orders[_payload.srcIndex];
            Match storage _match=selected_pair.matches[_payload.srcIndex];
            
            address bonder =_match.bonder;

            if (_payload.status==1) {
                //taker was NOT paid out. Challenge is true. Give funds from gaurentoor to challenger + tithe, + return funds to user
                transferTo(_payload.srcToken, _order.sender, _order.funding.srcQuantity); //refund user
                transferTo(_order.funding.bondAsset, _payload.challenger, (_order.funding.bondAmount*9)/10); //pay collateral
                transferTo(_order.funding.bondAsset, owner(), (_order.funding.bondAmount)/10); //pay collateral tithe

                emit ChallengeResult(true);
            }
            else {
                //transfer
                transferTo(_payload.srcToken, bytes32ToAddress(_match.maker), applyFee(_order.funding.srcQuantity, _order.funding.bondFee)); //pay counterparty
                transferTo(_payload.srcToken, bonder, bondFee(_order.funding.srcQuantity, _order.funding.bondFee)); //pay bonder fee
                transferTo(_order.funding.bondAsset, bonder, _order.funding.bondAmount); //give back bonder his bond

                //event
                emit ChallengeResult(false);
            }
            
            _match.finalized=true; 


        }

    }

    
    //Transfer Functions
    function transferFrom(address tkn, address from, uint amount) internal {
        SafeERC20.safeTransferFrom(IERC20(tkn), from, address(this),  amount);
    }

    function transferTo(address tkn, address to, uint amount) internal {
        SafeERC20.safeTransfer(IERC20(tkn), to, amount);
    }

    //Fee Functions
    function bondFee(uint number, uint _fee) public pure returns (uint) {
        return (_fee*number)/BASIS_POINTS;
    }
    function applyFee(uint number, uint _fee) public pure returns (uint) {
        return number-((_fee*number)/BASIS_POINTS);
    }
    function bytes32ToAddress(bytes32 _bytes) internal pure returns (address addr) {
        require(_bytes != bytes32(0), "Invalid address");
        addr = address(uint160(uint256(_bytes)));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    // Receive function to accept Ether
    receive() external payable {}

}