pragma solidity ^0.4.24;

import "ds-token/token.sol";


interface OfferInterface
{
    function make_offer(
        address maker, 
        DSToken src, 
        uint src_amnt, 
        DSToken dest, 
        uint dest_amnt, 
        uint rng_min, 
        uint rng_max, 
        uint16 code, 
        uint prepay,
        uint remit,
        uint8 bps
        ) public returns (uint id);
    
    function take_offer(
        uint id, 
        DSToken tkDstTkn, 
        uint amnt, 
        uint srcAmnt
        ) public returns(uint actualAmnt, uint fee, uint ownerAmntBySell, bool full_filled);
    
    function kill_offer(uint id) public returns(uint src_amnt, uint fee);
    function getOfferCnt(address owner) public view returns(uint cnt);
    function getOffers(address owner) public view returns(uint[]);
    function update_offer(uint id, uint destAmnt, uint rngMin, uint rngMax, uint16 code) public returns (uint old_dest_amnt);
    function isActive(uint id) public view returns (bool active);
    function getOwner(uint id) public view returns (address);
    function getOffer(uint id) public view returns(
        DSToken src, uint srcAmnt, DSToken dest, uint destAmnt, 
        address owner, uint min, uint max, bool hasCode,
        uint prepay, uint accumEther);
    function getOfferByIds(uint[] ids) public view returns(
        uint[], uint[], uint[], uint[]);
    function set_c2c_mkt(address c2c) public;
    function getOfferCode(uint id, bytes32 msghash, uint8 v, bytes32 r, bytes32 s) public view returns(uint16 code);

}