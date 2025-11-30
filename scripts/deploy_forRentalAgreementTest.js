const { ethers } = require("hardhat");
const fs = require("fs"); // Importation nécessaire pour écrire sur le disque

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contract with account:", deployer.address);

    const RealEstateRental = await ethers.getContractFactory("RealEstateRental");
    const contract = await RealEstateRental.deploy(); 
    await contract.waitForDeployment(); // Attendre que la transaction de déploiement soit minée

    const contractAddress = await contract.getAddress();
    console.log("Contract deployed at:", contractAddress);

    // --- Ajout pour sauvegarder l'adresse du contrat ---
    const deploymentInfo = {
        contractAddress: contractAddress,
        timestamp: new Date().toISOString()
    };
    // Écriture du fichier deployment-info.json dans le répertoire racine
    fs.writeFileSync("./deployment-info.json", JSON.stringify(deploymentInfo, null, 2));
    console.log("Deployment info saved to deployment-info.json");
    // --------------------------------------------------
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});