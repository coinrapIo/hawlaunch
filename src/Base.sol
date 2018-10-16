pragma solidity ^0.4.24;

import "ds-math/math.sol";
import "ds-token/token.sol";
// import "erc20/erc20.sol";

contract Base is DSMath
{
    DSToken constant internal ETH_TOKEN_ADDRESS = DSToken(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint  constant internal PRECISION = (10**18);
    uint  constant internal MAX_QTY   = (10**28); // 10B tokens
    uint  constant internal MAX_RATE  = (PRECISION * 10**6); // up to 1M tokens per ETH
    uint  constant internal MAX_DECIMALS = 18;
    uint  constant internal ETH_DECIMALS = 18;
    uint constant internal WAD_BPS = (10**22);
    mapping(address=>uint) internal decimals;

    // uint8 root_role = 0;  //power
    // uint8 admin_role = 1;
    // uint8 mod_role = 2;
    // uint8 user_role = 3;

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
            decimals[token] = ETH_DECIMALS;
        else 
            decimals[token] = token.decimals();
    }

    function getDecimals(DSToken token) internal view returns(uint) {
        if (token == ETH_TOKEN_ADDRESS) return ETH_DECIMALS; // save storage access
        uint tokenDecimals = decimals[token];
        // technically, there might be token with decimals 0
        // moreover, very possible that old tokens have decimals 0
        // these tokens will just have higher gas fees.
        if(tokenDecimals == 0)
            return token.decimals();

        return tokenDecimals;
    }

    function calcSrcQty(uint dstQty, uint srcDecimals, uint dstDecimals, uint rate) public pure returns(uint) {
        require(dstQty <= MAX_QTY);
        require(rate <= MAX_RATE);
        require(srcDecimals % 2 == 0);
        
        //source quantity is rounded up. to avoid dest quantity being too low.
        uint numerator;
        uint denominator;
        if (srcDecimals >= dstDecimals) {
            require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
            numerator = (dstQty * (10**(srcDecimals - dstDecimals)));
            denominator = rate * (10**(srcDecimals/2));
            return wdiv(numerator, denominator);
        } else {
            require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
            numerator = dstQty ;
            denominator = rate  * (10**(dstDecimals - srcDecimals + srcDecimals/2));
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

    function calcWadRate(uint srcAmnt, uint destAmnt, uint srcDecimals) public pure returns(uint rate)
    {
        require(srcDecimals % 2 == 0);
        rate = wdiv(destAmnt, mul(srcAmnt, 10**(srcDecimals/2)));
        require(rate > 0 && rate < MAX_RATE, "incorrect rate!");
    }

}