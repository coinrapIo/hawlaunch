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
        srcAmnt = 3 * 10**15;
        destAmnt = 11000000000001000000;
        expectWadRate = 3666666666667;

        // expectWadRate = 909090909090909;
        rate = base.calcWadRate(srcAmnt, destAmnt, 18);
        // rate = wdiv(destAmnt, srcAmnt*10**9);

        // uint remainder = destAmnt % srcAmnt;
        // assertEq(remainder, 0);
        assertEq(rate, expectWadRate);
        qty = base.calcSrcQty(destAmnt, 18, 18,rate);
        assertEq(qty, srcAmnt);
        // bytes32 msghash = 0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658;
        // bytes32 r = 0xeeeb2e746094a673f4e0f942b7560dead3aa6bb37d01f39222a7e53bf4b53872;
        // bytes32 s = 0x403563da6b621b21fae1606ab75fcda2607cec72d5074de72fdee34a05364492;
        // assertEq(ecrecover(h, v, r, s), address(0x5727d938aa27D631f1C2b9CdBF6Ba235953b621B));
        
        // bytes32 msghash = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8;
        // bytes32 h = keccak256("\x19Ethereum Signed Message:\n32", msghash);
        // bytes32 r = 0x9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608;
        // bytes32 s = 0x4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada;
        // uint8 v = 28;
        // assertEq(ecrecover(h, v, r, s), address(0x33692EE5CBF7EcDb8cA43eC9E815C47F3Db8Cd11));
        

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