// after each test , You should re run the commands for the local blockchain network and for the contract deployment
const hre = require("hardhat");
const fs = require("fs");

async function main() {
    // --- 1. CONFIGURATION ET CONNEXION ---
    
    // Assurez-vous que deployment-info.json contient l'adresse du contrat déployé.
    if (!fs.existsSync("./deployment-info.json")) {
        console.error("FATAL: Le fichier './deployment-info.json' est manquant. Veuillez déployer le contrat d'abord.");
        process.exit(1);
    }
    
    const deploymentInfo = JSON.parse(fs.readFileSync("./deployment-info.json"));
    const contractAddress = deploymentInfo.contractAddress;

    if (!contractAddress) {
        console.error("FATAL: L'adresse du contrat (contractAddress) n'est pas définie dans deployment-info.json.");
        process.exit(1);
    }

    console.log("Interacting with contract at:", contractAddress);
    
    // Récupérer les signers (comptes de test ou de développement)
    const [owner, landlord, tenant] = await hre.ethers.getSigners();
    
    // Attacher l'ABI du contrat à son adresse
    const RealEstateRental = await hre.ethers.getContractFactory("RealEstateRental");
    const contract = RealEstateRental.attach(contractAddress);
    
    // Montants
    const RENT_AMOUNT = hre.ethers.parseEther("1.0"); // 1 ETH
    const SECURITY_DEPOSIT = hre.ethers.parseEther("2.0"); // 2 ETH
    const TOTAL_INITIAL_PAYMENT = RENT_AMOUNT + SECURITY_DEPOSIT;
    const DURATION_MONTHS = 6;
    
    // --- 2. ÉTAPE 1: Listing d'une Propriété (Landlord) ---
    console.log("\n=== 1. Listing Property ===");
    
    const listTx = await contract.connect(landlord).listProperty(
        "123 Avenue des Champs-Élysées, Paris",
        "Luxury 3BR apartment with Eiffel Tower view",
        RENT_AMOUNT,
        SECURITY_DEPOSIT
    );
    
    await listTx.wait();
    console.log("Propriété listée avec succès!");
    
    // Obtenir l'ID de la propriété (devrait être 1)
    const propertyId = 1;
    let property = await contract.getProperty(propertyId);
    console.log(`Propriété ID ${property.id.toString()} (${hre.ethers.formatEther(property.rentPerMonth)} ETH/mois).`);
    
    // --- 3. ÉTAPE 3: Réservation (Tenant) - Escrow ---
    // (L'étape 2 (RentalRequest Accepted) est gérée par le backend)
    console.log("\n=== 2. Reservation de l'Accord (Escrow) ===");
    
    const initialContractBalance = await hre.ethers.provider.getBalance(contractAddress);
    
    const reserveTx = await contract.connect(tenant).reserveProperty(
        propertyId, // ID de la propriété
        DURATION_MONTHS, // Durée en mois
        { value: TOTAL_INITIAL_PAYMENT } // Paiement (Loyer + Dépôt)
    );
    
    const receiptReserve = await reserveTx.wait();
    const agreementId = 1; // Le premier accord créé
    
    // Vérifications après réservation
    let agreement = await contract.getRentalAgreement(agreementId);
    let newContractBalance = await hre.ethers.provider.getBalance(contractAddress);
    
    console.log("Réservation faite. Accord ID:", agreement.agreementId.toString());
    console.log("Statut: PENDING_RESERVATION (0)");
    console.log(`Fonds séquestrés dans le contrat: ${hre.ethers.formatEther(newContractBalance - initialContractBalance)} ETH`);

    
    // --- 4. ÉTAPE 4: Activation de l'Accord (Tenant) - Libération des fonds ---
    console.log("\n=== 3. Activation de l'Accord (Clé Reçue) ===");
    
    // Solde du propriétaire avant l'activation (pour vérifier le transfert)
    const initialLandlordBalance = await hre.ethers.provider.getBalance(landlord.address);
    
    const activateTx = await contract.connect(tenant).activateAgreement(agreementId);
    
    await activateTx.wait();
    console.log("Accord activé! Le premier loyer a été transféré au propriétaire.");

    // Vérifications après activation
    agreement = await contract.getRentalAgreement(agreementId);
    newContractBalance = await hre.ethers.provider.getBalance(contractAddress);
    const finalLandlordBalance = await hre.ethers.provider.getBalance(landlord.address);
    
    console.log("Statut actuel: ACTIVE (1)");
    console.log(`Solde Landlord après activation: ${hre.ethers.formatEther(finalLandlordBalance)} ETH`);
    console.log(`Dépôt de garantie toujours séquestré: ${hre.ethers.formatEther(newContractBalance)} ETH`);


    // --- 5. ÉTAPE 5: Paiement Mensuel (Tenant) ---
    console.log("\n=== 4. Paiement Loyer Mensuel ===");
    
    // Note : Pour un test réel, il faudrait avancer le temps (evm_increaseTime)
    // Ici, nous faisons juste un paiement.
    
    const payTx = await contract.connect(tenant).payMonthlyRent(
        agreementId,
        { value: RENT_AMOUNT } // Seulement le montant du loyer
    );
    
    await payTx.wait();
    
    agreement = await contract.getRentalAgreement(agreementId);
    console.log("Paiement mensuel réussi!");
    console.log("Nouveau total payé (TotalPaid):", hre.ethers.formatEther(agreement.totalPaid), "ETH");


    // --- 6. Informations finales ---
    console.log("\n=== Informations Finales ===");
    property = await contract.getProperty(propertyId);
    console.log("Propriété disponible après location : ", property.isAvailable ? "Oui" : "Non");
    
    const availableProperties = await contract.getAvailableProperties();
    console.log("Nombre de propriétés disponibles au total:", availableProperties.length);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });