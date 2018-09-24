pragma solidity ^0.4.24;


import "ds-token/token.sol";

contract SwapMkt
{

    function max_gas_price() public view returns (uint)
    {
        return 0;
    }

    function cap_in_wei(address user) public view returns (uint)
    {
        return 0;
    }

    function token_cap_in_wei(address user, DSToken token) public view returns (uint)
    {
        return 0;
    }

    function enabled() public view returns(bool)
    {
        return false;

    }

    function get_quote(DSToken base, DSToken quote, uint base_amnt) public view returns(uint rate, uint slippage_rate)
    {
        return (0, 0);
    }

    function trade(
        address trader, DSToken src, uint src_amnt, DSToken dest, address dest_addr, uint max_dest_amnt, uint min_rate, 
        uint rate100, uint sn, bytes32 code
    ) public payable returns (uint)
    {
        return 0;
    }

}