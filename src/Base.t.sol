pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "./Base.sol";
import "./IERC20.sol";

contract BaseTest is DSTest {
    Base base;
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    IERC20 constant internal WETH_TOKEN_ADDR = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        base = new Base();
    }

    function testBalance() public
    {
        // address dust_wallet = address(0x0fc7ebf20B23437E359Bba1D214a4ED0ad72f577);
        // uint eth = 37985824501548138;
        // assertTrue(base.getBalance(ETH_TOKEN_ADDRESS, dust_wallet) == eth);
        // uint weth = 8604691163683049;
        // assertTrue(base.getBalance(WETH_TOKEN_ADDR, dust_wallet) == weth);
    }

    function testCalcRate() public
    {
        // function calcRate(uint srcAmnt, uint srcDecimals, uint destAmnt, uint dstDecimals) 
        uint srcAmnt = 10**18;
        uint destAmnt = 68675 * 10 ** 14;
        uint expectWadRate = 68675 * 10 ** 14;
        // expectEventsExact(this);
        uint rate = base.calcWadRate(srcAmnt, destAmnt);
        // emit log_named_decimal_uint("wad_rate", rate, 18);
        assertTrue(rate == expectWadRate);

        uint wad = base.toWad(srcAmnt, 18);
        assertEq(wad, srcAmnt);

        uint expectCnyRate = 145613396432471787;
        rate = base.calcWadRate(destAmnt, srcAmnt);
        assertEq(rate, expectCnyRate);

    }

}