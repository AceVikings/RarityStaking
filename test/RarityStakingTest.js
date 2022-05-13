const { inputToConfig } = require("@ethereum-waffle/compiler");
const { expect } = require("chai");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Rarity Staking Contract",function(){

    let TokenFactory;
    let NFTFactory;
    let StakingFactory;

    let Token;
    let Nexus;
    let NFT;
    let Staking;

    before(async function() {

        [owner,ace,acadia] = await ethers.getSigners();

        NFTFactory = await ethers.getContractFactory("testNFT");
        TokenFactory = await ethers.getContractFactory("testToken");
        StakingFactory = await ethers.getContractFactory("RarityStaking");

        NFT = await NFTFactory.deploy();
        Token = await TokenFactory.deploy();
        Nexus = await TokenFactory.deploy();
        Staking = await StakingFactory.deploy(NFT.address,Token.address,Nexus.address);

        await NFT.connect(owner).mint(100);
        await NFT.connect(owner).setApprovalForAll(Staking.address,true);
        await Token.connect(owner).mint(10000);
        await Nexus.connect(owner).mint(10000);
        await Token.connect(owner).transfer(Staking.address,parseEther("10000"));
        await Nexus.connect(owner).transfer(Staking.address,parseEther("10000"));

    });

    describe("Deployment", function(){
        it("Should set the owner", async function(){
            expect(await Staking.owner()).to.equal(owner.address);
        })
    })

    describe("Start Staking",function(){
        let rarity = [];
        for(var i=1;i<100;i++){
            rarity.push([i,2277489,"0x91369e121087da8ce3a93a8fb3130ad45da79788fda60bb017eef42ff61fc49d"])
        }
        it("Should initialize tokens",async function(){
            await Staking.initializeRarity(rarity);
            for(var i=1;i<100;i++){
                expect(await Staking.tokenRarity(i)).to.equal(2277489);
            }
        })
        let tokens = [];
        for(var j=1;j<100;j++){
            tokens.push(j);
        }
        it("Should transfer tokens",async function(){
            await Staking.stakeTokens(tokens);
            for(var i=1;i<100;i++){
                expect (await NFT.ownerOf(i)).to.equal(Staking.address);
            }
        })
        it("Should update mappings",async function(){
            for(var i=1;i<100;i++){
                expect ((await Staking.stakedInfo(i))["owner"]).to.equal(owner.address);
            }
        })
        it("Should update user staked",async function(){
            for(var i=1;i<100;i++){
                expect ((await Staking.getUserStaked(owner.address)).map((value)=>{return parseInt(value)})).to.include(i);
            }
        })
    })

})