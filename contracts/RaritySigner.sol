//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./EIP712.sol";

contract RaritySigner is EIP712{

    string private constant SIGNING_DOMAIN = "One-Verse-Rarity";
    string private constant SIGNATURE_VERSION = "1";

    struct Rarity{
        uint tokenId;
        uint rarity;
        bytes signature;
    }

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION){
        
    }

    function getSigner(Rarity memory result) public view returns(address){
        return _verify(result);
    }
  
    function _hash(Rarity memory result) internal view returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(
      keccak256("Rarity(uint256 tokenId,uint256 rarity)"),
      result.tokenId,
      result.rarity
    )));
    }

    function _verify(Rarity memory result) internal view returns (address) {
        bytes32 digest = _hash(result);
        return ECDSA.recover(digest, result.signature);
    }

}