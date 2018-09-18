pragma solidity ^0.4.24;

import "erc20/erc20.sol";

contract IERC20 is ERC20
{
    uint8 public decimals;
    string public symbol;
    string public name; 
    // function decimals() public view returns (uint8 decimals);
    // function symbol() public view returns (string symbol);
    // function name() public view returns (string name);

}