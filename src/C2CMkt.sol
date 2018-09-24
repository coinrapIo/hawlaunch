pragma solidity ^0.4.24;

import "ds-roles/roles.sol";
import "ds-token/token.sol";
import "./Base.sol";
import "./CoinRapGatewayInterface.sol";
import "./Set.sol";

contract EventfulMarket{
    event LogOfferUpdate(uint id, uint oldDestAmnt, uint destAmnt, uint rngMin, uint rngMax);
    event LogTrade(uint offer_id, address indexed taker, uint srcAmnt, address indexed src, uint destAmnt, address dest, int16 code);

    event LogMake(
        uint indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken           src,
        DSToken           dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );

    event LogTake(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken           src,
        DSToken           dest,
        address         taker,
        uint            destAmnt,
        uint            srcAmnt,
        uint64          timestamp
    );

    event LogKill(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken           src,
        DSToken           dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );
}

contract C2CMkt is EventfulMarket, Base, DSRoles
{
    using SetLib for SetLib.Set;

    struct OfferInfo
    {
        DSToken           src;
        uint            srcAmnt;
        DSToken           dest;
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
    address public gateway_cntrt;
    bool locked;
    uint internal currRemit = 5 * 10 ** 17;
    uint8 internal currFeeBps = 10;
    mapping(uint => OfferInfo) public offers;
    mapping(address => SetLib.Set) internal ownerOffers;
    mapping(address => bool) public listTokens;
    // mapping(address => uint) public nonces;

    constructor(address admin, uint startsWith) DSAuth() public
    {
        require(admin != address(0x0));
        lastOfferId = startsWith; //0x3e8; //starts with 1000
        listTokens[ETH_TOKEN_ADDRESS] = true;
        setUserRole(msg.sender, root_role, true);
        setUserRole(admin, admin_role, true);

        //mod ops
        setRoleCapability(mod_role, this, bytes4(keccak256("setToken(address,bool)")), true);
    }

    
    function isActive(uint id) public view returns (bool active)
    {
        return offers[id].timestamp > 0;
    }

    function getOwner(uint id) public view returns (address owner)
    {
        return offers[id].owner;
    }

    function getOffer(uint id) public view returns(
        DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, 
        address owner, uint min, uint max, bool hasCode, uint16 code)
    {
        OfferInfo memory offer = offers[id];
        uint16 c = msg.sender == offer.owner ? offer.code : 0;
        return(
            offer.src, offer.srcAmnt, offer.dest, offer.destAmnt,
            offer.owner, offer.rngMin, offer.rngMax, offer.code==0, c
        );
    }

    function isListPair(DSToken src, DSToken dest) public view returns(bool)
    {
        return listTokens[src] && listTokens[dest] && (src == ETH_TOKEN_ADDRESS || dest == ETH_TOKEN_ADDRESS);
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

    modifier canMake(DSToken src, DSToken dest)
    {
        require(isListPair(src, dest), "the tokens are not listed!");
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
        require(code>=0 && code < 9999, "incorrect code argument.");
        require((rngMin > 0 && rngMin <= rngMax && rngMax <= destAmnt), "incorrect range min~max arguments.");
        OfferInfo memory offer = offers[id];
        calcWadRate(offer.srcAmnt, destAmnt);
        return _update(id, destAmnt, rngMin, rngMax, code);

    }

    function _update(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) internal synchronized returns (bool)
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
        uint cntrtBefore = getBalance(offers[id].src, this);
        uint makerBefore = getBalance(offers[id].src, offers[id].owner);
        (refund, fee) = _cancel(id);
        uint cntrtAfter = getBalance(offers[id].src, this);
        uint makerAfter = getBalance(offers[id].src, offers[id].owner);
        require(add(cntrtAfter, refund) == cntrtBefore, "src balance wrong(contract)");
        require(add(makerBefore, refund) == makerAfter, "src balance wrong(maker)");
    }

    function _cancel(uint id) internal synchronized returns(uint refund, uint fee)
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

        require(ownerOffers[offer.owner].remove(id), "remove owner offer failed!");
        delete offers[id];
        
        bytes32 pair = keccak256(abi.encodePacked(offer.src, offer.dest));
        emit LogKill(id, pair, msg.sender, offer.src, offer.dest, offer.srcAmnt, offer.destAmnt, uint64(block.timestamp));
    }

// uint id, DSToken src, DSToken dest, uint dest_amnt, uint wad_min_rate
    function take(address taker, uint id, DSToken tkDstTkn, uint destAmnt, uint wad_min_rate) 
        public payable returns (uint actualAmnt, uint fee)
    {
        require(msg.sender == gateway_cntrt);
        require((tkDstTkn == ETH_TOKEN_ADDRESS || msg.value == 0), "The token of pay for or amount incorrect.");
        OfferInfo memory offer = offers[id];
        uint amnt = (tkDstTkn == ETH_TOKEN_ADDRESS) ? msg.value : destAmnt;
        // rate settings by offer owner.
        uint rate = calcWadRate(offer.srcAmnt, offer.destAmnt); 
        require(wad_min_rate <= rate, "the rate(taker expect) too higher");
        uint srcAmnt = calcSrcQty(amnt, getDecimalsSafe(offer.src), getDecimalsSafe(offer.dest), rate);
        require(srcAmnt > 0 && srcAmnt <= getBalance(offer.src, this), "rate settings incorrect or contract balance insufficient");

        (actualAmnt, fee) = _takeOffer(taker, id, tkDstTkn, amnt, srcAmnt);

        // bytes32 pair = keccak256(abi.encodePacked(offer.src, offer.dest));
        // LogTake(id, pair, offer.owner, offer.src, offer.dest, taker, destAmnt, actualAmnt, uint64(block.timestamp));

    }

    function _takeOffer(address taker, uint id, DSToken tkDstTkn, uint amnt, uint srcAmnt) 
        internal synchronized returns (uint actualAmnt, uint fee)
    {
        require(offers[id].destAmnt >= amnt, "the offer.destAmnt insufficient.");
        fee = 0;
        offers[id].srcAmnt = sub(offers[id].srcAmnt, srcAmnt);
        offers[id].destAmnt = sub(offers[id].destAmnt, amnt);
        if (tkDstTkn != ETH_TOKEN_ADDRESS)
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
                uint accum_amnt = add(offers[id].accumTradeAmnt, srcAmnt);
                if ( accum_amnt > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt, offers[id].remit), offers[id].feeBps), WAD_BPS);
                    offers[id].prepay = sub(offers[id].prepay, fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, srcAmnt);
            require(tkDstTkn.transfer(offers[id].owner, amnt), "transfer to offer's owner failed!");
            taker.transfer(srcAmnt);
        }
        else
        {
            // maker's view: token(src) -> eth(dest)
            uint offerOwnerAmnt = amnt;
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // amnt * feeBps / 10000
                fee = wdiv(mul(amnt, offers[id].feeBps), WAD_BPS);
                offerOwnerAmnt = sub(amnt, fee);
            }
            else
            {
                uint accum_amnt2 = add(offers[id].accumTradeAmnt, amnt);
                if ( accum_amnt2 > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt2, offers[id].remit), offers[id].feeBps), WAD_BPS);
                    offerOwnerAmnt = sub(amnt, fee);
                }
                // else {} //free within the amount of remit.
            }
            offers[id].accumTradeAmnt = add(offers[id].accumTradeAmnt, amnt);
            require(offers[id].src.transfer(taker, srcAmnt), "transfer to taker failed!~");
            offers[id].owner.transfer(offerOwnerAmnt);
        }
        
        if(offers[id].srcAmnt == 0)
        {
            require(ownerOffers[offers[id].owner].remove(id), "remove owner offer failed");
            delete offers[id];

        }
        return (srcAmnt, fee);
    }


    function make(address maker, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code)
        public canMake(src, dest) payable returns (uint id)
    {
        // require(msg.sender == gateway_cntrt);
        require((code>=0 || code < 9999), "incorrect code argument.");
        
        getDecimalsSafe(src);
        getDecimalsSafe(dest);
        require((src == ETH_TOKEN_ADDRESS || msg.value == 0),"incorrect payable arguments!");
        uint prepay = 0;
        if (src == ETH_TOKEN_ADDRESS)
        {
            prepay = wdiv(mul(sub(srcAmnt, currRemit), currFeeBps), WAD_BPS);
            require(msg.value - srcAmnt == prepay, "argument value incorrect.(srcAmnt, prepay)");
        }
         
        calcWadRate(srcAmnt, destAmnt);
        id = _makeOffer(maker, src, srcAmnt, dest, destAmnt, rngMin, rngMax, code, prepay);
    }


    function _makeOffer(address maker, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code, uint prepayFee) 
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
        offer.owner = maker;
        offer.timestamp = uint64(block.timestamp);
        offer.accumTradeAmnt = 0;
        offer.prepay = prepayFee;
        offer.feeBps = currFeeBps;
        offer.remit = currRemit;
        id = _nextId();
        
        offers[id] = offer;
        require(ownerOffers[offer.owner].add(id), "insert owner offer failed.");
        
        bytes32 pair = keccak256(abi.encodePacked(src, dest));
        emit LogMake(id, pair, msg.sender, src, dest, srcAmnt, destAmnt, offer.timestamp);
    }

    event DepositToken(ERC20 token, address from, uint amount);
    function () public payable
    {
        emit DepositToken(ETH_TOKEN_ADDRESS, msg.sender, msg.value);
    }

    function getOffers(address owner) public view returns(uint[])
    {
        uint[] memory keys = ownerOffers[owner].getKeys();
        return keys;
    }

    function getOfferCnt(address owner) public view returns(uint cnt)
    {
        cnt = ownerOffers[owner].size();
    }
    
    function enabled() public view returns(bool)
    {
        return true;
    }


    /**
     * admin ops.
     */
    function setToken(DSToken token, bool enable) public auth
    {
        require(gateway_cntrt != address(0x00));
        require((enable && !listTokens[token]) || (!enable && listTokens[token]) , "token enable status wrong!");
        listTokens[token] = enable;
    }

    function setCoinRapGateway(address gateway) public auth
    {
        require(gateway != address(0x00));
        gateway_cntrt = gateway;
    }


}