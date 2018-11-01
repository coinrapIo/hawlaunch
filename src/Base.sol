pragma solidity ^0.4.24;

import "ds-token/token.sol";

contract Base
{
    DSToken constant internal ETH_TOKEN_ADDRESS = DSToken(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint  constant internal PRECISION = (10**18);
    uint constant internal MAX_QTY   = (10**28); // 10B tokens
    uint constant internal MAX_RATE  = 10**36; // up to 1M tokens per ETH
    uint constant internal MAX_DECIMALS = 18;
    uint constant internal RATE_PRECISION = MAX_DECIMALS / 2;
    // uint  constant internal ETH_DECIMALS = 18;
    uint constant internal WAD_BPS = (10**22);
    mapping(address=>uint) internal decimals;

    // uint8 root_role = 0;  //power
    // uint8 admin_role = 1;
    // uint8 mod_role = 2;
    // uint8 user_role = 3;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, 10**18), y / 2) / y;
    }

    function getBalance(DSToken token, address user) public view returns(uint) 
    {
        if (token == ETH_TOKEN_ADDRESS)
            return user.balance;
        else
            return token.balanceOf(user);
    }

    function setDecimals(DSToken token) internal 
    {
        if (token == ETH_TOKEN_ADDRESS)
            decimals[token] = MAX_DECIMALS;
        else 
            decimals[token] = token.decimals();
    }

    function getDecimals(DSToken token) internal view returns(uint) {
        if (token == ETH_TOKEN_ADDRESS) return MAX_DECIMALS; // save storage access
        uint tokenDecimals = decimals[token];
        // technically, there might be token with decimals 0
        // moreover, very possible that old tokens have decimals 0
        // these tokens will just have higher gas fees.
        if(tokenDecimals == 0)
            return token.decimals();

        return tokenDecimals;
    }

    // function calcDstQty(uint srcQty, uint srcDecimals, uint dstDecimals, uint rate) internal pure returns(uint) {
    //     require(srcQty <= MAX_QTY);
    //     require(rate <= MAX_RATE);

    //     if (dstDecimals >= srcDecimals) {
    //         require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
    //         return (srcQty * rate * (10**(dstDecimals - srcDecimals))) / MAX_DECIMALS;
    //     } else {
    //         require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
    //         return (srcQty * rate) / (MAX_DECIMALS * (10**(srcDecimals - dstDecimals)));
    //     }
    // }

    function calcSrcQty(uint dstQty, uint srcDecimals, uint dstDecimals, uint rate) public pure returns(uint) 
    {
        require(dstQty <= MAX_QTY);
        require(rate <= MAX_RATE);
        
        //source quantity is rounded up. to avoid dest quantity being too low.
        uint numerator;
        uint denominator;
        if (srcDecimals >= dstDecimals) {
            require(srcDecimals - dstDecimals <= MAX_DECIMALS);
            numerator = mul(dstQty, (10**(srcDecimals - dstDecimals)));
            denominator = mul(rate, (10**(RATE_PRECISION + srcDecimals - dstDecimals)));
            return wdiv(numerator, denominator);
        } else {
            require(dstDecimals - srcDecimals <= MAX_DECIMALS);
            numerator = mul(dstQty, 10**(dstDecimals - srcDecimals));
            denominator = mul(rate, (10**(dstDecimals - srcDecimals + RATE_PRECISION)));
            return wdiv(numerator, denominator);
        }
        // return (numerator + denominator - 1) / denominator; //avoid rounding down errors
    }

    function getDecimalsSafe(DSToken token) public returns(uint) 
    {
        if (decimals[token] == 0) 
        {
            setDecimals(token);
        }
        return decimals[token];
    }

    function calcWadRate(uint srcAmnt, uint destAmnt) public pure returns(uint rate)
    {
        // require(srcDecimals % 2 == 0);
        // uint precision = srcDecimals / 2;
        rate = add(mul(destAmnt, 10 ** RATE_PRECISION), srcAmnt -1) / srcAmnt;
        require(rate > 0 && rate < MAX_RATE, "incorrect rate!");
    }
}