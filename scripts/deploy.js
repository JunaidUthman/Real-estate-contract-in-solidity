const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Déploiement avec le compte:", deployer.address);

    const RealEstateRental = await ethers.getContractFactory("RealEstateRental");
    const contract = await RealEstateRental.deploy();
    await contract.waitForDeployment();

    const address = await contract.getAddress();
    console.log("✅ Contrat déployé à l'adresse:", address);

    // --- Génération du fichier pour le Frontend ---
    const contractsDir = path.join(__dirname, "..", "frontend", "src", "contracts");

    // Créer le dossier s'il n'existe pas
    if (!fs.existsSync(contractsDir)) {
        fs.mkdirSync(contractsDir, { recursive: true });
    }

    // Sauvegarde de l'adresse et de l'ABI
    fs.writeFileSync(
        path.join(contractsDir, "contract-address.json"),
        JSON.stringify({ RealEstateRental: address }, undefined, 2)
    );

    const RealEstateRentalArtifact = artifacts.readArtifactSync("RealEstateRental");

    fs.writeFileSync(
        path.join(contractsDir, "RealEstateRental.json"),
        JSON.stringify(RealEstateRentalArtifact, undefined, 2)
    );

    console.log("✅ Fichiers ABI et Adresse envoyés au dossier frontend !");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});