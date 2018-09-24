pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "./Set.sol";


contract SetContract
{
    using SetLib for SetLib.Set;

    SetLib.Set set;

    function add(uint x) public returns(bool)
    {
        return set.add(x);
    }

    function remove(uint x) public returns(bool)
    {
        return set.remove(x);
    }

    function exists(uint n) public view returns(bool)
    {
        return set.exists(n);
    }

    function size() public view returns(uint)
    {
        return set.size();
    }

}

contract SetTest is DSTest
{
    SetContract inst;
    function setUp() public {
        inst = new SetContract();
    }

    function test_add() public
    {
        inst.add(1);
        inst.add(2);
        inst.add(3);
        inst.add(14);
        assertTrue(inst.exists(3));
        assertEq(inst.size(), 4);
        inst.remove(3);
        assertTrue(inst.exists(2));
        assertTrue(!inst.exists(3));
        assertTrue(inst.exists(1));
        assertEq(inst.size(),3);
        assertTrue(inst.exists(14));

        assertTrue(!inst.add(2));
        assertTrue(!inst.remove(3));

        assertTrue(inst.remove(14));
        assertTrue(!inst.exists(14));
        assertTrue(inst.add(5));
        assertEq(inst.size(), 3);

        // uint[] arr = inst.getKeys();
        // assertTrue(arr.length==2);
    }


}