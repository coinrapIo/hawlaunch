pragma solidity ^0.4.24;

import "ds-token/token.sol";
import "ds-auth/auth.sol";
import "./OfferInterface.sol";
import "./Set.sol";
import "./Base.sol";

contract OfferData is OfferInterface, Base, DSAuth
{
    using SetLib for SetLib.Set;

    struct OfferInfo
    {
        DSToken         src;
        uint            srcAmnt;
        DSToken         dest;
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
    mapping(uint=>OfferInfo) public offers;
    mapping(address => SetLib.Set) ownerOffers;
    address public c2c;

    constructor(uint startWith) public DSAuth()
    {
        lastOfferId = startWith;
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

    function isActive(uint id) public view returns (bool active)
    {
        return offers[id].timestamp > 0;
    }

    function getOwner(uint id) public view returns (address)
    {
        return offers[id].owner;
    }

    function getOffer(uint id) public view returns(
        DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, 
        address owner, uint min, uint max, bool has_code,
        uint prepay, uint accum_eth)
    {
        OfferInfo memory offer = offers[id];
        src = offer.src;
        src_amnt = offer.srcAmnt;
        dest = offer.dest;
        dest_amnt = offer.destAmnt;
        owner = offer.owner;
        min = offer.rngMin;
        max = offer.rngMax;
        has_code = (offer.code>uint16(0));
        prepay = offer.prepay;
        accum_eth = offer.accumTradeAmnt;
        // timestamp = offer.timestamp;
        // remit = offer.remit;
        // bps = offer.feeBps;
    }

    function check_rate_and_qty(DSToken src, uint src_amnt, DSToken dest, uint dest_amnt) internal returns(bool)
    {
        uint rate = calcWadRate(src_amnt, dest_amnt, getDecimalsSafe(src));
        require(src_amnt == calcSrcQty(dest_amnt, getDecimalsSafe(src), getDecimalsSafe(dest), rate));
        return true;
    }

    function make_offer(
        address maker, 
        DSToken src, 
        uint src_amnt, 
        DSToken dest, 
        uint dest_amnt, 
        uint rng_min, 
        uint rng_max, 
        uint16 code, 
        uint prepay,
        uint remit,
        uint8 bps
        ) public returns (uint id)
    {
        require(msg.sender == c2c);
        require(check_rate_and_qty(src, src_amnt, dest, dest_amnt));
        OfferInfo memory offer;
        offer.src = src;
        offer.srcAmnt = src_amnt;
        offer.dest = dest;
        offer.destAmnt = dest_amnt;
        offer.rngMin = rng_min;
        offer.rngMax = rng_max;
        offer.code = code;
        offer.owner = maker;
        offer.timestamp = uint64(block.timestamp);
        offer.accumTradeAmnt = 0;
        offer.prepay = prepay;
        offer.feeBps = bps;
        offer.remit = remit;
        id = persist_offer(offer);
    }

    function persist_offer(OfferInfo offer) internal synchronized returns(uint id)
    {
        id = _nextId();
        
        offers[id] = offer;
        require(ownerOffers[offer.owner].add(id), "insert owner offer failed.");
    }
    
    function take_offer(uint id, DSToken dest, uint amnt, uint srcAmnt) 
        public synchronized returns (uint actualAmnt, uint fee, uint ownerAmntBySell, bool full_filled)
    {
        require(msg.sender == c2c);
        fee = 0;
        ownerAmntBySell = 0;
        offers[id].srcAmnt = sub(offers[id].srcAmnt, srcAmnt);
        offers[id].destAmnt = sub(offers[id].destAmnt, amnt);
        
        //accumlate ether amount(include current trade)
        uint accum_amnt;
        if (offers[id].src == ETH_TOKEN_ADDRESS)
        {
            // maker's view: eth(src) -> token(dest)
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // srcAmnt * feeBps / 10000
                fee = wdiv(mul(srcAmnt, offers[id].feeBps), WAD_BPS);
                offers[id].prepay = sub(offers[id].prepay, fee);
            }
            else
            {
                accum_amnt = add(offers[id].accumTradeAmnt, srcAmnt);
                if ( accum_amnt > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt, offers[id].remit), offers[id].feeBps), WAD_BPS);
                    offers[id].prepay = sub(offers[id].prepay, fee);
                    // balanceInOrder[offers[id].src] = sub(balanceInOrder[offers[id].src], fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, srcAmnt);
            // require(tkDstTkn.transfer(offers[id].owner, amnt), "transfer to offer's owner failed!");
            // taker.transfer(srcAmnt);
        }
        else
        {
            // maker's view: token(src) -> eth(dest)
            ownerAmntBySell = amnt;
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // amnt * feeBps / 10000
                fee = wdiv(mul(amnt, offers[id].feeBps), WAD_BPS);
                ownerAmntBySell = sub(amnt, fee);
            }
            else
            {
                accum_amnt = add(offers[id].accumTradeAmnt, amnt);
                if ( accum_amnt > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt, offers[id].remit), offers[id].feeBps), WAD_BPS);
                    ownerAmntBySell = sub(amnt, fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, amnt);
            // require(offers[id].src.transfer(taker, srcAmnt), "transfer to taker failed!~");
            // offers[id].owner.transfer(offerOwnerAmnt);
        }
        
        if(offers[id].srcAmnt == 0)
        {
            require(ownerOffers[offers[id].owner].remove(id), "remove owner offer failed");
            if (getOfferCnt(offers[id].owner) == 0)
            {
                delete ownerOffers[offers[id].owner];
            }
            full_filled = true;
            delete offers[id];

        }
        return (srcAmnt, fee, ownerAmntBySell, full_filled);
    }
    
    function kill_offer(uint id) public returns(uint src_amnt, uint fee)
    {
        require(msg.sender == c2c);
        OfferInfo memory offer = offers[id];
        src_amnt = offer.srcAmnt;
        fee = offer.prepay;
        require(ownerOffers[offer.owner].remove(id), "remove owner offer failed!");
        if (getOfferCnt(offer.owner) == 0)
        {
            delete ownerOffers[offer.owner];
        }
        delete offers[id];
    }

    function update_offer(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) public returns(uint old_dest_amnt)
    {
        require(msg.sender == c2c);
        require(check_rate_and_qty(offers[id].src, offers[id].srcAmnt, offers[id].dest, destAmnt));
        old_dest_amnt = offers[id].destAmnt;
        if (offers[id].destAmnt != destAmnt)
        {
            offers[id].destAmnt = destAmnt;
        }
        if (offers[id].rngMin != rngMin)
        {
            offers[id].rngMin = rngMin;
        }
        if (offers[id].rngMax != rngMax)
        {
            offers[id].rngMax = rngMax;
        }
        if (offers[id].code != code)
        {
            offers[id].code = code;
        }
    }

    function getOfferCode(uint id, bytes32 msghash, uint8 v, bytes32 r, bytes32 s)  public view returns(uint16 code)
    {
        code = 0;
        if (isActive(id))
        {
            // bytes32 h = keccak256("\x19Ethereum Signed Message:\n32", msghash);
            OfferInfo memory offer = offers[id];
            if(ecrecover(msghash, v, r, s)==offer.owner)
            {
                code = offer.code;
            }
        }
    }

    event SetC2CMkt(address caller, address c2c);
    function set_c2c_mkt(address _c2c) public auth
    {
        require(_c2c != address(0x00));
        c2c = _c2c;
        emit SetC2CMkt(msg.sender, c2c);
    }

    function getOfferCnt(address owner) public view returns(uint cnt)
    {
        cnt = ownerOffers[owner].size();
    }

    function getOffers(address owner) public view returns(uint[])
    {
        uint[] memory keys = ownerOffers[owner].getKeys();
        return keys;
    }

    function getOfferByIds(uint[] ids) public view returns(
        uint[], uint[], uint[], uint[]
        )
    {
        // DSToken[] memory src = new DSToken[](ids.length);
        uint[] memory src_amnt = new uint[](ids.length);
        // DSToken[] memory dest = new DSToken[](ids.length);
        uint[] memory dest_amnt = new uint[](ids.length);
        // address[] memory owner = new address[](ids.length);
        // uint[] memory rng_min = new uint[](ids.length);
        // uint[] memory rng_max = new uint[](ids.length);
        // bool[] memory has_code = new bool[](ids.length);
        // uint16[] memory code = new uint16[](ids.length);
        uint[] memory prepay = new uint[](ids.length);
        uint[] memory accum = new uint[](ids.length);

        for(uint i = 0; i < ids.length; i++)
        {
            OfferInfo offer = offers[ids[i]];
            src_amnt[i] = offer.srcAmnt;
            dest_amnt[i] = offer.destAmnt;
            prepay[i] = offer.prepay;
            accum[i] = offer.accumTradeAmnt;
        }
        return (src_amnt, dest_amnt,prepay, accum);
    }

}