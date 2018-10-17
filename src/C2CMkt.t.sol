pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "ds-token/token.sol";
import "./C2CMkt.sol";
import "./CoinRapGateway.sol";

contract C2CMktTest is DSTest {
    
    DSToken crp;
    C2CMkt c2c;
    CoinRapGateway gateway;
    uint startsWith = 0;
    uint initialBalance = 100000 * 10 ** 18;
    uint user1CrpAmnt = 10000*10**18;
    DSToken constant internal ETH_TOKEN_ADDRESS = DSToken(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    DSToken constant internal WETH_TOKEN_ADDR = DSToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address user1 = address(0x897eeaF88F2541Df86D61065e34e7Ba13C111CB8);
    

    function setUp() public 
    {
        c2c = new C2CMkt(address(this), startsWith);

        gateway = new CoinRapGateway();
        gateway.set_c2c_mkt(c2c);
        c2c.setCoinRapGateway(gateway);

        crp = new DSToken("CRP");
        c2c.setToken(crp, true);
        crp.mint(initialBalance);

        user1.transfer(5*10**18);  // test -5eth-> user1
        crp.transfer(user1, user1CrpAmnt); //
    }

    function () public payable
    {
    }

    function test_make() public
    {

        uint _srcAmnt = 10**18;
        uint _destAmnt = 1000 * 10**18;
        uint _min = _destAmnt;
        uint _max = _destAmnt;
        uint _fee = 5*10**14;
        uint16 _code = 1234;
        // bytes memory _ref;
        // DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, 
        // uint prepay, uint rng_min, uint rng_max, uint16 code, bytes ref
        uint id = gateway.make.value(_srcAmnt+_fee)(ETH_TOKEN_ADDRESS, _srcAmnt, crp, _destAmnt, _min, _max, _code);
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
        assertEq(c2c.getOfferCnt(this), 1);
        assertTrue(c2c.isActive(id));
        assertEq(c2c.getOwner(id), address(this));
        // uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code
        c2c.update(id, _destAmnt, _min, _max, 0);
        uint amnt;
        uint fee;
        (amnt, fee) = c2c.cancel(id);
        assertEq(amnt -_fee, _srcAmnt);
        assertEq(fee, _fee);

    }

    function test_make_take() public
    {
        uint _srcAmnt = 10**18;
        uint _destAmnt = 1000 * 10**18;
        uint _min = 5*10**17;
        uint _max = _destAmnt;
        uint _fee = 5*10**14;
        uint16 _code = 1234;
        // bytes memory _ref;
        // DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, 
        // uint prepay, uint rng_min, uint rng_max, uint16 code, bytes ref
        uint id = c2c.make.value(_srcAmnt+_fee)(user1, ETH_TOKEN_ADDRESS, _srcAmnt, crp, _destAmnt, _min, _max, _code);
        assertEq(id, startsWith+1);
        assertEq(crp.balanceOf(this), initialBalance-user1CrpAmnt);
        assertTrue(crp.approve(address(gateway), 2**255));
        (_destAmnt, _fee) = gateway.take.value(0)(id, ETH_TOKEN_ADDRESS, crp, 500*10**18, 1000*10**9, _code);
        assertEq(crp.balanceOf(this), initialBalance-user1CrpAmnt-500*10**18);
        assertEq(_destAmnt, 5*10**17);
        assertEq(_fee, 0);
        
    }

    function test_make_take_token_to_eth() public
    {
        uint _src_amnt = 1000 * 10 ** 18; //token
        uint _dest_amnt = 10**18; //eth
        uint _min = 5 * 10 **17;
        uint _max = _dest_amnt;
        uint _fee = 5 * 10 ** 14;
        uint16 _code = 1234;

        uint rate = c2c.calcWadRate(_src_amnt, _dest_amnt, c2c.getDecimalsSafe(crp));
        assertEq(rate, 10**6);

        crp.approve(address(gateway), 2**255);
        // uint id = gateway.make.value(0)(crp, _src_amnt, ETH_TOKEN_ADDRESS, _dest_amnt, _min, _max, _code);
        crp.transfer(c2c, _src_amnt);
        uint id = c2c.make.value(0)(user1, crp, _src_amnt, ETH_TOKEN_ADDRESS, _dest_amnt, _min, _max, _code);
        assertEq(_src_amnt, crp.balanceOf(c2c));
        assertEq(id, startsWith+1);
        
        (_dest_amnt, _fee) = gateway.take.value(5*10**17)(id, crp, ETH_TOKEN_ADDRESS, 5*10**17, 10**6, _code);
        assertEq(_dest_amnt, 500*10**18);
        assertEq(_fee, 0);
        

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
        // uint16 code;
        // bool hasCode;

        (, srcAmnt,  , destAmnt, owner, min, max, , , ) = c2c.getOffer(id);
        // assertTrue(src == ETH_TOKEN_ADDRESS);
        // assertTrue(dest == crp);
        assertEq(srcAmnt, _srcAmnt);
        assertEq(destAmnt, _destAmnt);
        assertEq(owner, address(this));
        assertEq(min, _min);
        assertEq(max, _max);
        // assertTrue(hasCode == (_code > 0));
        // assertTrue(code == _code);
    }

    function test_take() public
    {
        // uint u1_balance = user1.balance;
        // assertEq(u1_balance, 5*10**18);
        // uint u1_crp_before = crp.balanceOf(user1);
        // uint actual_amnt;
        // uint fee;
        //uint id, DSToken src, DSToken dest, uint dest_amnt,  uint wad_min_rate, uint16 code
        // (actual_amnt, fee) = gateway.take(startsWith+1, ETH_TOKEN_ADDRESS, crp, 500*10**18, 1000*10**18, 1234);
        // assertEq(actual_amnt, 500*10**18);
        // assertEq(fee, 0);
    }
}
