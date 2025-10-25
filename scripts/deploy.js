// scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contract with account:", deployer.address);

    const RealEstateRental = await ethers.getContractFactory("RealEstateRental");
    const contract = await RealEstateRental.deploy(); // deploy returns deployed contract
console.log("Contract deployed at:", await contract.getAddress());

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
