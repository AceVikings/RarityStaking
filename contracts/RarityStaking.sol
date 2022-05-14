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
    IERC20 RaffleToken;

    struct tokenInfo{
        address owner;
        uint lastClaim;
        uint lastRoll;
        uint position;
        uint rateIndex;
    }

    bool public Paused;
    uint raffleReward = 1 ether;
    uint raffleCooldown = 12 hours;

    mapping(uint=>uint) public tokenRarity;
    mapping(uint=>tokenInfo) public stakedInfo;
    mapping(address=>uint[]) public userStaked;

    uint[] public rate;
    uint[] public time;
    uint[2] public edgeRarity = [277489,2859033];
    uint[2] public raffleOdds = [80000,50000];
    uint[2] public rarityMultiplier = [80000,40000];
    address designatedSigner = 0x08042c118719C9889A4aD70bc0D3644fBe288153;

    event RaffleWin(address indexed user,uint indexed tokenId,bool win);

    constructor(address _nft,address _rewardToken,address _raffleToken) {
        NFT = IERC721(_nft);
        RewardToken = IERC20(_rewardToken);
        RaffleToken = IERC20(_raffleToken);
        rate.push(5 ether);
        time.push(block.timestamp);
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
        uint length = tokenIds.length;
        uint rateLength = rate.length;
        uint userStakedLength = userStaked[msg.sender].length;
        for(uint i=0;i<length;i++){
            require(tokenRarity[tokenIds[i]] != 0,"Rarity not initialized");
            require(NFT.ownerOf(tokenIds[i]) == msg.sender,"Sender not owner");
            stakedInfo[tokenIds[i]] = tokenInfo(msg.sender,block.timestamp,block.timestamp,userStakedLength+i,rateLength-1);
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

    function raffleRoll(uint[] memory tokenIds) external{
        require(msg.sender == tx.origin,"Contracts can't roll");
        uint length = tokenIds.length;
        require(length < 900,"Can't roll more than 900 at a time");
        uint baseRandom = uint(vrf());
        uint amount = 0;
        for (uint j=0;j<=length/60;j++){
            uint random = uint(keccak256(abi.encode(baseRandom%10000)));
            baseRandom /= 10000;
            uint end;
            if(length < 60*(j+1) - 1){
                end = length;
            }
            else{
                end = 60*(j+1) - 1;
            }
            for(uint i=60*j;i<end;i++){
                require(stakedInfo[tokenIds[i]].owner == msg.sender,"Sender not owner");
                require(block.timestamp - stakedInfo[tokenIds[i]].lastRoll >= raffleCooldown,"Rolling too soon");
                stakedInfo[tokenIds[i]].lastRoll = block.timestamp;
                uint odds = raffleOdds[0] + raffleOdds[1]*(tokenRarity[tokenIds[i]]-edgeRarity[0])/(edgeRarity[1]-edgeRarity[0]); //Max rarity - Min rarity = 2580383
                uint mod = random%1000000;
                if (mod < odds){
                    amount += raffleReward;
                    emit RaffleWin(msg.sender, tokenIds[i], true);
                }
                else{
                    emit RaffleWin(msg.sender, tokenIds[i], false);
                }
                random /= 10;
            }
        }
        RaffleToken.transfer(msg.sender,amount);
    }

    function claimRewards(uint[] memory tokenIds) public {
        uint amount;
        for(uint i=0;i<tokenIds.length;i++){
            require(stakedInfo[tokenIds[i]].owner == msg.sender,"Sender not owner");
            amount += getRewards(tokenIds[i]);
            stakedInfo[tokenIds[i]].lastClaim = block.timestamp;
            stakedInfo[tokenIds[i]].rateIndex = rate.length - 1;
        }
        RewardToken.transfer(msg.sender,amount);
    }

    function emergencyUnstake(uint[] memory tokenIds) external {
        for(uint i=0;i<tokenIds.length;i++){
            require(stakedInfo[tokenIds[i]].owner == msg.sender,"Sender not owner");
            NFT.transferFrom(address(this),msg.sender,tokenIds[i]);
            popTokens(tokenIds[i]);
            delete stakedInfo[tokenIds[i]];
        }
    }

    function getRewards(uint tokenId) public view returns(uint){
        tokenInfo storage info = stakedInfo[tokenId];
        if(info.lastClaim == 0){
            return 0;
        }
        uint currentTime;
        uint collected = 0;
        for(uint i=info.rateIndex;i<rate.length;i++){
            if(info.lastClaim < time[i]){
                if(collected == 0){
                collected += (time[i] - info.lastClaim) * rate[i-1];
                }
                else{
                collected += (time[i] - time[i-1])*rate[i-1];
                }
            }
            currentTime = i;
        }
        if(collected == 0){
            collected += (block.timestamp - info.lastClaim)*rate[currentTime];
        }
        else{
            collected += (block.timestamp - time[currentTime])*rate[currentTime];
        }
        uint multiplier = rarityMultiplier[0] + rarityMultiplier[1]*(tokenRarity[tokenId]-edgeRarity[0])/(edgeRarity[1]-edgeRarity[0]); 
        return collected*multiplier/(100000*1 days);
    }

    function popTokens(uint tokenId) private {
        uint lastToken = userStaked[msg.sender][userStaked[msg.sender].length - 1];
        uint currPos = stakedInfo[tokenId].position;
        userStaked[msg.sender][currPos] = lastToken;
        stakedInfo[lastToken].position = currPos;
        userStaked[msg.sender].pop();
    }

    function vrf() private view returns (bytes32 result) {
        uint256[1] memory bn;
        bn[0] = block.number;
        assembly {
            let memPtr := mload(0x40)
            if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
                invalid()
            }
            result := mload(memPtr)
        }
        return result;
    }

    function getUserStaked(address _user) external view returns(uint[] memory){
        return userStaked[_user];
    }

    function pauseContract(bool _pause) external onlyOwner{
        Paused = _pause;
    }

    function updateRewards(uint _newRate) external onlyOwner{
        rate.push(_newRate);
        time.push(block.timestamp);
    }

    function setNFT(address _nft) external onlyOwner{
        NFT = IERC721(_nft);
    }

    function setRaffleToken(address _raffle) external onlyOwner{
        RaffleToken = IERC20(_raffle);
    }

    function setRewardToken(address _token) external onlyOwner{
        RewardToken = IERC20(_token);
    }

    function setRaffleCooldown(uint _time) external onlyOwner{
        raffleCooldown = _time;
    }

    function setRaffleReward(uint _reward) external onlyOwner{
        raffleReward = _reward;
    }

    function setEdgeRarity(uint[2] memory _edge) external onlyOwner{
        edgeRarity[0] = _edge[0];
        edgeRarity[1] = _edge[1];
    }

    function setRaffleOdds(uint[2] memory _odds) external onlyOwner{
        raffleOdds[0] = _odds[0];
        raffleOdds[1] = _odds[1];
    }

    function setRarityMultiplier(uint[2] memory _multiplier) external onlyOwner{
        rarityMultiplier[0] = _multiplier[0];
        rarityMultiplier[1] = _multiplier[1];
    }

    function retrieveRewardToken() external onlyOwner{
        RewardToken.transfer(msg.sender,RewardToken.balanceOf(address(this)));
    }

    function retrieveRaffleToken() external onlyOwner{
        RaffleToken.transfer(msg.sender,RaffleToken.balanceOf(address(this)));
    }

    function setDesignatedSigner(address _signer) external onlyOwner{
        designatedSigner = _signer;
    }

}