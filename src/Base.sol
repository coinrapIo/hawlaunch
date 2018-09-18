pragma solidity ^0.4.24;

import "ds-math/math.sol";
import "./IERC20.sol";

contract Base is DSMath
{
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint  constant internal PRECISION = (10**18);
    uint  constant internal MAX_QTY   = (10**28); // 10B tokens
    uint  constant internal MAX_RATE  = (PRECISION * 10**6); // up to 1M tokens per ETH
    uint  constant internal MAX_DECIMALS = 18;
    uint  constant internal ETH_DECIMALS = 18;
    mapping(address=>uint) internal decimals;


    function getBalance(IERC20 token, address user) public view returns(uint) 
    {
        if (token == ETH_TOKEN_ADDRESS)
            return user.balance;
        else
            return token.balanceOf(user);
    }

    function setDecimals(IERC20 token) internal {
        if (token == ETH_TOKEN_ADDRESS) decimals[token] = ETH_DECIMALS;
        else decimals[token] = token.decimals();
    }

    function getDecimals(IERC20 token) internal view returns(uint) {
        if (token == ETH_TOKEN_ADDRESS) return ETH_DECIMALS; // save storage access
        uint tokenDecimals = decimals[token];
        // technically, there might be token with decimals 0
        // moreover, very possible that old tokens have decimals 0
        // these tokens will just have higher gas fees.
        if(tokenDecimals == 0) return token.decimals();

        return tokenDecimals;
    }

    function calcDstQty(uint srcQty, uint srcDecimals, uint dstDecimals, uint rate) internal pure returns(uint) {
        require(srcQty <= MAX_QTY);
        require(rate <= MAX_RATE);

        if (dstDecimals >= srcDecimals) {
            require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
            return (srcQty * rate * (10**(dstDecimals - srcDecimals))) / PRECISION;
        } else {
            require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
            return (srcQty * rate) / (PRECISION * (10**(srcDecimals - dstDecimals)));
        }
    }

    function calcSrcQty(uint dstQty, uint srcDecimals, uint dstDecimals, uint rate) internal pure returns(uint) {
        require(dstQty <= MAX_QTY);
        require(rate <= MAX_RATE);
        
        //source quantity is rounded up. to avoid dest quantity being too low.
        uint numerator;
        uint denominator;
        if (srcDecimals >= dstDecimals) {
            require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
            numerator = (PRECISION * dstQty * (10**(srcDecimals - dstDecimals)));
            denominator = rate;
        } else {
            require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
            numerator = (PRECISION * dstQty);
            denominator = (rate * (10**(dstDecimals - srcDecimals)));
        }
        return (numerator + denominator - 1) / denominator; //avoid rounding down errors
    }

    function getDecimalsSafe(IERC20 token) internal returns(uint) 
    {
        if (decimals[token] == 0) 
        {
            setDecimals(token);
        }
        return decimals[token];
    }

    function toWad(uint amnt, uint currDecimals) public pure returns(uint wad)
    {
        require(currDecimals <= MAX_DECIMALS);
        wad = mul(amnt, 10 ** (MAX_DECIMALS-currDecimals));
    }

    function calcWadRate(uint srcAmnt, uint destAmnt) public pure returns(uint rate)
    {
        rate = wdiv(destAmnt, srcAmnt);
        require(rate > 0 && rate < MAX_RATE, "incorrect rate!");
        // assume: 1$ = 7￥;
        // 1美分 =  (7 /1) / 10 ^(2-0) = 0.07 人民币(元), srcDecimals(2) >= dstDecimals(0)
        // 1美元 = 7 * 10^(0+2)人民币(分), srcDecimals(0) -> dstDecimals(2)
    
        // if (srcDecimals >= dstDecimals)
        // {
        //     require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
        //     // var _t = div(mul(destAmnt, PRECISION), srcAmnt);
        //     // rate = wdiv(wdiv(destAmnt, srcAmnt), 10**(srcDecimals - dstDecimals)); 
        //     rate = wdiv(wdiv(toWad(destAmnt, dstDecimals), toWad(srcAmnt, srcDecimals)), toWad(10**(srcDecimals - dstDecimals), srcDecimals - dstDecimals));
        // }
        // else
        // {
        //     require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
        //     // var _t = div(mul(destAmnt, PRECISION), srcAmnt);
        //     rate = mul(wdiv(destAmnt, srcAmnt), toWad(10**(dstDecimals - srcDecimals), dstDecimals - srcDecimals)); 
        // }
        // require(rate > 0 && rate < MAX_RATE, "incorrect rate!");

        // uint128 rate1 = 0;
        // uint128 sd = uint128(srcDecimals);
        // uint128 dd = uint128(dstDecimals);
        // uint128 sa = uint128(srcAmnt);
        // uint128 da = uint128(destAmnt);
        // uint128 precision = uint128(10**18);
        // uint128 mr = uint128(128**24);
        // if (sd >= dd)
        // {
        //     require((sd - sd) <= mr);
        //     // var _t = div(mul(destAmnt, PRECISION), srcAmnt);
        //     uint128 decimals2 = uint128(10**(sd - dd));
        //     rate1 = wdiv(wdiv(wmul(da, precision), sa), decimals2); 
        // }
        // else
        // {
        //     require((dd - sd) <= mr);
        //     // var _t = div(mul(destAmnt, PRECISION), srcAmnt);
        //     uint128 decimals3 = uint128(10**(dd - sd));
        //     rate1 = wmul(wdiv(wmul(da, precision), sa), decimals3); 
        // }
        // return uint(rate1);
    }


}