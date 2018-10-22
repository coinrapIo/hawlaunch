pragma solidity ^0.4.24;

import "ds-roles/roles.sol";
import "ds-token/token.sol";
import "./Base.sol";
import "./CoinRapGatewayInterface.sol";
import "./Set.sol";

contract EventfulMarket{
    event LogOfferUpdate(uint id, uint oldDestAmnt, uint destAmnt, uint rngMin, uint rngMax);

    event LogMake(
        uint indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken         src,
        DSToken         dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );

    event LogTake(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken         src,
        DSToken         dest,
        address         taker,
        uint            actualAmnt,
        uint            fee,
        uint64          timestamp
    );

    event LogKill(
        uint    indexed id,
        bytes32 indexed pair,
        address indexed maker,
        DSToken         src,
        DSToken         dest,
        uint            srcAmnt,
        uint            destAmnt,
        uint64          timestamp
    );
}

contract C2CMkt is EventfulMarket, Base, DSAuth
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
    address public gateway_cntrt;
    bool locked;
    uint public currRemit = 5 * 10 ** 17;
    uint8 public currFeeBps = 10;
    mapping(uint => OfferInfo) public offers;
    mapping(address => SetLib.Set) internal ownerOffers;
    mapping(address => bool) public listTokens;
    //token:balance, hold by offer owner
    mapping(address => uint256) public balanceInOrder;
    bool public enableMake = true;
    // sha3(token,address) => bool
    mapping(bytes32 => bool) withdrawAddresses;

    constructor(address admin, uint startsWith) DSAuth() public
    {
        require(admin != address(0x0));
        lastOfferId = startsWith; //0x3e8; //starts with 1000
        listTokens[ETH_TOKEN_ADDRESS] = true;
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
        DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, 
        address owner, uint min, uint max, bool hasCode,
        uint prepay, uint accumEther)
    {
        OfferInfo memory offer = offers[id];
        src = offer.src;
        srcAmnt = offer.srcAmnt;
        dest = offer.dest;
        destAmnt = offer.destAmnt;
        owner = offer.owner;
        min = offer.rngMin;
        max = offer.rngMax;
        hasCode = (offer.code>uint16(0));
        prepay = offer.prepay;
        accumEther = offer.accumTradeAmnt;
    }

    function isListPair(DSToken src, DSToken dest) public view returns(bool)
    {
        return listTokens[src] && listTokens[dest] && (src == ETH_TOKEN_ADDRESS || dest == ETH_TOKEN_ADDRESS);
    }

    modifier isOwner(uint id)
    {
        require(isActive(id), "the offer is not exists or inactivation!");
        require(getOwner(id) == msg.sender, "the offer is not own by caller");
        _;
    }

    modifier canMake(DSToken src, DSToken dest)
    {
        require(isListPair(src, dest) && enableMake, "the tokens are not listed!");
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

    function update(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) public isOwner(id) returns(bool)
    {
        require(code>=0 && code < 9999, "incorrect code argument.");
        require((rngMin > 0 && rngMin <= rngMax && rngMax <= destAmnt), "incorrect range min~max arguments.");
        OfferInfo memory offer = offers[id];
        uint rate = calcWadRate(offer.srcAmnt, destAmnt, getDecimalsSafe(offer.src));
        require(offer.srcAmnt == calcSrcQty(destAmnt, getDecimalsSafe(offer.src), getDecimalsSafe(offer.dest), rate));
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

    function cancel(uint id) public isOwner(id) returns(uint refund, uint fee)
    {
        OfferInfo memory offer = offers[id];
        require(offers[id].srcAmnt > 0, "balance wrong!");
        uint cntrtBefore = getBalance(offer.src, this);
        uint makerBefore = getBalance(offer.src, offer.owner);
        (refund, fee) = _cancel(id);
        uint cntrtAfter = getBalance(offer.src, this);
        uint makerAfter = getBalance(offer.src, offer.owner);
        require(add(cntrtAfter, refund) == cntrtBefore, "src balance wrong(contract)");
        require(add(makerBefore, refund) == makerAfter, "src balance wrong(maker)");
    }

    function _cancel(uint id) internal synchronized returns(uint refund, uint fee)
    {

        OfferInfo memory offer = offers[id];
        //refund prepay and balance of offer, if the offer.src is ether.
        refund = (offer.src == ETH_TOKEN_ADDRESS) ? add(offers[id].srcAmnt, offers[id].prepay) : offers[id].srcAmnt;
        fee = offer.prepay;

        if (offer.src == ETH_TOKEN_ADDRESS)
        {
            offer.owner.transfer(refund);
        }
        else
        {
            require(offer.src.transfer(offer.owner, refund), "transfer to offer owner failed!");   
        }
        balanceInOrder[offer.src] = sub(balanceInOrder[offer.src], refund);
        // offers[id].srcAmnt = 0;
        // offers[id].prepay = 0;

        require(ownerOffers[offer.owner].remove(id), "remove owner offer failed!");
        if (getOfferCnt(offer.owner) == 0)
        {
            delete ownerOffers[offer.owner];
        }
        delete offers[id];
        
        bytes32 pair = keccak256(abi.encodePacked(offer.src, offer.dest));
        emit LogKill(id, pair, msg.sender, offer.src, offer.dest, offer.srcAmnt, offer.destAmnt, uint64(block.timestamp));
    }

    function _logTake(uint id, DSToken src, DSToken dest, address maker, address taker, uint actual_amnt, uint fee) internal
    {
        bytes32 pair = keccak256(abi.encodePacked(src, dest));
        emit LogTake(id, pair, maker, src, dest, taker, actual_amnt, fee, uint64(block.timestamp));
    }

    function _takeOffer(address taker, uint id, DSToken tkDstTkn, uint amnt, uint srcAmnt) 
        internal synchronized returns (uint actualAmnt, uint fee)
    {
        fee = 0;
        offers[id].srcAmnt = sub(offers[id].srcAmnt, srcAmnt);
        offers[id].destAmnt = sub(offers[id].destAmnt, amnt);
        balanceInOrder[offers[id].src] = sub(balanceInOrder[offers[id].src], srcAmnt);
        uint accum_amnt;
        if (tkDstTkn != ETH_TOKEN_ADDRESS)
        {
            // maker's view: eth(src) -> token(dest)
            if (offers[id].accumTradeAmnt >= offers[id].remit)
            {
                // srcAmnt * feeBps / 10000
                fee = wdiv(mul(srcAmnt, offers[id].feeBps), WAD_BPS);
                offers[id].prepay = sub(offers[id].prepay, fee);
                balanceInOrder[offers[id].src] = sub(balanceInOrder[offers[id].src], fee);
            }
            else
            {
                accum_amnt = add(offers[id].accumTradeAmnt, srcAmnt);
                if ( accum_amnt > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt, offers[id].remit), offers[id].feeBps), WAD_BPS);
                    offers[id].prepay = sub(offers[id].prepay, fee);
                    balanceInOrder[offers[id].src] = sub(balanceInOrder[offers[id].src], fee);
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
                accum_amnt = add(offers[id].accumTradeAmnt, amnt);
                if ( accum_amnt > offers[id].remit)
                {
                    fee = wdiv(mul(sub(accum_amnt, offers[id].remit), offers[id].feeBps), WAD_BPS);
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
            if (getOfferCnt(offers[id].owner) == 0)
            {
                delete ownerOffers[offers[id].owner];
            }
            delete offers[id];

        }
        return (srcAmnt, fee);
    }


    function make(address maker, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code)
        public canMake(src, dest) payable returns (uint id)
    {
        // TODO: 仅用于单元测试。
        // require(msg.sender == gateway_cntrt);
        require((code>=0 && code < 9999), "incorrect code argument.");
        
        getDecimalsSafe(src);
        getDecimalsSafe(dest);
        require((src == ETH_TOKEN_ADDRESS || msg.value == 0),"incorrect payable arguments!");
        uint prepay = 0;
        if (src == ETH_TOKEN_ADDRESS)
        {
            prepay = (currRemit >= srcAmnt) ? 0 : wdiv(mul(sub(srcAmnt, currRemit), currFeeBps), WAD_BPS);
            require(msg.value - srcAmnt == prepay, "argument value incorrect.(srcAmnt, prepay)");
        }
         
        uint rate = calcWadRate(srcAmnt, destAmnt, getDecimalsSafe(src));
        require(srcAmnt == calcSrcQty(destAmnt, getDecimalsSafe(src), getDecimalsSafe(dest), rate));
        id = _makeOffer(maker, src, srcAmnt, dest, destAmnt, rngMin, rngMax, code, prepay);
    }

    function take(address taker, uint id, DSToken tkDstTkn, uint destAmnt, uint wad_min_rate) 
        public payable returns (uint actualAmnt, uint fee)
    {
        // require(msg.sender == gateway_cntrt);
        require((tkDstTkn == ETH_TOKEN_ADDRESS || msg.value == 0), "The token of pay for or amount incorrect.");
        OfferInfo memory offer = offers[id];
        uint amnt = (tkDstTkn == ETH_TOKEN_ADDRESS) ? msg.value : destAmnt;
        // rate settings by offer owner.
        uint rate = calcWadRate(offer.srcAmnt, offer.destAmnt, getDecimalsSafe(offer.src)); 
        require(wad_min_rate <= rate, "the rate(taker expect) too high");
        uint srcAmnt = calcSrcQty(amnt, getDecimalsSafe(offer.src), getDecimalsSafe(offer.dest), rate);
        require(srcAmnt > 0 && srcAmnt <= getBalance(offer.src, this), "rate settings incorrect or contract balance insufficient");

        (actualAmnt, fee) = _takeOffer(taker, id, tkDstTkn, amnt, srcAmnt);

        _logTake(id, offer.src, offer.dest, offer.owner, taker, actualAmnt, fee);
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
        balanceInOrder[src] = add(balanceInOrder[src], srcAmnt);
        if (src == ETH_TOKEN_ADDRESS && prepayFee > 0)
        {
            balanceInOrder[src] = add(balanceInOrder[src], prepayFee);
        }
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
            (, src_amnt[i], , dest_amnt[i], , , , , prepay[i],accum[i]) = getOffer(ids[i]);
        }
        return (src_amnt, dest_amnt,prepay, accum);
    }
    

    function getOfferCnt(address owner) public view returns(uint cnt)
    {
        cnt = ownerOffers[owner].size();
    }
    
    function enabled() public view returns(bool)
    {
        return enableMake;
    }

    /**
     * admin ops.
     */
    event logEnable(address caller, bool enableMake);
    function setEnabled(bool _enableMake) public auth
    {
        require(_enableMake != enableMake);
        enableMake = _enableMake;
        emit logEnable(msg.sender, enableMake);
    }

    event logSetToken(address caller, DSToken token, bool enable);
    function setToken(DSToken token, bool enable) public auth
    {
        require(gateway_cntrt != address(0x00));
        require((enable && !listTokens[token]) || (!enable && listTokens[token]) , "token enable status wrong!");
        listTokens[token] = enable;
        emit logSetToken(msg.sender, token, enable);
    }

    function setCoinRapGateway(address gateway) public auth
    {
        require(gateway != address(0x00));
        gateway_cntrt = gateway;
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

    event WithdrawAddressApproved(DSToken token, address addr, bool approve);
    function approvedWithdrawAddress(DSToken token, address addr, bool approve) public auth
    {
        withdrawAddresses[keccak256(abi.encodePacked(token,addr))] = approve;
        emit WithdrawAddressApproved(token, addr, approve);
    }

    event TokenWithdraw(DSToken token, uint amnt, address receiver);
    function withrawToken(DSToken token, uint amnt, address receiver) external auth
    {
        require(withdrawAddresses[keccak256(abi.encodePacked(token,receiver))]);
        uint balance = getBalance(token, address(this));
        uint inOrder = balanceInOrder[token];
        require(amnt <= balance - inOrder);
        if(token == ETH_TOKEN_ADDRESS)
        {
            receiver.transfer(amnt);
        }
        else
        {
            require(token.transfer(receiver, amnt));
        }
        emit TokenWithdraw(token, amnt, receiver);
    }

}