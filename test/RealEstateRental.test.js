const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RealEstateRental", function () {
  
  // Configuration initiale (Fixture) pour ne pas répéter le code de déploiement
  async function deployRentalFixture() {
    const [owner, landlord, tenant, otherAccount] = await ethers.getSigners();

    const RealEstateRental = await ethers.getContractFactory("RealEstateRental");
    const rentalContract = await RealEstateRental.deploy();

    return { rentalContract, owner, landlord, tenant, otherAccount };
  }

  // Enum simulé en JS (0 = MONTHLY, 1 = DAILY)
  const RentUnit = { MONTHLY: 0, DAILY: 1 };

  describe("Property Listing", function () {
    it("Should list a new property", async function () {
      const { rentalContract, landlord } = await loadFixture(deployRentalFixture);
      
      const rent = ethers.parseEther("1");
      const deposit = ethers.parseEther("2");

      // CORRECTION ICI : Ajout du 5ème argument (RentUnit.MONTHLY)
      await expect(rentalContract.connect(landlord).listProperty(
        "123 Main Street, Paris",
        "Beautiful 2BR apartment",
        rent,
        deposit,
        RentUnit.MONTHLY 
      )).to.emit(rentalContract, "PropertyListed")
        .withArgs(1, landlord.address, rent, RentUnit.MONTHLY);
    });

    it("Should fail if rent is zero", async function () {
      const { rentalContract, landlord } = await loadFixture(deployRentalFixture);
      
      // CORRECTION ICI : Ajout du 5ème argument
      await expect(rentalContract.connect(landlord).listProperty(
        "Addr", "Desc", 0, 0, RentUnit.MONTHLY
      )).to.be.revertedWith("Rent must be greater than 0");
    });
  });

  describe("Rental Agreement Creation", function () {
    async function listedPropertyFixture() {
      const { rentalContract, landlord, tenant, owner } = await loadFixture(deployRentalFixture);
      const rent = ethers.parseEther("1");
      const deposit = ethers.parseEther("0.5");
      
      // Listing initial correct
      await rentalContract.connect(landlord).listProperty("Addr", "Desc", rent, deposit, RentUnit.MONTHLY);
      return { rentalContract, landlord, tenant, rent, deposit, owner };
    }

    it("Should create rental agreement with correct payment", async function () {
      const { rentalContract, tenant, rent, deposit } = await loadFixture(listedPropertyFixture);
      
      const totalPay = rent + deposit;

      // CORRECTION ICI : reserveProperty prend maintenant (id, mois, jours_supplémentaires)
      // On ajoute le '0' à la fin pour les jours supplémentaires
      await expect(rentalContract.connect(tenant).reserveProperty(1, 6, 0, { value: totalPay }))
        .to.emit(rentalContract, "AgreementCreated");
        
      const agreement = await rentalContract.rentalAgreements(1);
      expect(agreement.status).to.equal(0); // PENDING_RESERVATION
    });
  });

  describe("Monthly Rent Payment", function () {
    async function activeAgreementFixture() {
      const data = await loadFixture(deployRentalFixture);
      const rent = ethers.parseEther("1");
      const deposit = ethers.parseEther("0.5");
      
      await data.rentalContract.connect(data.landlord).listProperty("A", "D", rent, deposit, RentUnit.MONTHLY);
      
      // Réservation (6 mois, 0 jours)
      await data.rentalContract.connect(data.tenant).reserveProperty(1, 6, 0, { value: rent + deposit });
      
      // Activation
      await data.rentalContract.connect(data.tenant).activateAgreement(1);
      
      return { ...data, rent };
    }

    it("Should accept monthly rent payment after 25 days", async function () {
      const { rentalContract, tenant, rent } = await loadFixture(activeAgreementFixture);

      // Avancer le temps de 26 jours
      await time.increase(26 * 24 * 60 * 60);

      // CORRECTION ICI : payRent(id, amountInUnits)
      await expect(rentalContract.connect(tenant).payRent(1, 1, { value: rent }))
        .to.emit(rentalContract, "RentPaid");
    });
  });

  describe("Agreement Termination", function () {
    async function activeAgreementFixture() {
        const data = await loadFixture(deployRentalFixture);
        const rent = ethers.parseEther("1");
        const deposit = ethers.parseEther("0.5");
        
        await data.rentalContract.connect(data.landlord).listProperty("A", "D", rent, deposit, RentUnit.MONTHLY);
        await data.rentalContract.connect(data.tenant).reserveProperty(1, 6, 0, { value: rent + deposit });
        await data.rentalContract.connect(data.tenant).activateAgreement(1);
        
        return { ...data, deposit };
    }

    it("Should allow tenant to terminate and return deposit to landlord (penalty)", async function () {
      const { rentalContract, tenant, landlord, deposit } = await loadFixture(activeAgreementFixture);

      // Si le locataire part, la caution va au propriétaire (Logique corrigée)
      await expect(rentalContract.connect(tenant).terminateAgreement(1))
        .to.changeEtherBalances(
            [rentalContract, landlord],
            [-deposit, deposit]
        );
    });
  });

  describe("Dispute Management", function () {
    async function activeAgreementFixture() {
        const data = await loadFixture(deployRentalFixture);
        const rent = ethers.parseEther("1");
        const deposit = ethers.parseEther("0.5");
        
        await data.rentalContract.connect(data.landlord).listProperty("A", "D", rent, deposit, RentUnit.MONTHLY);
        await data.rentalContract.connect(data.tenant).reserveProperty(1, 6, 0, { value: rent + deposit });
        await data.rentalContract.connect(data.tenant).activateAgreement(1);
        
        return { ...data };
    }

    it("Should create a dispute", async function () {
      const { rentalContract, landlord } = await loadFixture(activeAgreementFixture);
      
      await expect(rentalContract.connect(landlord).createDispute(1, "Tenant destroyed furniture"))
        .to.emit(rentalContract, "DisputeCreated")
        .withArgs(1, 1, landlord.address);
        
      const agreement = await rentalContract.rentalAgreements(1);
      expect(agreement.status).to.equal(4); // DISPUTED
    });
  });

  describe("View Functions", function () {
    it("Should get available properties", async function () {
      const { rentalContract, landlord } = await loadFixture(deployRentalFixture);
      
      await rentalContract.connect(landlord).listProperty("P1", "D1", 100, 100, RentUnit.MONTHLY);
      await rentalContract.connect(landlord).listProperty("P2", "D2", 100, 100, RentUnit.MONTHLY);
      
      // On rend P2 indisponible (via suppression logique)
      await rentalContract.connect(landlord).delistProperty(2);

      const available = await rentalContract.getAvailableProperties();
      expect(available.length).to.equal(1);
      expect(available[0]).to.equal(1); // Seule la propriété 1 est dispo
    });

    it("Should get landlord properties", async function () {
        const { rentalContract, landlord } = await loadFixture(deployRentalFixture);
        
        await rentalContract.connect(landlord).listProperty("P1", "D1", 100, 100, RentUnit.MONTHLY);
        
        const props = await rentalContract.getLandlordProperties(landlord.address);
        expect(props.length).to.equal(1);
        expect(props[0]).to.equal(1);
      });
  });
});