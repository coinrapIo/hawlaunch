pragma solidity ^0.4.24;

import "ds-test/test.sol";

import "./C2ccontract.sol";

contract C2ccontractTest is DSTest {
    C2ccontract contract;

    function setUp() public {
        contract = new C2ccontract();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
