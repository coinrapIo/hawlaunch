pragma solidity ^0.4.24;

import "ds-token/token.sol";


interface CoinRapGatewayInterface
{
    function max_gas_price() external view returns(uint);
    function cap_in_wei(address user) external view returns(uint);
    function token_cap_in_wei(address user, DSToken token) external view returns(uint);
    function enabled(address cntrt_addr) external view returns(bool);

    function get_quote(DSToken base, DSToken quote, uint base_amnt) external view returns(uint rate, uint slippage_rate);
    
    function make(DSToken src, uint src_amnt, DSToken dest, uint dest_amnt, uint rng_min, uint rng_max, uint16 code) external payable returns (uint id);

    //此处参数名和意义都是maker的视角
    function take(uint id, DSToken src, DSToken dest, uint dest_amnt,  uint wad_min_rate, uint16 code) external payable returns(uint actual_amnt, uint fee);
    
    function trade(DSToken src, uint src_amnt, DSToken dest, address dest_addr, uint max_dest_amnt, uint min_rate, uint rate100, uint sn, bytes32 code) external payable returns (uint);

    
}