// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RealEstateRental is ReentrancyGuard, Ownable {
    
    // Structs
    struct Property {
        uint256 id;
        address payable owner;
        string propertyAddress;
        string description;
        uint256 rentPerMonth;
        uint256 securityDeposit;
        bool isAvailable;
        bool isActive;
    }
    
    struct RentalAgreement {
        uint256 agreementId;
        uint256 propertyId;
        address payable tenant;
        address payable landlord;
        uint256 rentAmount;
        uint256 securityDeposit;
        uint256 startDate;
        uint256 endDate;
        uint256 lastPaymentDate;
        AgreementStatus status;
        uint256 totalPaid;
    }
    
    struct Dispute {
        uint256 disputeId;
        uint256 agreementId;
        address initiator;
        string reason;
        DisputeStatus status;
        uint256 createdAt;
    }
    
    // Enums
    enum AgreementStatus {
        PENDING,
        ACTIVE,
        COMPLETED,
        TERMINATED,
        DISPUTED
    }
    
    enum DisputeStatus {
        OPEN,
        RESOLVED,
        REJECTED
    }
    
    // State variables
    uint256 public propertyCounter;
    uint256 public agreementCounter;
    uint256 public disputeCounter;
    uint256 public platformFeePercentage = 2; // 2% platform fee
    uint256 public accumulatedPlatformFees;

    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => RentalAgreement) public rentalAgreements;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public landlordProperties;
    mapping(address => uint256[]) public tenantAgreements;
    
    // Events : an event is a special way for your smart contract to communicate with the outside world
    //When you “emit” an event, it’s like writing a log entry to the blockchain.
    event PropertyListed(uint256 indexed propertyId, address indexed owner, uint256 rentPerMonth);
    event PropertyDelisted(uint256 indexed propertyId);
    event AgreementCreated(uint256 indexed agreementId, uint256 indexed propertyId, address tenant, address landlord);
    event RentPaid(uint256 indexed agreementId, uint256 amount, uint256 timestamp);
    event AgreementCompleted(uint256 indexed agreementId);
    event AgreementTerminated(uint256 indexed agreementId, address terminatedBy);
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed agreementId, address initiator);
    event DisputeResolved(uint256 indexed disputeId, bool favorLandlord);
    event SecurityDepositReturned(uint256 indexed agreementId, address tenant, uint256 amount);
    
    constructor(){}
    
    // Modifiers
    modifier onlyPropertyOwner(uint256 _propertyId) {
        require(properties[_propertyId].owner == msg.sender, "Not property owner");
        _;
    }
    
    modifier propertyExists(uint256 _propertyId) {
        require(_propertyId > 0 && _propertyId <= propertyCounter, "Property does not exist");
        _;
    }
    
    modifier agreementExists(uint256 _agreementId) {
        require(_agreementId > 0 && _agreementId <= agreementCounter, "Agreement does not exist");
        _;
    }
    
    // Property Management Functions
    function listProperty( // this function creates a new property owned by the msg.sender(landloard)
        string memory _propertyAddress,
        string memory _description,
        uint256 _rentPerMonth,
        uint256 _securityDeposit
    ) external returns (uint256) {
        require(_rentPerMonth > 0, "Rent must be greater than 0");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        
        propertyCounter++;
        
        properties[propertyCounter] = Property({
            id: propertyCounter,
            owner: payable(msg.sender),
            propertyAddress: _propertyAddress,
            description: _description,
            rentPerMonth: _rentPerMonth,
            securityDeposit: _securityDeposit,
            isAvailable: true,
            isActive: true
        });
        
        landlordProperties[msg.sender].push(propertyCounter);
        
        emit PropertyListed(propertyCounter, msg.sender, _rentPerMonth);
        return propertyCounter;
    }
    
    function updateProperty(
        uint256 _propertyId,
        string memory _propertyAddress,
        string memory _description,
        uint256 _rentPerMonth,
        uint256 _securityDeposit,
        bool _isAvailable
    ) external propertyExists(_propertyId) onlyPropertyOwner(_propertyId) {
        Property storage property = properties[_propertyId];
        require(property.isActive, "Property is not active");
        
        property.propertyAddress = _propertyAddress;
        property.description = _description;
        property.rentPerMonth = _rentPerMonth;
        property.securityDeposit = _securityDeposit;
        property.isAvailable = _isAvailable;
    }
    
    function delistProperty(uint256 _propertyId) 
        external 
        propertyExists(_propertyId) 
        onlyPropertyOwner(_propertyId) 
    {
        properties[_propertyId].isActive = false;
        properties[_propertyId].isAvailable = false;
        emit PropertyDelisted(_propertyId);
    }
    
    // Rental Agreement Functions
    function createRentalAgreement(//the payable mark means that this function can receive ether(from the one who calls) throw msg.value, so we can use functions like transfare or send to redirect the money to another address
        uint256 _propertyId,
        uint256 _durationInMonths
        
    ) external payable propertyExists(_propertyId) nonReentrant {
        Property storage property = properties[_propertyId];
        require(property.isAvailable, "Property not available");
        require(property.isActive, "Property not active");
        require(msg.sender != property.owner, "Owner cannot rent own property");
        require(_durationInMonths > 0, "Duration must be at least 1 month");
        
        uint256 totalInitialPayment = property.rentPerMonth + property.securityDeposit;
        // Version avec message détaillé
        if (msg.value != totalInitialPayment) {
            revert(
                string(
                    abi.encodePacked(
                        "Payment mismatch. Required: ",
                        Strings.toString(totalInitialPayment),
                        " wei, Sent: ",
                        Strings.toString(msg.value),
                        " wei"
                    )
                )
            );
        }
        
        agreementCounter++;
        uint256 startDate = block.timestamp;
        uint256 endDate = startDate + (_durationInMonths * 30 days);
        
        rentalAgreements[agreementCounter] = RentalAgreement({
            agreementId: agreementCounter,
            propertyId: _propertyId,
            tenant: payable(msg.sender),
            landlord: property.owner,
            rentAmount: property.rentPerMonth,
            securityDeposit: property.securityDeposit,
            startDate: startDate,
            endDate: endDate,
            lastPaymentDate: startDate,
            status: AgreementStatus.ACTIVE,
            totalPaid: property.rentPerMonth
        });
        
        property.isAvailable = false;
        tenantAgreements[msg.sender].push(agreementCounter);
        
        // Transfer first month rent to landlord (minus platform fee)
        uint256 platformFee = (property.rentPerMonth * platformFeePercentage) / 100;
        uint256 landlordAmount = property.rentPerMonth - platformFee;
        accumulatedPlatformFees += platformFee;
        
        property.owner.transfer(landlordAmount);//this function transfers the landlordAmount(the amount is gonna be msg.value) to the property owner
        
        emit AgreementCreated(agreementCounter, _propertyId, msg.sender, property.owner);
        emit RentPaid(agreementCounter, property.rentPerMonth, block.timestamp);
    }
    
    function payMonthlyRent(uint256 _agreementId) 
        external 
        payable 
        agreementExists(_agreementId) 
        nonReentrant 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(agreement.tenant == msg.sender, "Not the tenant");
        require(agreement.status == AgreementStatus.ACTIVE, "Agreement not active");
        require(block.timestamp <= agreement.endDate, "Agreement expired");
        require(msg.value == agreement.rentAmount, "Incorrect rent amount");
        
        // Check if at least 25 days have passed since last payment
        // require(
        //     block.timestamp >= agreement.lastPaymentDate + 25 days,
        //     "Too soon for next payment"
        // );
        
        agreement.lastPaymentDate = block.timestamp;
        agreement.totalPaid += msg.value;
        
        // Transfer rent to landlord (minus platform fee)
        uint256 platformFee = (msg.value * platformFeePercentage) / 100;
        uint256 landlordAmount = msg.value - platformFee;
        accumulatedPlatformFees += platformFee;
        
        agreement.landlord.transfer(landlordAmount);
        
        emit RentPaid(_agreementId, msg.value, block.timestamp);
    }
    
    function completeAgreement(uint256 _agreementId) 
        external 
        agreementExists(_agreementId) 
        nonReentrant 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(
            msg.sender == agreement.tenant || msg.sender == agreement.landlord,
            "Not authorized"
        );
        require(agreement.status == AgreementStatus.ACTIVE, "Agreement not active");
        require(block.timestamp >= agreement.endDate, "Agreement not yet expired");
        
        agreement.status = AgreementStatus.COMPLETED;
        properties[agreement.propertyId].isAvailable = true;
        
        // Return security deposit to tenant
        agreement.tenant.transfer(agreement.securityDeposit);
        
        emit AgreementCompleted(_agreementId);
        emit SecurityDepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
    }
    
    function terminateAgreement(uint256 _agreementId) 
        external 
        agreementExists(_agreementId) 
        nonReentrant 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(
            msg.sender == agreement.tenant || msg.sender == agreement.landlord,
            "Not authorized"
        );
        require(agreement.status == AgreementStatus.ACTIVE, "Agreement not active");
        
        agreement.status = AgreementStatus.TERMINATED;
        properties[agreement.propertyId].isAvailable = true;
        
        // If tenant terminates, landlord keeps security deposit
        // If landlord terminates, return security deposit to tenant
        if (msg.sender == agreement.landlord) {
            agreement.tenant.transfer(agreement.securityDeposit);
            emit SecurityDepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
        } else {
            agreement.landlord.transfer(agreement.securityDeposit);
        }
        
        emit AgreementTerminated(_agreementId, msg.sender);
    }
    
    // Dispute Management Functions
    function createDispute(uint256 _agreementId, string memory _reason) 
        external 
        agreementExists(_agreementId) 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(
            msg.sender == agreement.tenant || msg.sender == agreement.landlord,
            "Not authorized"
        );
        require(
            agreement.status == AgreementStatus.ACTIVE || 
            agreement.status == AgreementStatus.COMPLETED,
            "Invalid agreement status"
        );
        
        disputeCounter++;
        
        disputes[disputeCounter] = Dispute({
            disputeId: disputeCounter,
            agreementId: _agreementId,
            initiator: msg.sender,
            reason: _reason,
            status: DisputeStatus.OPEN,
            createdAt: block.timestamp
        });
        
        agreement.status = AgreementStatus.DISPUTED;
        
        emit DisputeCreated(disputeCounter, _agreementId, msg.sender);
    }
    
    function resolveDispute(
        uint256 _disputeId,
        bool _favorLandlord
    ) external onlyOwner nonReentrant {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == DisputeStatus.OPEN, "Dispute not open");
        
        RentalAgreement storage agreement = rentalAgreements[dispute.agreementId];
        
        dispute.status = DisputeStatus.RESOLVED;
        agreement.status = AgreementStatus.COMPLETED;
        properties[agreement.propertyId].isAvailable = true;
        
        // Handle security deposit based on resolution
        if (_favorLandlord) {
            agreement.landlord.transfer(agreement.securityDeposit);
        } else {
            agreement.tenant.transfer(agreement.securityDeposit);
            emit SecurityDepositReturned(dispute.agreementId, agreement.tenant, agreement.securityDeposit);
        }
        
        emit DisputeResolved(_disputeId, _favorLandlord);
    }
    
    // View Functions
    function getProperty(uint256 _propertyId) 
        external 
        view 
        propertyExists(_propertyId) 
        returns (Property memory) 
    {
        return properties[_propertyId];
    }
    
    function getRentalAgreement(uint256 _agreementId) 
        external 
        view 
        agreementExists(_agreementId) 
        returns (RentalAgreement memory) 
    {
        return rentalAgreements[_agreementId];
    }
    
    function getDispute(uint256 _disputeId) 
        external 
        view 
        returns (Dispute memory) 
    {
        require(_disputeId > 0 && _disputeId <= disputeCounter, "Dispute does not exist");
        return disputes[_disputeId];
    }
    
    function getLandlordProperties(address _landlord) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return landlordProperties[_landlord];
    }
    
    function getTenantAgreements(address _tenant) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return tenantAgreements[_tenant];
    }
    
    function getAvailableProperties() external view returns (uint256[] memory) {
        uint256 availableCount = 0;
        
        // Count available properties
        for (uint256 i = 1; i <= propertyCounter; i++) {
            if (properties[i].isAvailable && properties[i].isActive) {
                availableCount++;
            }
        }
        
        // Create array of available property IDs
        uint256[] memory availableProperties = new uint256[](availableCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= propertyCounter; i++) {
            if (properties[i].isAvailable && properties[i].isActive) {
                availableProperties[index] = i;
                index++;
            }
        }
        
        return availableProperties;// this arry contains the ids of available properties
    }
    
    // Admin Functions
    function setPlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee too high"); // Max 10%
        platformFeePercentage = _newFeePercentage;
    }
    
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedPlatformFees;
        require(amount > 0, "No platform fees to withdraw");
        accumulatedPlatformFees = 0;
        payable(owner()).transfer(amount);
    }

    
    // Fallback function
    receive() external payable {}
}
