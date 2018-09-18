pragma solidity ^0.4.24;

import "ds-test/test.sol";

import "./BaseMarket.sol";

contract BaseMarketTest is DSTest {
    BaseMarket mkt;

    function setUp() public {
        mkt = new BaseMarket();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
