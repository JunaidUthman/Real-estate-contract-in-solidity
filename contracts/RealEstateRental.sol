// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RealEstateRental is ReentrancyGuard, Ownable {
    
    // Enums
    enum RentUnit {
        MONTHLY, // Loyer de base par mois
        DAILY    // Loyer de base par jour
    }

    enum AgreementStatus {
        PENDING_RESERVATION,// this state is when made the reservation but didnt get the key of the house yet
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

    // Structs
    struct Property {
        uint256 id;
        address payable owner;
        string propertyAddress;
        string description;
        uint256 rentBaseAmount; // Montant de base du loyer (par mois ou par jour) [NEW]
        RentUnit unit;          // Unité de loyer (MONTHLY ou DAILY) [NEW]
        uint256 securityDeposit;
        bool isAvailable;
        bool isActive;
    }
    
    struct RentalAgreement {
        uint256 agreementId;
        uint256 propertyId;
        address payable tenant;
        address payable landlord;
        uint256 rentAmount;      // Montant de base stocké (par mois ou par jour)
        RentUnit unit;           // Unité de loyer de l'accord [NEW]
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
    
    // State variables
    uint256 public propertyCounter;
    uint256 public agreementCounter;
    uint256 public disputeCounter;
    uint256 public platformFeePercentage = 2;
    // 2% platform fee
    uint256 public accumulatedPlatformFees;

    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => RentalAgreement) public rentalAgreements;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public landlordProperties;
    mapping(address => uint256[]) public tenantAgreements;
    
    // Events : an event is a special way for your smart contract to communicate with the outside world
    //When you “emit” an event, it’s like writing a log entry to the blockchain.
    event PropertyListed(uint256 indexed propertyId, address indexed owner, uint256 rentBaseAmount, RentUnit unit); // Mise à jour de l'event [UPDATED]
    event PropertyDelisted(uint256 indexed propertyId);
    event AgreementCreated(uint256 indexed agreementId, uint256 indexed propertyId, address tenant, address landlord);
    event AgreementActivated(uint256 indexed agreementId); // Nouveau event [NEW]
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
        require(_propertyId > 0 && properties[_propertyId].id == _propertyId, "Property does not exist");
        // Correction: utiliser l'ID pour vérifier l'existence
        _;
    }
    
    modifier agreementExists(uint256 _agreementId) {
        require(_agreementId > 0 && rentalAgreements[_agreementId].agreementId == _agreementId, "Agreement does not exist");
        // Correction: utiliser l'ID pour vérifier l'existence
        _;
    }
    
    // Property Management Functions
    function listProperty( // this function creates a new property owned by the msg.sender(landloard)
        string memory _propertyAddress,
        string memory _description,
        uint256 _rentBaseAmount,
        uint256 _securityDeposit,
        RentUnit _unit // Nouveau paramètre pour l'unité [NEW]
    ) external returns (uint256) {
        require(_rentBaseAmount > 0, "Rent must be greater than 0");
        // Suppression de l'exigence `require(_securityDeposit > 0, ...)` pour permettre $0 de dépôt. [UPDATED]
        
        propertyCounter++;
        properties[propertyCounter] = Property({
            id: propertyCounter,
            owner: payable(msg.sender),
            propertyAddress: _propertyAddress,
            description: _description,
            rentBaseAmount: _rentBaseAmount,
            unit: _unit, // Stockage de la nouvelle unité [NEW]
            securityDeposit: _securityDeposit,
            isAvailable: true,
            isActive: true
        });
        
        landlordProperties[msg.sender].push(propertyCounter);
        
        emit PropertyListed(propertyCounter, msg.sender, _rentBaseAmount, _unit); // Mise à jour de l'event [UPDATED]
        return propertyCounter;
    }
    
    function updateProperty(
        uint256 _propertyId,
        string memory _propertyAddress,
        string memory _description,
        uint256 _rentBaseAmount, // Renommé [UPDATED]
        uint256 _securityDeposit,
        bool _isAvailable,
        RentUnit _unit // Ajouté [NEW]
    ) external propertyExists(_propertyId) onlyPropertyOwner(_propertyId) {
        Property storage property = properties[_propertyId];
        require(property.isActive, "Property is not active");
        
        property.propertyAddress = _propertyAddress;
        property.description = _description;
        property.rentBaseAmount = _rentBaseAmount; // Renommé [UPDATED]
        property.securityDeposit = _securityDeposit;
        property.isAvailable = _isAvailable;
        property.unit = _unit; // Ajouté [NEW]
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
    function reserveProperty(
        uint256 _propertyId,
        uint256 _durationInMonths,
        uint256 _optionalAdditionalDays // Permet une durée précise en jours, même pour les mois [NEW]
    ) external payable propertyExists(_propertyId) nonReentrant returns (uint256) {
        Property storage property = properties[_propertyId];
        require(property.isAvailable, "Property not available");
        require(property.isActive, "Property not active");
        require(msg.sender != property.owner, "Owner cannot rent own property");
        require(_durationInMonths > 0 || _optionalAdditionalDays > 0, "Duration must be at least 1 day or 1 month"); // Ajustement [UPDATED]

        uint256 firstPaymentAmount;
        
        // Calcul du premier paiement (Le premier loyer + le dépôt)
        if (property.unit == RentUnit.MONTHLY) {
            // Pour les locations mensuelles, le 1er paiement est toujours 1 mois de loyer.
            firstPaymentAmount = property.rentBaseAmount;
        } else if (property.unit == RentUnit.DAILY) {
            // Pour les locations journalières, le 1er paiement est 1 jour de loyer.
            firstPaymentAmount = property.rentBaseAmount; 
        }

        // Le montant initial requis (Dépôt + 1er Loyer)
        uint256 totalInitialPayment = firstPaymentAmount + property.securityDeposit;
        require(msg.value == totalInitialPayment, "Payment mismatch: initial funds required for reservation");

        agreementCounter++;
        uint256 startDate = block.timestamp;
        
        // Calcul de la date de fin en utilisant les mois et les jours additionnels [UPDATED]
        uint256 endDate = startDate + (_durationInMonths * 30 days) + (_optionalAdditionalDays * 1 days);
        
        rentalAgreements[agreementCounter] = RentalAgreement({
            agreementId: agreementCounter,
            propertyId: _propertyId,
            tenant: payable(msg.sender),
            landlord: property.owner,
            rentAmount: property.rentBaseAmount, // Stocke le montant de base (par mois ou par jour)
            unit: property.unit, // Stocke l'unité de loyer
            securityDeposit: property.securityDeposit,
            startDate: startDate, // Date de début de l'Escrow
            endDate: endDate,
            lastPaymentDate: 0, // Pas de paiement transféré au Landlord
            status: AgreementStatus.PENDING_RESERVATION, // Statut de séquestre
            totalPaid: msg.value // Le montant total payé au contrat (pour le moment)
        });
        property.isAvailable = false;
        tenantAgreements[msg.sender].push(agreementCounter);
        
        // NOTE IMPORTANTE : AUCUN TRANSFERT AU PROPRIÉTAIRE ICI. L'Éther (msg.value) reste dans le contrat RealEstateRental.
        emit AgreementCreated(agreementCounter, _propertyId, msg.sender, property.owner);
        
        return agreementCounter;
    }


    function activateAgreement(uint256 _agreementId) 
        external 
        agreementExists(_agreementId) 
        nonReentrant 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(agreement.tenant == msg.sender, "Only tenant can activate agreement");
        require(agreement.status == AgreementStatus.PENDING_RESERVATION, "Agreement is not in PENDING_RESERVATION status");
        
        // Calcul du premier loyer payé lors de la réservation
        uint256 firstRentAmount;
        if (agreement.unit == RentUnit.MONTHLY) {
            firstRentAmount = agreement.rentAmount;
        } else if (agreement.unit == RentUnit.DAILY) {
            firstRentAmount = agreement.rentAmount; // Correspond au montant initial de 1 jour de loyer
        }
        
        // Mise à jour du statut
        agreement.status = AgreementStatus.ACTIVE;
        
        // Calcul de la commission
        uint256 platformFee = (firstRentAmount * platformFeePercentage) / 100;
        uint256 landlordAmount = firstRentAmount - platformFee;
        accumulatedPlatformFees += platformFee;
        
        // Transfert du premier loyer (net de frais) au propriétaire. 
        // Le Dépôt de garantie reste dans le contrat.
        agreement.landlord.transfer(landlordAmount);
        
        // Mise à jour de la date du dernier paiement (le premier paiement)
        agreement.lastPaymentDate = block.timestamp;
        
        // Mettre à jour totalPaid pour refléter uniquement les loyers (ou ajuster la sémantique si nécessaire)
        // Pour cet exemple, nous considérons le premier loyer comme payé au Landlord.
        emit RentPaid(_agreementId, firstRentAmount, block.timestamp);
        emit AgreementActivated(_agreementId); // Utilisation d'un événement plus sémantique pour l'activation [UPDATED]
    }
    
    function payRent( // Fonction générique pour le loyer mensuel ou journalier [UPDATED]
        uint256 _agreementId,
        uint256 _amountInUnits // Le nombre de mois ou de jours payés. 1 pour loyer mensuel, 1 pour loyer journalier. [NEW]
    ) external 
        payable 
        agreementExists(_agreementId) 
        nonReentrant 
    {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        require(agreement.tenant == msg.sender, "Not the tenant");
        require(agreement.status == AgreementStatus.ACTIVE, "Agreement not active");
        require(block.timestamp <= agreement.endDate, "Agreement expired");
        require(_amountInUnits > 0, "Amount must be greater than zero"); // Montant doit être > 0 [NEW]
        
        uint256 expectedPayment;

        if (agreement.unit == RentUnit.MONTHLY) {
            // Loyer mensuel : on s'attend à ce que _amountInUnits soit 1 pour un mois complet
            require(_amountInUnits == 1, "Monthly rent payment must be for 1 month");
            expectedPayment = agreement.rentAmount;
            
            // Vérification du temps minimum écoulé (25 jours pour le loyer mensuel) [NEW]
            require(
                block.timestamp >= agreement.lastPaymentDate + 25 days,
                "Too soon for next monthly payment"
            );

        } else if (agreement.unit == RentUnit.DAILY) {
            // Loyer journalier : on impose un paiement d'une seule journée par transaction. [MODIFIED]
            require(_amountInUnits == 1, "Daily rent payment must be for 1 day only"); // Nouvelle restriction
            expectedPayment = agreement.rentAmount * _amountInUnits; // Qui est simplement agreement.rentAmount
            
            // Vérification du temps minimum écoulé (1 jour pour le loyer journalier) [NEW]
             require(
                block.timestamp >= agreement.lastPaymentDate + 1 days,
                "Too soon for next daily payment"
            );
        }

        require(msg.value == expectedPayment, "Incorrect rent amount for the specified period");
        
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
        // Ce transfert est $0 si securityDeposit était $0.
        agreement.tenant.transfer(agreement.securityDeposit); 
        
        emit AgreementCompleted(_agreementId); // Événement pour la FIN réelle du contrat.
        if (agreement.securityDeposit > 0) { // Conditionnel pour l'event
            emit SecurityDepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
        }
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
        // Si tenant terminates, landlord keeps security deposit ($0 si dépôt nul)
        // Si landlord terminates, return security deposit to tenant ($0 si dépôt nul)
        if (msg.sender == agreement.landlord) {
            agreement.tenant.transfer(agreement.securityDeposit);
             if (agreement.securityDeposit > 0) { // Conditionnel pour l'event
                emit SecurityDepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
            }
        } else {
            agreement.landlord.transfer(agreement.securityDeposit); // Transfert $0 si dépôt nul
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
        // Transfert $0 si le dépôt est nul.
        if (_favorLandlord) {
            agreement.landlord.transfer(agreement.securityDeposit);
        } else {
            agreement.tenant.transfer(agreement.securityDeposit);
            if (agreement.securityDeposit > 0) { // Conditionnel pour l'event
                emit SecurityDepositReturned(dispute.agreementId, agreement.tenant, agreement.securityDeposit);
            }
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
        require(_newFeePercentage <= 10, "Fee too high");
        // Max 10%
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