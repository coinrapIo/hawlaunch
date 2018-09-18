pragma solidity ^0.4.24;

import "./IERC20.sol";
import "./Base.sol";

contract EventfulMarket{
    event LogOfferUpdate(uint id, uint oldDestAmnt, uint destAmnt, uint rngMin, uint rngMax);
    event LogTrade(uint offer_id, address indexed taker, uint srcAmnt, address indexed src, uint destAmnt, address dest, int16 code);

    event LogMake(
        uint indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20           src,
        IERC20           dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );

    event LogBump(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20           src,
        IERC20           dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );

    event LogTake(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20           src,
        IERC20           dest,
        address         taker,
        uint            destAmnt,
        uint            srcAmnt,
        uint64          timestamp
    );

    event LogKill(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20           src,
        IERC20           dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );
}

contract BaseMarket is EventfulMarket, Base
{

    struct UserBalance
    {
        uint srcBalance;
        uint destBalance;
    }

    struct OfferInfo
    {
        IERC20           src;
        uint            srcAmnt;
        IERC20           dest;
        uint            destAmnt;
        address         owner;
        uint            rngMin;
        uint            rngMax;
        uint16          code;       
        uint64          timestamp;
        /* pre-pay trade fee.(eth->token). It may be returned to maker, if maker cancel the offer.*/
        uint            prepay;
        uint            accumTradeAmnt;
        uint            remit;
        uint8           feeBps;
    }

    uint public lastOfferId;
    bool locked;
    uint internal currRemit;
    uint8 internal currFeeBps;
    mapping(uint => OfferInfo) public offers;
    mapping(address => mapping(uint => bytes32)) public ownerOffers;
    mapping(address => bool) public listTokens;
    // mapping(address => uint) public nonces;


    
    function isActive(uint id) public view returns (bool active)
    {
        return offers[id].timestamp > 0;
    }

    function getOwner(uint id) public view returns (address owner)
    {
        return offers[id].owner;
    }

    function getOffer(uint id) public view returns(
        IERC20 src, uint srcAmnt, IERC20 dest, uint destAmnt, 
        address owner, uint min, uint max, bool hasCode, uint16 code)
    {
        OfferInfo memory offer = offers[id];
        uint16 c = msg.sender == offer.owner ? offer.code : 0;
        return(
            offer.src, offer.srcAmnt, offer.dest, offer.destAmnt,
            offer.owner, offer.rngMin, offer.rngMax, offer.code==0, c
        );
    }

    function isListPair(IERC20 src, IERC20 dest) public view returns(bool)
    {
        return listTokens[src] && listTokens[dest] && (src == ETH_TOKEN_ADDRESS || dest == ETH_TOKEN_ADDRESS);
    }


    modifier canTake(uint id)
    {
        require(isActive(id), "the offer is not exists or inactivation!");
        _;
    }

    modifier canCancel(uint id)
    {
        require(isActive(id), "the offer is not exists or inactivation!");
        require(getOwner(id) == msg.sender, "the offer is not own by caller");
        _;
    }

    modifier canUpdate(uint id)
    {
        require(isActive(id), "the offer is not exists or inactivation!");
        require(getOwner(id) == msg.sender, "the offer is not own by caller");
        _;
    }

    modifier canMake(IERC20 src, IERC20 dest)
    {
        require(listTokens[src], "It is not listed(src)");
        require(listTokens[dest], "It is not listed(dest)");
        require(src == ETH_TOKEN_ADDRESS || dest == ETH_TOKEN_ADDRESS, "The one must be etherum.");
        _;
    }

    modifier synchronized()
    {
        require(!locked, "blocked by locked.");
        locked = true;
        _;
        locked = false;
    }

    function _nextId() internal returns(uint)
    {
        lastOfferId++;
        return lastOfferId;
    }

    function update(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) public canUpdate(id) returns(bool)
    {
        require(destAmnt > 0, "dest amount lte 0 or rate incorrect");
        require((rngMin > 0 && rngMin <= rngMax && rngMax <= destAmnt), "incorrect range min~max arguments.");
        OfferInfo memory offer = offers[id];
        calcWadRate(offer.srcAmnt, destAmnt);
        require(code>=0 || code < 9999, "incorrect code argument.");
        return _update(id, destAmnt, rngMin, rngMax, code);

    }

    function _update(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) internal canUpdate(id) synchronized returns (bool)
    {
        uint oldDestAmnt = offers[id].destAmnt;
        offers[id].destAmnt = destAmnt;
        offers[id].rngMin = rngMin;
        offers[id].rngMax = rngMax;
        offers[id].code = code;
        emit LogOfferUpdate(id, oldDestAmnt, destAmnt, rngMin, rngMax);
        return true;
    }

    function cancel(uint id) public canCancel(id) returns(uint refund, uint fee)
    {
        require(offers[id].srcAmnt > 0, "balance wrong!");
        UserBalance memory cntrtBefore;
        UserBalance memory makerBefore;
        cntrtBefore.srcBalance = getBalance(offers[id].src, this);
        makerBefore.srcBalance = getBalance(offers[id].src, offers[id].owner);
        (refund, fee) = _cancel(id);
        UserBalance memory cntrtAfter;
        UserBalance memory makerAfter;
        cntrtAfter.srcBalance = getBalance(offers[id].src, this);
        makerAfter.srcBalance = getBalance(offers[id].src, offers[id].owner);
        require(add(cntrtAfter.srcBalance, refund) == cntrtBefore.srcBalance, "src balance wrong(contract)");
        require(add(makerBefore.srcBalance, refund) == makerAfter.srcBalance, "src balance wrong(maker)");
    }

    function _cancel(uint id) internal canCancel(id) synchronized returns(uint refund, uint fee)
    {

        OfferInfo memory offer = offers[id];
        refund = offer.srcAmnt;
        fee = offer.prepay;

        if (offer.src == ETH_TOKEN_ADDRESS)
        {
            //refund prepay and balance of offer
            refund = add(offers[id].srcAmnt, offers[id].prepay);
            offer.owner.transfer(refund);
            offers[id].srcAmnt = 0;
            offers[id].prepay = 0;
        }
        else
        {
            refund = offers[id].srcAmnt;
            require(offer.src.transfer(offer.owner, refund), "transfer to offer owner failed!");
            offers[id].srcAmnt = 0;
        }
        delete ownerOffers[offer.owner][id];
        delete offers[id];
        bytes32 pair = keccak256(abi.encodePacked(offer.src, offer.dest));
        emit LogKill(id, pair, msg.sender, offer.src, offer.dest, offer.srcAmnt, offer.destAmnt, uint64(block.timestamp));
    }

    function validateInput(uint id, IERC20 tkDstTkn, uint destAmnt, uint16 code) internal view
    {
        require((tkDstTkn == ETH_TOKEN_ADDRESS || msg.value == 0), "The token of pay for or amount incorrect.");
        
        OfferInfo memory offer = offers[id];
        require(offer.dest == tkDstTkn && (offer.code > 0 && offer.code == code), "The dest token or code is incorrect.");

        uint amnt = (tkDstTkn == ETH_TOKEN_ADDRESS) ? msg.value : destAmnt;
        require(offer.rngMin <= amnt && offer.rngMax >= amnt && amnt <= offer.destAmnt, "take amount does not in range.");
    }

    function take(uint id, IERC20 tkDstTkn, uint destAmnt, uint16 code) public 
        canTake(id) payable returns (uint actualAmnt, uint fee)
    {
        validateInput(id, tkDstTkn, destAmnt, code);
        OfferInfo memory offer = offers[id];
        uint amnt = (tkDstTkn == ETH_TOKEN_ADDRESS) ? msg.value : destAmnt;
        // rate settings by offer owner.
        uint rate = calcWadRate(offer.srcAmnt, offer.destAmnt); 
        uint srcAmnt = calcSrcQty(amnt, getDecimalsSafe(offer.src), getDecimalsSafe(offer.dest), rate);
        require((srcAmnt > 0), "rate settings incorrect.");

        UserBalance memory cntrtBefore;
        cntrtBefore.srcBalance = getBalance(offer.src, this);
        require(cntrtBefore.srcBalance >= srcAmnt, "insufficient funds in contract!");

        UserBalance memory makerBefore;
        UserBalance memory takerBefore;
        makerBefore.destBalance = getBalance(offer.dest, offer.owner);
        takerBefore.srcBalance = getBalance(offer.src, msg.sender);
        takerBefore.destBalance = getBalance(offer.dest, msg.sender);

        if (tkDstTkn != ETH_TOKEN_ADDRESS)
        {
            require(tkDstTkn.transferFrom(msg.sender, this, amnt), "can't transfer token from caller.");
        }

        (actualAmnt, fee) = _takeOffer(id, tkDstTkn, amnt, srcAmnt);

        validAfterTrade(cntrtBefore, makerBefore, takerBefore, offer, amnt, actualAmnt, fee);

    }

    function validAfterTrade(
        UserBalance cntrtBefore, UserBalance makerBefore, UserBalance takerBefore, 
        OfferInfo offer, uint amnt, uint actualAmnt, uint fee) internal view
    {
        UserBalance memory cntrtAfter;
        UserBalance memory makerAfter;
        UserBalance memory takerAfter;
        cntrtAfter.srcBalance = getBalance(offer.src, this);
        makerAfter.destBalance = getBalance(offer.dest, offer.owner);
        takerAfter.srcBalance = getBalance(offer.src, msg.sender);
        takerAfter.destBalance = getBalance(offer.dest, msg.sender);

        require(add(add(cntrtAfter.srcBalance, actualAmnt),fee) == cntrtBefore.srcBalance, "src balance wrong(contract)");
        require(add(add(makerBefore.destBalance, actualAmnt),fee) == makerAfter.destBalance, "dest balance wrong(maker)");
        require(add(takerAfter.destBalance, amnt) == takerBefore.destBalance, "dest balance wrong(taker)");
        require(add(takerBefore.srcBalance, actualAmnt) == takerAfter.srcBalance, "src balance wrong(taker)");
    }

    function _takeOffer(uint id, IERC20 tkDstTkn, uint amnt, uint srcAmnt) internal synchronized returns (uint actualAmnt, uint fee)
    {
        fee = 0;
        offers[id].srcAmnt = sub(offers[id].srcAmnt, srcAmnt);
        offers[id].destAmnt = sub(offers[id].destAmnt, amnt);
        if (tkDstTkn != ETH_TOKEN_ADDRESS)
        {
            // maker's view: eth(src) -> token(dest)
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // srcAmnt * feeBps * 10000 / 10000
                fee = wdiv(mul(srcAmnt, mul(offers[id].feeBps, 10000)), 10000);
                offers[id].prepay = sub(offers[id].prepay, fee);
            }
            else
            {
                if (offers[id].accumTradeAmnt + srcAmnt > offers[id].remit)
                {
                    fee = offers[id].accumTradeAmnt + srcAmnt - offers[id].remit;
                    offers[id].prepay = sub(offers[id].prepay, fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, srcAmnt);
            require(tkDstTkn.transfer(offers[id].owner, amnt), "transfer to offer's owner failed!");
            msg.sender.transfer(srcAmnt);
        }
        else
        {
            // maker's view: token(src) -> eth(dest)
            uint offerOwnerAmnt = amnt;
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // amnt - (amnt * feeBps * 10000) / 1000
                fee = wdiv(mul(amnt, mul(offers[id].feeBps, 10000)), 10000);
                offerOwnerAmnt = sub(amnt, fee);
            }
            else
            {
                if (offers[id].accumTradeAmnt + amnt > offers[id].remit)
                {
                    uint baseAmnt = sub(add(offers[id].accumTradeAmnt, amnt), offers[id].remit);
                    fee = wdiv(mul(baseAmnt, mul(offers[id].feeBps, 10000)), 10000);
                    offerOwnerAmnt = sub(amnt, fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, amnt);
            require(offers[id].src.transfer(msg.sender, srcAmnt), "transfer to caller failed!~");
            offers[id].owner.transfer(offerOwnerAmnt);
        }
        
        if(offers[id].srcAmnt == 0)
        {
            delete ownerOffers[offers[id].owner][id];
            delete offers[id];

        }
        return (srcAmnt, fee);
    }


    function make(IERC20 src, uint srcAmnt, IERC20 dest, uint destAmnt, uint rngMin, uint rngMax, uint prepayFee, uint16 code)
        public canMake payable returns (uint id)
    {
        require(src != IERC20(0x0), "src is empty");
        require(dest != IERC20(0x0), "dest is empty");
        require(src != dest, "There is same symbol in the trade pair?");
        getDecimalsSafe(src);
        getDecimalsSafe(dest);
        require((src == ETH_TOKEN_ADDRESS || msg.value == 0),"incorrect payable arguments!");
        if (src == ETH_TOKEN_ADDRESS)
        {
            require(srcAmnt + prepayFee <= msg.value && prepayFee >= (srcAmnt - currRemit) * currFeeBps, "argument value incorrect.(srcAmnt, prepayFee)");
        }
        else
        {
            require(prepayFee == 0, "incorrect prepay fee");
        }    
        calcWadRate(srcAmnt, getDecimalsSafe(src), destAmnt, getDecimalsSafe(dest));
        require(srcAmnt > 0, "src amount lte 0");
        require(destAmnt > 0, "dest amount lte 0 or rate incorrect");
        require((rngMin > 0 && rngMin <= rngMax && rngMax <= destAmnt), "incorrect range min~max arguments.");
        require((code>=0 || code < 9999), "incorrect code argument.");
        

        UserBalance memory makerBalanceBefore;
        makerBalanceBefore.srcBalance = getBalance(src, msg.sender);
        makerBalanceBefore.destBalance = getBalance(dest, msg.sender);

        if (src == ETH_TOKEN_ADDRESS)
        {
            makerBalanceBefore.srcBalance = add(makerBalanceBefore.srcBalance, msg.value);
        }
        else
        {
            require(src.transferFrom(msg.sender, this, srcAmnt), "can't transfer token from msg.sender");
        }

        id = _makeOffer(src, srcAmnt, dest, destAmnt, rngMin, rngMax, code, prepayFee);
        UserBalance memory userBalanceAfter;
        userBalanceAfter.srcBalance = getBalance(src, msg.sender);
        userBalanceAfter.destBalance = getBalance(dest, msg.sender);
        
        require(add(userBalanceAfter.srcBalance, msg.value) == makerBalanceBefore.srcBalance, "src balance check exception!");
        require(userBalanceAfter.destBalance == makerBalanceBefore.destBalance, "dest balance check exception!");
    }


    function _makeOffer(IERC20 src, uint srcAmnt, IERC20 dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code, uint prepayFee) 
        internal synchronized returns (uint id)
    {
        OfferInfo memory offer;
        offer.src = src;
        offer.srcAmnt = srcAmnt;
        offer.dest = dest;
        offer.destAmnt = destAmnt;
        offer.rngMin = rngMin;
        offer.rngMax = rngMax;
        offer.code = code;
        offer.owner = msg.sender;
        offer.timestamp = uint64(block.timestamp);
        offer.accumTradeAmnt = 0;
        offer.prepay = prepayFee;
        offer.feeBps = currFeeBps;
        offer.remit = currRemit;
        id = _nextId();
        
        offers[id] = offer;
        bytes32 pair = keccak256(abi.encodePacked(offer.src, offer.dest));
        ownerOffers[offer.owner][id] = pair;
        emit LogMake(id, keccak256(abi.encodePacked(src, dest)), msg.sender, src, dest, srcAmnt, destAmnt, offer.timestamp);
    }



    function () public payable
    {

    }

}
