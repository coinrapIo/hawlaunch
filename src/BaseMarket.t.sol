pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "./BaseMarket.sol";

contract BaseMarketTest is DSTest {
    BaseMarket mkt;
    DSToken crp;
    address adm = address(0x00a14fb9f33365c0b614a0ea39fcdc7db153c18f5d);
    DSToken constant internal ETH_TOKEN_ADDRESS = DSToken(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint startsWith = 0;

    uint initialBalance = 1000 * 10 ** 18;

    function setUp() public {
        mkt = new BaseMarket(adm, startsWith);
        crp = new DSToken("CRP");
        mkt.setToken(crp, true);
        crp.mint(initialBalance);
    }

    // function testFail_basic_sanity() public {
    //     assertTrue(false);
    // }

    // function test_basic_sanity() public {
    //     assertTrue(true);
    // }
    function test_make() public
    {
        uint _srcAmnt = 10**18;
        uint _destAmnt = 1000 * 10**18;
        uint _min = _destAmnt;
        uint _max = _destAmnt;
        uint _fee = 10 * 10**15;
        uint16 _code = 1234;
        // DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, uint rngMin, uint rngMax, uint prepayFee, uint16 code
        uint id = mkt.make.value(_srcAmnt+_fee)(ETH_TOKEN_ADDRESS, _srcAmnt, crp, _destAmnt, _min, _max, _fee, _code);
        assertEq(id, startsWith+1);
        validate_offer(id, ETH_TOKEN_ADDRESS, _srcAmnt, crp, _destAmnt, _min, _max, _code);
        // DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, 
        // address owner, uint min, uint max, bool hasCode, uint16 code
        // DSToken src;
        // DSToken dest;
        // uint srcAmnt; 
        // uint destAmnt;
        // uint min;
        // uint max;
        // address owner;
        // uint16 code;
        // bool hasCode;

        // (src, srcAmnt,  dest, destAmnt, owner, min, max, hasCode, code) = mkt.getOffer(id);
        // assertTrue(src == ETH_TOKEN_ADDRESS);
        // assertTrue(dest == crp);
        // assertEq(srcAmnt, _srcAmnt);
        // assertEq(destAmnt, _destAmnt);
        // assertEq(owner, address(this));
        // assertEq(min, _min);
        // assertEq(max, _max);
        // assertTrue(hasCode == (_code > 0));
        // assertTrue(code == _code);
        assertEq(mkt.getOfferCnt(this), 1);

    }

    function validate_offer(uint id, DSToken _src, uint _srcAmnt, DSToken _dest, uint _destAmnt, uint _min, uint _max, uint16 _code) internal
    {
        // DSToken src;
        // DSToken dest;
        uint srcAmnt; 
        uint destAmnt;
        uint min;
        uint max;
        address owner;
        uint16 code;
        // bool hasCode;

        (, srcAmnt,  , destAmnt, owner, min, max, ,code ) = mkt.getOffer(id);
        // assertTrue(src == ETH_TOKEN_ADDRESS);
        // assertTrue(dest == crp);
        assertEq(srcAmnt, _srcAmnt);
        assertEq(destAmnt, _destAmnt);
        assertEq(owner, address(this));
        assertEq(min, _min);
        assertEq(max, _max);
        // assertTrue(hasCode == (_code > 0));
        assertTrue(code == _code);
    }
}
