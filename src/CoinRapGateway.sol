pragma solidity ^0.4.24;

import "ds-token/token.sol";
import "ds-auth/auth.sol";
import "./CoinRapGatewayInterface.sol";
import "./C2CMkt.sol";
import "./SwapMkt.sol";
import "./Base.sol";

contract CoinRapGateway is CoinRapGatewayInterface, Base, DSAuth
{
    struct UserBalance
    {
        uint srcBalance;
        uint destBalance;
    }

    struct MakeInput
    {
        DSToken src;
        uint src_amnt;
        DSToken dest;
        uint dest_amnt;
        uint prepay;
        uint rng_min;
        uint rng_max;
        uint16 code;
        bytes ref;
    }

    C2CMkt public c2c;
    SwapMkt public swap;

    event reset_c2c(address curr, address old);
    event reset_swap(address curr, address old);

    constructor() DSAuth() public
    {
    }
    
    function set_c2c_mkt(C2CMkt c2c_mkt) public auth
    {
        require(c2c_mkt != address(0x00), "c2c interface is null");
        emit reset_c2c(c2c, c2c_mkt);
        c2c = c2c_mkt;
    }

    function set_swap_mkt(SwapMkt swap_mkt) public auth
    {
        require(swap_mkt != address(0x00), "c2c interface is null");
        emit reset_swap(swap_mkt, swap);
        swap = swap_mkt;
    }

    function max_gas_price() public view returns(uint)
    {
        if (swap == address(0x00))
        {
            return 0;
        }
        return swap.max_gas_price();
    }

    function cap_in_wei(address user) public view returns(uint)
    {
        if (swap == address(0x00))
        {
            return 0;
        }
        return swap.cap_in_wei(user);
    }

    function token_cap_in_wei(address user, DSToken token) public view returns(uint)
    {
        if (swap == address(0x00))
        {
            return 0;
        }
        return swap.token_cap_in_wei(user, token);

    }
    function enabled(address cntrt_addr) public view returns(bool)
    {
        if (cntrt_addr == address(c2c))
        {
            return c2c.enabled();
        }
        else if (cntrt_addr == address(swap))
        {
            return swap.enabled();
        }
        return false;
    }

    function get_quote(DSToken base, DSToken quote, uint base_amnt) public view returns(uint rate, uint slippage_rate)
    {
        if (swap == address(0x00))
        {
            return (0, 0);
        }
        return swap.get_quote(base, quote, base_amnt);
    }
    
    //DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, uint prepay, uint rng_min, uint rng_max, uint code, bytes ref) external payable returns (uint);
    function make(DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, uint rng_min, uint rng_max, uint16 code) public payable returns(uint id)
    {
        require(src != dest, "There is same symbol in the trade pair?");
        require(src_amnt > 0, "src amount lte 0");
        require(dest_amnt > 0, "dest amount lte 0 or rate incorrect");
        require((rng_min > 0 && rng_min <= rng_max && rng_max <= dest_amnt), "incorrect range min~max arguments.");

        // MakeInput memory mk_npt;
        // mk_npt.src = src;
        // mk_npt.src_amnt = src_amnt;
        // mk_npt.dest = dest;
        // mk_npt.dest_amnt = dest_amnt;
        // mk_npt.prepay = prepay;
        // mk_npt.rng_min = rng_min;
        // mk_npt.rng_max = rng_max;
        // mk_npt.code = code;
        // mk_npt.ref = ref;

        UserBalance memory makerBalanceBefore;
        makerBalanceBefore.srcBalance = getBalance(src, msg.sender);
        makerBalanceBefore.destBalance = getBalance(dest, msg.sender);

        if (src == ETH_TOKEN_ADDRESS)
        {
            makerBalanceBefore.srcBalance = add(makerBalanceBefore.srcBalance, msg.value);
        }
        
        if (src != ETH_TOKEN_ADDRESS)
        {
            require(src.transferFrom(msg.sender, c2c, src_amnt), "can't transfer token from msg.sender");
        }

        id = c2c.make.value(msg.value)(msg.sender, src, src_amnt, dest, dest_amnt, rng_min, rng_max, code);

        UserBalance memory userBalanceAfter;
        userBalanceAfter.srcBalance = getBalance(src, msg.sender);
        userBalanceAfter.destBalance = getBalance(dest, msg.sender);
        
        require(makerBalanceBefore.srcBalance == add(userBalanceAfter.srcBalance, (src == ETH_TOKEN_ADDRESS)?msg.value:src_amnt), "src balance check exception!");
        require(userBalanceAfter.destBalance == makerBalanceBefore.destBalance, "dest balance check exception!");
    }

    // function internal_make(MakeInput mk_npt) internal payable returns(uint id)
    // {
        
    // }

    //此处参数名和意义都是maker的视角
    function take(uint id, DSToken src, DSToken dest, uint dest_amnt, uint wad_min_rate, uint16 code) 
        public payable returns(uint actual_amnt, uint fee)
    {
        // require(validate_take_input(id, src, dest, dest_amnt, wad_min_rate, code), "input incorrect!");
        validate_take_input(id, src, dest, dest_amnt, wad_min_rate, code);
        address o_owner = c2c.getOwner(id);
    
        UserBalance memory cntrt_before;
        UserBalance memory maker_before;
        UserBalance memory taker_before;
        cntrt_before.srcBalance = getBalance(src, c2c);
        maker_before.destBalance = getBalance(dest, o_owner);
        taker_before.srcBalance = getBalance(src, msg.sender);
        taker_before.destBalance = getBalance(dest, msg.sender);

        if (dest != ETH_TOKEN_ADDRESS)
        {
            require(dest.transferFrom(msg.sender, c2c, dest_amnt), "can't transfer token from caller.");
        }

        (actual_amnt, fee) = c2c.take.value(msg.value)(msg.sender, id, dest, dest_amnt, wad_min_rate);
        validate_after_take(src, dest, dest_amnt, o_owner, actual_amnt, fee, taker_before, maker_before, cntrt_before);
    }

    // event LogBalance(address addr, uint before, uint aft, uint amunt, uint fee);

    function validate_after_take(DSToken src, DSToken dest, uint dest_amnt, address o_owner, uint actual_amnt, uint fee, UserBalance taker_before, UserBalance maker_before, UserBalance cntrt_before) internal
    {
        UserBalance memory cntrt_after;
        UserBalance memory maker_after;
        UserBalance memory taker_after;
        cntrt_after.srcBalance = getBalance(src, c2c);
        maker_after.destBalance = getBalance(dest, o_owner);
        taker_after.srcBalance = getBalance(src, msg.sender);
        taker_after.destBalance = getBalance(dest, msg.sender);
        // emit LogBalance(o_owner, maker_before.destBalance, maker_after.destBalance, actual_amnt, fee);
        
        require(add(cntrt_after.srcBalance, actual_amnt) == cntrt_before.srcBalance, "src balance wrong(contract)");
        require(sub(add(maker_before.destBalance, dest_amnt),fee) == maker_after.destBalance, "dest balance wrong(maker)");
        require(add(taker_after.destBalance, dest_amnt) == taker_before.destBalance, "dest balance wrong(taker)");
        require(add(taker_before.srcBalance, actual_amnt) == taker_after.srcBalance, "src balance wrong(taker)");
    }

    function validate_take_input(uint id, DSToken src, DSToken dest, uint dest_amnt, uint wad_min_rate, uint16 code) internal view 
    {
        require(wad_min_rate >0 && c2c.isActive(id));
        
        DSToken o_dest;
        DSToken o_src;
        uint o_dest_amnt;
        address o_owner;
        uint o_min;
        uint o_max;
        (o_src, , o_dest, o_dest_amnt, o_owner, o_min, o_max, , , ) = c2c.getOffer(id);
        require(src == o_src && dest == o_dest);
        uint amnt = (dest == ETH_TOKEN_ADDRESS) ? msg.value : dest_amnt;
        require(amnt >= o_min && amnt <= o_max && amnt <= o_dest_amnt);
    }
    
    function trade(
        DSToken src, uint src_amnt, DSToken dest, address dest_addr, uint max_dest_amnt, uint min_rate, 
        uint rate100, uint sn, bytes32 code
    ) public payable returns (uint)
    {
        if(swap == address(0x00))
        {
            return 0;
        }
        return swap.trade.value(msg.value)(msg.sender, src, src_amnt, dest, dest_addr, max_dest_amnt, min_rate, rate100, sn, code);
    }

}