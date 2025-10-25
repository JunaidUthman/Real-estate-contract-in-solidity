const hre = require("hardhat");

async function main() {
    const accounts = await hre.ethers.getSigners();
    
    console.log("=== Account Balances ===\n");
    
    for (let i = 0; i < Math.min(accounts.length, 5); i++) {
        const address = accounts[i].address;
        const balance = await hre.ethers.provider.getBalance(address);
        const balanceInEth = hre.ethers.formatEther(balance);
        
        console.log(`Account ${i}:`);
        console.log(`  Address: ${address}`);
        console.log(`  Balance: ${balanceInEth} ETH`);
        console.log(`  Balance: ${balance.toString()} wei\n`);
    }
    
    // Vérifier le solde du contrat
    const contractAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Remplacez par votre adresse
    const contractBalance = await hre.ethers.provider.getBalance(contractAddress);
    console.log("=== Contract Balance ===");
    console.log(`Address: ${contractAddress}`);
    console.log(`Balance: ${hre.ethers.formatEther(contractBalance)} ETH`);
    console.log(`Balance: ${contractBalance.toString()} wei\n`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });