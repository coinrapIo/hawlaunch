pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "./Base.sol";

contract BaseTest is DSTest, DSMath {
    Base base;
    DSToken constant internal ETH_TOKEN_ADDRESS = DSToken(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    DSToken constant internal WETH_TOKEN_ADDR = DSToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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
        uint expectWadRate = 68675 * 10 ** 5;
        // expectEventsExact(this);
        uint rate = base.calcWadRate(srcAmnt, destAmnt, 18);
        
        // emit log_named_decimal_uint("wad_rate", rate, 18);
        assertEq(rate, expectWadRate);
        uint qty = base.calcSrcQty(destAmnt, 18, 18, rate);
        assertEq(srcAmnt, qty);

        // srcAmnt = 2 * 10 ** 22;
        // destAmnt = 10**18;  // 0.00005 : 1
        // expectWadRate = 5 * 10**13;

        // srcAmnt = 11000000000000000000;
        // destAmnt = 10000000000000000;
        // expectWadRate = 909090;
        // srcAmnt = 1100000000;
        // destAmnt = 1000000;
        // expectWadRate = 909091;
        // srcAmnt = 3 * 10**15;
        // destAmnt = 11000000000001000000;
        // expectWadRate = 3666666666667;
        srcAmnt = 14562000000000000000000;
        destAmnt = 100000000000000000;
        expectWadRate = 6868;

        // expectWadRate = 909090909090909;
        rate = base.calcWadRate(srcAmnt, destAmnt, 18);
        // rate = wdiv(destAmnt, srcAmnt*10**9);

        // uint remainder = destAmnt % srcAmnt;
        // assertEq(remainder, 0);
        assertEq(rate, expectWadRate);
        qty = base.calcSrcQty(destAmnt, 18, 18,rate);
        assertEq(qty, srcAmnt);
        uint8 v = 28;
        // bytes32 h = 0x1476abb745d423bf09273f1afd887d951181d25adc66c4834a70491911b7f750;
        // bytes32 r = 0xe6ca9bba58c88611fad66a6ce8f996908195593807c4b38bd528d2cff09d4eb3;
        // bytes32 s = 0x3e5bfbbf4d3e39b1a2fd816a7680c19ebebaf3a141b239934ad43cb33fcec8ce;
        // address addr = ecrecover(h, v, r, s);
        // assertEq(addr, address(0x5ce9454909639D2D17A3F753ce7d93fa0b9aB12E));
        
        // bytes32 msghash = 0x637027ead3e166d3b96679f11241cd71b8917780c5d669b44659d364950002e7;
        // bytes32 h = msghash; //keccak256("\x19Ethereum Signed Message:\n32", msghash);
        // bytes32 r = 0x5afbf5f7a4c5e3f46c989f8b4c34d7660ff6f9ddb66f48282d53609b7f97e712;  // 41153332590067763136963621823720559789582984567710433983028445548701034211090;
        // bytes32 s = 0x4ef0fbd4d32ac66738433471d53ce76bf0cd72b602336357ba89a8eac4ea981b;  // 35706183561121818561236792521317601083264836186301836213702387435094707705883;
        // // uint8 v = 28;
        // assertEq(ecrecover(h, v, r, s), address(0x897eeaF88F2541Df86D61065e34e7Ba13C111CB8));
        v = 27;
        bytes32 h = 0xf43d6d30b9222da6f031252c5148fc8ceb80edf5ceccbf755daa8d6780fb8435;
        bytes32 r = 0xb81e2a1eb76f2d12efbba7fb583689e84ce5c4f555f49011fd87a984dbba1d42;
        bytes32 s = 0x262488da64b6d206090b035d432cc39cec772ff11bc89bb9a7603e016ef615f;
        address addr = ecrecover(h, v, r, s);
        assertEq(addr, address(0x5727d938aa27D631f1C2b9CdBF6Ba235953b621B));
        

        // uint wad = base.toWad(srcAmnt, 18);
        // assertEq(wad, srcAmnt);

        // uint expectCnyRate = 145613396432471787;
        // rate = base.calcWadRate(destAmnt, srcAmnt);
        // assertEq(rate, expectCnyRate);

        // // uint expectJpyRate = 8928571428571428; 进位了。
        // uint expectJpyRate = 8928571428571429;
        // rate = base.calcWadRate(112*srcAmnt, srcAmnt);
        // assertEq(rate, expectJpyRate);

        // uint usd2jpyRate = 112 * 10**18;
        // rate = base.calcWadRate(srcAmnt, 112*srcAmnt);
        // assertEq(rate, usd2jpyRate);

        // uint b = mul(sub(srcAmnt, 5*10**17), 10);
        // assertEq(b, 5*10**18);
        // uint d = wdiv(b, 10000*10**18); // 0.5 * 0.001
        // assertEq(d, 5*10**14); //0.0005
    }

}