pragma solidity ^0.4.24;

import "ds-auth/auth.sol";
import "ds-token/token.sol";
import "./Base.sol";
import "./OfferInterface.sol";
import "./CoinRapGatewayInterface.sol";

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

    address public gateway_cntrt;
    uint public currRemit = 5 * 10 ** 17;
    uint8 public currFeeBps = 10;
    bool public enableMake = true;

    OfferInterface offer_data;

    mapping(address => bool) public listTokens;
    //token:balance, hold by offer owner
    mapping(address => uint256) public balanceInOrder;
    // sha3(token,address) => bool
    mapping(bytes32 => bool) withdrawAddresses;

    constructor(OfferInterface _offer_data) DSAuth() public
    {
        require(_offer_data != address(0x00));
        offer_data = _offer_data;
        listTokens[ETH_TOKEN_ADDRESS] = true;
    }


    function isListPair(DSToken src, DSToken dest) public view returns(bool)
    {
        return listTokens[src] && listTokens[dest] && (src == ETH_TOKEN_ADDRESS || dest == ETH_TOKEN_ADDRESS);
    }

    modifier isActive(uint id)
    {
        require(offer_data.isActive(id), "the offer is not exists or inactivation!");
        _;
    }

    function isActiveOffer(uint id) public view returns(bool)
    {
        return offer_data.isActive(id);
    }

    function getOwner(uint id) public view returns (address)
    {
        return offer_data.getOwner(id);
    }

    modifier canMake(DSToken src, DSToken dest)
    {
        require(isListPair(src, dest) && enableMake, "the tokens are not listed!");
        _;
    }

    function getOffer(uint id) public view returns(
        DSToken src, uint srcAmnt,  DSToken dest, uint destAmnt, 
        address owner, uint min, uint max)
    {
        (src, srcAmnt , dest, destAmnt, owner, min, max, , , ) = offer_data.getOffer(id);
    }

    function update(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) public isActive(id) returns(bool)
    {
        require(code>=0 && code < 9999, "incorrect code argument.");
        require((rngMin > 0 && rngMin <= rngMax && rngMax <= destAmnt), "incorrect range min~max arguments.");
        uint old_dest_amnt = offer_data.update_offer(id, destAmnt, rngMin, rngMax, code);
        emit LogOfferUpdate(id, old_dest_amnt, destAmnt, rngMin, rngMax);
        return true;

    }

    struct MyOfferInfo
    {
        DSToken         src;
        uint            srcAmnt;
        DSToken         dest;
        uint            destAmnt;
        address         owner;
        uint            rngMin;
        uint            rngMax;
        bool            hasCode;       
        uint64          timestamp;
        /* pre-pay trade fee.(eth->token). It may be returned to maker, if maker cancel the offer.*/
        uint            prepay;
        uint            accumTradeAmnt;
        uint            remit;
        uint8           bps;
        uint            id;
    }

    function cancel(uint id) public isActive(id) returns(uint refund, uint fee)
    {
        DSToken         src;
        uint            srcAmnt;
        DSToken         dest;
        uint            destAmnt;
        address         owner;
        // uint            rngMin;
        // uint            rngMax;
        // bool            hasCode;
        // uint16          code;       
        // uint64          timestamp;
        /* pre-pay trade fee.(eth->token). It may be returned to maker, if maker cancel the offer.*/
        uint            prepay;
        // uint            accumTradeAmnt;
        // uint            remit;
        // uint8           bps;
        (src, srcAmnt, dest, destAmnt, owner, , , , prepay,) = offer_data.getOffer(id);
        
        require(owner == msg.sender);
        MyOfferInfo memory offer;
        offer.src = src;
        offer.srcAmnt = srcAmnt;
        offer.dest = dest;
        offer.destAmnt = destAmnt;
        offer.owner = owner;
        offer.prepay = prepay;
        offer.id = id;
        return __cancel(offer);
    }

    function __cancel(MyOfferInfo offer) internal returns(uint refund, uint fee)
    {
        require(offer.srcAmnt > 0, "balance wrong!");
        uint cntrtBefore = getBalance(offer.src, this);
        uint makerBefore = getBalance(offer.src, offer.owner);
        (refund, fee) = _cancel(offer.id, offer.src, offer.srcAmnt, offer.dest, offer.destAmnt, offer.owner, offer.prepay);
        uint cntrtAfter = getBalance(offer.src, this);
        uint makerAfter = getBalance(offer.src, offer.owner);
        require(add(cntrtAfter, refund) == cntrtBefore, "src balance wrong(contract)");
        require(add(makerBefore, refund) == makerAfter, "src balance wrong(maker)");
    }

    function _cancel(uint id, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, address owner, uint prepay) internal returns(uint refund, uint fee)
    {

        //refund prepay and balance of offer, if the offer.src is ether.
        refund = (src == ETH_TOKEN_ADDRESS) ? add(srcAmnt, prepay) : srcAmnt;
        fee = prepay;

        if (src == ETH_TOKEN_ADDRESS)
        {
            owner.transfer(refund);
        }
        else
        {
            require(src.transfer(owner, refund), "transfer to offer owner failed!");   
        }
        balanceInOrder[src] = sub(balanceInOrder[src], refund);
        offer_data.kill_offer(id);
        
        bytes32 pair = keccak256(abi.encodePacked(src, dest));
        emit LogKill(id, pair, msg.sender, src, dest, srcAmnt, destAmnt, uint64(block.timestamp));
    }

    function _logTake(uint id, DSToken src, DSToken dest, address maker, address taker, uint actual_amnt, uint fee) internal
    {
        bytes32 pair = keccak256(abi.encodePacked(src, dest));
        emit LogTake(id, pair, maker, src, dest, taker, actual_amnt, fee, uint64(block.timestamp));
    }

    function _takeOffer(address taker, uint id, DSToken src, DSToken tkDstTkn, uint amnt, uint srcAmnt, address owner) 
        internal returns (uint actualAmnt, uint fee)
    {
        bool full_filled = false;
        uint ownerAmntBySell = 0;
        (actualAmnt, fee, ownerAmntBySell, full_filled) = offer_data.take_offer(id, tkDstTkn, amnt, srcAmnt);
        balanceInOrder[src] = sub(balanceInOrder[src], srcAmnt);

        if (tkDstTkn != ETH_TOKEN_ADDRESS)
        {
            // maker's view: eth(src) -> token(dest)
            if(fee > 0)
            {
                balanceInOrder[src] = sub(balanceInOrder[src], fee);
            }
            require(tkDstTkn.transfer(owner, amnt), "transfer to offer's owner failed!");
            taker.transfer(srcAmnt);
        }
        else
        {
            // maker's view: token(src) -> eth(dest)
            require(src.transfer(taker, srcAmnt), "transfer to taker failed!~");
            owner.transfer(ownerAmntBySell);
        }

        return (srcAmnt, fee);
    }


    function make(address maker, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code)
        public canMake(src, dest) payable returns (uint id)
    {
        // TODO: 用于单元测试时，需要注释掉．
        require(msg.sender == gateway_cntrt);
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
        // TODO: 用于单元测试时，需要注释掉．
        require(msg.sender == gateway_cntrt);
        require((tkDstTkn == ETH_TOKEN_ADDRESS || msg.value == 0), "The token of pay for or amount incorrect.");
        address maker;
        DSToken src;
        uint amnt;
        uint srcAmnt;
        (src, maker, amnt, srcAmnt) = check_take(id, tkDstTkn, destAmnt, wad_min_rate);

        (actualAmnt, fee) = _takeOffer(taker, id, src, tkDstTkn, amnt, srcAmnt, maker);

        _logTake(id, src, tkDstTkn, maker, taker, actualAmnt, fee);
    }

    function check_take(uint id, DSToken tkDstTkn, uint destAmnt, uint wad_min_rate) internal returns(DSToken src, address maker, uint amnt, uint srcAmnt)
    {
        // DSToken src;
        uint src_amnt;
        uint dest_amnt;
        // address maker;
        (src, src_amnt, ,dest_amnt, maker , , , , ,) = offer_data.getOffer(id);
        // (src, srcAmnt, dest, destAmnt, owner, , , , prepay, , , , ) = offer_data.getOffer(id);
        amnt = (tkDstTkn == ETH_TOKEN_ADDRESS) ? msg.value : destAmnt;
        // rate settings by offer owner.
        uint rate = calcWadRate(src_amnt, dest_amnt, getDecimalsSafe(src)); 
        require(wad_min_rate <= rate, "the rate(taker expect) too high");
        srcAmnt = calcSrcQty(amnt, getDecimalsSafe(src), getDecimalsSafe(tkDstTkn), rate);
        require(srcAmnt > 0 && srcAmnt <= getBalance(src, this), "rate settings incorrect or contract balance insufficient");
    }


    function _makeOffer(address maker, DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint16 code, uint prepayFee) 
        internal returns (uint id)
    {
        id = offer_data.make_offer(maker, src, srcAmnt, dest, destAmnt, rngMin, rngMax, code, prepayFee, currRemit, currFeeBps);
        balanceInOrder[src] = add(balanceInOrder[src], srcAmnt);
        if (src == ETH_TOKEN_ADDRESS && prepayFee > 0)
        {
            balanceInOrder[src] = add(balanceInOrder[src], prepayFee);
        }
        
        bytes32 pair = keccak256(abi.encodePacked(src, dest));
        emit LogMake(id, pair, msg.sender, src, dest, srcAmnt, destAmnt, uint64(block.timestamp));
    }

    event DepositToken(ERC20 token, address from, uint amount);
    function () public payable
    {
        emit DepositToken(ETH_TOKEN_ADDRESS, msg.sender, msg.value);
    }


    /**
     * admin ops.
     */

    event SetRemit(address caller, uint remit);
    function setRemit(uint remit) public auth
    {
        require(remit != currRemit);
        currRemit = remit;
        emit SetRemit(msg.sender, currRemit);
    }

    event SetFeeBps(address caller, uint bps);
    function setFeeBps(uint bps) public auth
    {
        require(bps != currFeeBps);
        currFeeBps = bps;
        emit SetFeeBps(caller, bps);
    }
    
    function enabled() public view returns(bool)
    {
        return enableMake;
    }

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