const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("RealEstateRental", function () {
    let realEstateRental;
    let owner, landlord, tenant, tenant2;
    let propertyId, agreementId;
    
    const RENT_AMOUNT = ethers.parseEther("1.0"); // 1 ETH per month
    const SECURITY_DEPOSIT = ethers.parseEther("2.0"); // 2 ETH security deposit
    
    beforeEach(async function () {
        [owner, landlord, tenant, tenant2] = await ethers.getSigners();
        
        const RealEstateRental = await ethers.getContractFactory("RealEstateRental");
        realEstateRental = await RealEstateRental.deploy();
    });
    
    describe("Property Listing", function () {
        it("Should list a new property", async function () {
            const tx = await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const receipt = await tx.wait();
            const event = receipt.logs.find(log => {
                try {
                    return realEstateRental.interface.parseLog(log).name === "PropertyListed";
                } catch (e) {
                    return false;
                }
            });
            
            expect(event).to.not.be.undefined;
            
            const property = await realEstateRental.getProperty(1);
            expect(property.owner).to.equal(landlord.address);
            expect(property.rentPerMonth).to.equal(RENT_AMOUNT);
            expect(property.isAvailable).to.be.true;
        });
        
        it("Should fail if rent is zero", async function () {
            await expect(
                realEstateRental.connect(landlord).listProperty(
                    "123 Main Street",
                    "Description",
                    0,
                    SECURITY_DEPOSIT
                )
            ).to.be.revertedWith("Rent must be greater than 0");
        });
    });
    
    describe("Rental Agreement Creation", function () {
        beforeEach(async function () {
            await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            propertyId = 1;
        });
        
        it("Should create rental agreement with correct payment", async function () {
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            
            await expect(
                realEstateRental.connect(tenant).createRentalAgreement(
                    propertyId,
                    6, // 6 months
                    { value: totalPayment }
                )
            ).to.emit(realEstateRental, "AgreementCreated");
            
            const agreement = await realEstateRental.getRentalAgreement(1);
            expect(agreement.tenant).to.equal(tenant.address);
            expect(agreement.landlord).to.equal(landlord.address);
            expect(agreement.rentAmount).to.equal(RENT_AMOUNT);
            expect(agreement.status).to.equal(1); // ACTIVE
            
            const property = await realEstateRental.getProperty(propertyId);
            expect(property.isAvailable).to.be.false;
        });
        
        it("Should fail if payment amount is incorrect", async function () {
            await expect(
                realEstateRental.connect(tenant).createRentalAgreement(
                    propertyId,
                    6,
                    { value: RENT_AMOUNT } // Missing security deposit
                )
            ).to.be.revertedWith("Incorrect payment amount");
        });
        
        it("Should fail if owner tries to rent own property", async function () {
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            
            await expect(
                realEstateRental.connect(landlord).createRentalAgreement(
                    propertyId,
                    6,
                    { value: totalPayment }
                )
            ).to.be.revertedWith("Owner cannot rent own property");
        });
    });
    
    describe("Monthly Rent Payment", function () {
        beforeEach(async function () {
            await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            await realEstateRental.connect(tenant).createRentalAgreement(
                1,
                6,
                { value: totalPayment }
            );
            agreementId = 1;
        });
        
        it("Should accept monthly rent payment after 25 days", async function () {
            // Fast forward 26 days
            await time.increase(26 * 24 * 60 * 60);
            
            await expect(
                realEstateRental.connect(tenant).payMonthlyRent(agreementId, {
                    value: RENT_AMOUNT
                })
            ).to.emit(realEstateRental, "RentPaid");
            
            const agreement = await realEstateRental.getRentalAgreement(agreementId);
            expect(agreement.totalPaid).to.equal(RENT_AMOUNT * 2n);
        });
        
        it("Should fail if payment is too soon", async function () {
            await expect(
                realEstateRental.connect(tenant).payMonthlyRent(agreementId, {
                    value: RENT_AMOUNT
                })
            ).to.be.revertedWith("Too soon for next payment");
        });
        
        it("Should fail if wrong amount is sent", async function () {
            await time.increase(26 * 24 * 60 * 60);
            
            await expect(
                realEstateRental.connect(tenant).payMonthlyRent(agreementId, {
                    value: RENT_AMOUNT / 2n
                })
            ).to.be.revertedWith("Incorrect rent amount");
        });
    });
    
    describe("Agreement Completion", function () {
        beforeEach(async function () {
            await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            await realEstateRental.connect(tenant).createRentalAgreement(
                1,
                1, // 1 month for faster testing
                { value: totalPayment }
            );
            agreementId = 1;
        });
        
        it("Should complete agreement and return security deposit", async function () {
            // Fast forward past end date
            await time.increase(31 * 24 * 60 * 60);
            
            const tenantBalanceBefore = await ethers.provider.getBalance(tenant.address);
            
            await expect(
                realEstateRental.connect(tenant).completeAgreement(agreementId)
            ).to.emit(realEstateRental, "SecurityDepositReturned");
            
            const agreement = await realEstateRental.getRentalAgreement(agreementId);
            expect(agreement.status).to.equal(2); // COMPLETED
            
            const property = await realEstateRental.getProperty(1);
            expect(property.isAvailable).to.be.true;
        });
        
        it("Should fail if agreement has not expired", async function () {
            await expect(
                realEstateRental.connect(tenant).completeAgreement(agreementId)
            ).to.be.revertedWith("Agreement not yet expired");
        });
    });
    
    describe("Agreement Termination", function () {
        beforeEach(async function () {
            await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            await realEstateRental.connect(tenant).createRentalAgreement(
                1,
                6,
                { value: totalPayment }
            );
            agreementId = 1;
        });
        
        it("Should allow landlord to terminate and return deposit", async function () {
            await expect(
                realEstateRental.connect(landlord).terminateAgreement(agreementId)
            ).to.emit(realEstateRental, "AgreementTerminated")
              .and.to.emit(realEstateRental, "SecurityDepositReturned");
            
            const agreement = await realEstateRental.getRentalAgreement(agreementId);
            expect(agreement.status).to.equal(3); // TERMINATED
        });
        
        it("Should allow tenant to terminate but forfeit deposit", async function () {
            await expect(
                realEstateRental.connect(tenant).terminateAgreement(agreementId)
            ).to.emit(realEstateRental, "AgreementTerminated");
            
            const agreement = await realEstateRental.getRentalAgreement(agreementId);
            expect(agreement.status).to.equal(3); // TERMINATED
        });
    });
    
    describe("Dispute Management", function () {
        beforeEach(async function () {
            await realEstateRental.connect(landlord).listProperty(
                "123 Main Street, Paris",
                "Beautiful 2BR apartment",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const totalPayment = RENT_AMOUNT + SECURITY_DEPOSIT;
            await realEstateRental.connect(tenant).createRentalAgreement(
                1,
                6,
                { value: totalPayment }
            );
            agreementId = 1;
        });
        
        it("Should create a dispute", async function () {
            await expect(
                realEstateRental.connect(tenant).createDispute(
                    agreementId,
                    "Property has maintenance issues"
                )
            ).to.emit(realEstateRental, "DisputeCreated");
            
            const dispute = await realEstateRental.getDispute(1);
            expect(dispute.initiator).to.equal(tenant.address);
            expect(dispute.status).to.equal(0); // OPEN
            
            const agreement = await realEstateRental.getRentalAgreement(agreementId);
            expect(agreement.status).to.equal(4); // DISPUTED
        });
        
        it("Should resolve dispute in favor of landlord", async function () {
            await realEstateRental.connect(tenant).createDispute(
                agreementId,
                "Property has issues"
            );
            
            await expect(
                realEstateRental.connect(owner).resolveDispute(1, true)
            ).to.emit(realEstateRental, "DisputeResolved");
            
            const dispute = await realEstateRental.getDispute(1);
            expect(dispute.status).to.equal(1); // RESOLVED
        });
        
        it("Should resolve dispute in favor of tenant", async function () {
            await realEstateRental.connect(tenant).createDispute(
                agreementId,
                "Property has issues"
            );
            
            await expect(
                realEstateRental.connect(owner).resolveDispute(1, false)
            ).to.emit(realEstateRental, "DisputeResolved")
              .and.to.emit(realEstateRental, "SecurityDepositReturned");
        });
    });
    
    describe("View Functions", function () {
        it("Should get available properties", async function () {
            await realEstateRental.connect(landlord).listProperty(
                "Property 1",
                "Description 1",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            await realEstateRental.connect(landlord).listProperty(
                "Property 2",
                "Description 2",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const availableProperties = await realEstateRental.getAvailableProperties();
            expect(availableProperties.length).to.equal(2);
        });
        
        it("Should get landlord properties", async function () {
            await realEstateRental.connect(landlord).listProperty(
                "Property 1",
                "Description 1",
                RENT_AMOUNT,
                SECURITY_DEPOSIT
            );
            
            const properties = await realEstateRental.getLandlordProperties(landlord.address);
            expect(properties.length).to.equal(1);
            expect(properties[0]).to.equal(1);
        });
    });
});
