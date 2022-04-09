//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

/// @title Rarity Staking
/// @author Ace
/// @notice NFT Staking contract that emits variable rewards based on token rarity

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./RaritySigner.sol";

contract RarityStaking is Ownable,RaritySigner{

    IERC721 NFT;
    IERC20 RewardToken;

    struct tokenInfo{
        address owner;
        uint lastClaim;
        uint position;
    }

    bool public Paused;
    uint baseReward = 1 ether;

    mapping(uint=>uint) public tokenRarity;
    mapping(uint=>tokenInfo) public stakedInfo;
    mapping(address=>uint[]) userStaked;

    address designatedSigner;

    constructor(address _nft,address _rewardToken) {
        NFT = IERC721(_nft);
        RewardToken = IERC20(_rewardToken);
    }

    modifier isUnPaused{
        require(!Paused,"Execution Paused");
        _;
    }

    function initializeRarity(Rarity[] memory rarity) external {
        for(uint i=0;i<rarity.length;i++){
            require(getSigner(rarity[i]) == designatedSigner,"invalid signer");
            tokenRarity[rarity[i].tokenId] = rarity[i].rarity;     
        }
    }

    function stakeTokens(uint[] memory tokenIds) external isUnPaused{
        for(uint i=0;i<tokenIds.length;i++){
            require(tokenRarity[tokenIds[i]] != 0,"Rarity not initialized");
            require(NFT.ownerOf(tokenIds[i]) == msg.sender,"Sender not owner");
            stakedInfo[tokenIds[i]] = tokenInfo(msg.sender,block.timestamp,userStaked[msg.sender].length);
            userStaked[msg.sender].push(tokenIds[i]);
            NFT.transferFrom(msg.sender,address(this),tokenIds[i]);
        }
    }

    function unstakeTokens(uint[] memory tokenIds) external {
        claimRewards(tokenIds);
        for(uint i=0;i<tokenIds.length;i++){
            require(stakedInfo[tokenIds[i]].owner == msg.sender,"Sender not owner");
            NFT.transferFrom(address(this),msg.sender,tokenIds[i]);
            popTokens(tokenIds[i]);
            delete stakedInfo[tokenIds[i]];
        }
    }

    function claimRewards(uint[] memory tokenIds) public {
        uint amount;
        for(uint i=0;i<tokenIds.length;i++){
            require(stakedInfo[tokenIds[i]].owner == msg.sender,"Sender not owner");
            amount += getRewards(tokenIds[i]);
            stakedInfo[tokenIds[i]].lastClaim = block.timestamp;
        }
        RewardToken.transfer(msg.sender,amount);
    }

    function getRewards(uint tokenId) public view returns(uint){
        tokenInfo storage info = stakedInfo[tokenId];
        if(info.lastClaim == 0){
            return 0;
        }
        uint multiplier = 80 + 40*tokenRarity[tokenId]/1000; //Assumption max rarity - min rarity = 1000
        return (block.timestamp - info.lastClaim) * baseReward * multiplier/100;
    }

    function popTokens(uint tokenId) private {
        uint lastToken = userStaked[msg.sender][userStaked[msg.sender].length - 1];
        uint currPos = stakedInfo[tokenId].position;
        userStaked[msg.sender][currPos] = lastToken;
        stakedInfo[lastToken].position = currPos;
        userStaked[msg.sender].pop();
    }

    function pauseContract(bool _pause) external onlyOwner{
        Paused = _pause;
    }

    function retrieveRewardToken() external onlyOwner{
        RewardToken.transfer(msg.sender,RewardToken.balanceOf(address(this)));
    }

    function setDesignatedSigner(address _signer) external onlyOwner{
        designatedSigner = _signer;
    }

}