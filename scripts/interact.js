const hre = require("hardhat");
const fs = require("fs");

async function main() {
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("./deployment-info.json"));
    console.log("Interacting with contract at:", deploymentInfo.contractAddress);
    
    const [owner, landlord, tenant] = await hre.ethers.getSigners();
    
    const RealEstateRental = await hre.ethers.getContractFactory("RealEstateRental");
    const contract = RealEstateRental.attach(deploymentInfo.contractAddress);
    
    // Example 1: List a property
    console.log("\n=== Listing Property ===");
    const rentAmount = hre.ethers.parseEther("1.0");
    const securityDeposit = hre.ethers.parseEther("2.0");
    
    const listTx = await contract.connect(landlord).listProperty(
        "123 Avenue des Champs-Élysées, Paris",
        "Luxury 3BR apartment with Eiffel Tower view",
        rentAmount,
        securityDeposit
    );
    
    await listTx.wait();
    console.log("Property listed successfully!");
    
    // Get property details
    const property = await contract.getProperty(1);
    console.log("Property ID:", property.id.toString());
    console.log("Owner:", property.owner);
    console.log("Rent per month:", hre.ethers.formatEther(property.rentPerMonth), "ETH");
    
    // Example 2: Create rental agreement
    console.log("\n=== Creating Rental Agreement ===");
    const totalPayment = rentAmount + securityDeposit;
    
    const agreementTx = await contract.connect(tenant).createRentalAgreement(
        1, // property ID
        6, // 6 months duration
        { value: totalPayment }
    );
    
    await agreementTx.wait();
    console.log("Rental agreement created!");
    
    // Get agreement details
    const agreement = await contract.getRentalAgreement(1);
    console.log("Agreement ID:", agreement.agreementId.toString());
    console.log("Tenant:", agreement.tenant);
    console.log("Landlord:", agreement.landlord);
    console.log("Status:", agreement.status);
    
    // Example 3: Get available properties
    console.log("\n=== Available Properties ===");
    const availableProperties = await contract.getAvailableProperties();
    console.log("Number of available properties:", availableProperties.length);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
