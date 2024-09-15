// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract ContractPages is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    ////////////////////////////////
    // VARIABLES
    bytes32 public constant PAGES_ADMIN_ROLE = keccak256("PAGES_ADMIN_ROLE");

    address private _payoutAddress;

    mapping(bytes32 => address) public pageOwners;
    mapping(address => uint256) public pageOwnerCounter;
    mapping(bytes32 => address) public pageContractAddresses;
    mapping(bytes32 => bytes) public pageContentHashes;

    mapping(address => bool) private blacklistedAddresses;

    mapping(string => bytes32) private _reservedNames;
    mapping(bytes32 => string) private _pageNames;

    uint256 public reservationCostPerMonth;
    uint256 public constant RESERVATION_DISCOUNT_12_MONTHS = 20; // 20% discount

    mapping(bytes32 => uint256) public nameReservationExpiry;

    ////////////////////////////////
    // EVENTS

    event PageCreated(
        bytes32 indexed pageId,
        address indexed owner,
        address indexed contractAddress
    );
    event PageContentHashUpdated(
        bytes32 indexed pageId,
        bytes indexed contentHash
    );
    event PageOwnershipTransferred(
        bytes32 indexed pageId,
        address indexed owner,
        address indexed newOwner
    );
    event PageDestroyed(bytes32 indexed pageId, address caller);

    event NameReserved(
        bytes32 indexed pageId,
        string name,
        uint256 expiryTimestamp
    );
    event NameReleased(bytes32 indexed pageId, string name);

    event ReservationCostUpdated(uint256 newCost);

    ////////////////////////////////
    // CONSTRUCTOR

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        _setRoleAdmin(PAGES_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(PAGES_ADMIN_ROLE, _owner);

        reservationCostPerMonth = 0.1 ether; // Set initial cost
    }

    ////////////////////////////////
    // FUNCTIONS

    /**
     * @dev Creates a new page with the given owner, contract address, and content hash.
     * @param _contractAddress The address of the contract associated with the page.
     * @param _contentHash The content hash of the page.
     * @notice This function can only be called by addresses that are not blacklisted.
     */
    function createPage(
        address _contractAddress,
        bytes memory _contentHash
    ) public onlyNotBlacklisted {
        require(_contractAddress != address(0), "Invalid contract address");
        bytes32 _pageId = nextPageId(msg.sender, _contractAddress);
        pageOwners[_pageId] = msg.sender;
        pageOwnerCounter[msg.sender]++;
        pageContractAddresses[_pageId] = _contractAddress;
        pageContentHashes[_pageId] = _contentHash;
        emit PageCreated(_pageId, msg.sender, _contractAddress);
    }

    /**
     * @dev Updates the content hash of an existing page.
     * @param _pageId The unique identifier of the page.
     * @param _contentHash The new content hash for the page.
     * @notice This function can only be called by the page owner and addresses that are not blacklisted.
     */
    function updatePageContentHash(
        bytes32 _pageId,
        bytes memory _contentHash
    ) public onlyPageOwner(_pageId) onlyNotBlacklisted {
        // Check if the page exists
        require(pageExists(_pageId), "Page does not exist");

        // Update the content hash
        pageContentHashes[_pageId] = _contentHash;

        emit PageContentHashUpdated(_pageId, _contentHash);
    }

    /**
     * @dev Transfers ownership of a page to a new address.
     * @param _pageId The unique identifier of the page.
     * @param _newOwner The address of the new owner.
     * @notice This function can only be called by the current page owner and addresses that are not blacklisted.
     */
    function transferPageOwnership(bytes32 _pageId, address _newOwner) public {
        require(pageExists(_pageId), "Page does not exist");
        require(msg.sender == pageOwners[_pageId], "Not page owner");
        pageOwners[_pageId] = _newOwner;
        emit PageOwnershipTransferred(_pageId, msg.sender, _newOwner);
    }

    /**
     * @dev Destroys a page, removing all associated data.
     * @param _pageId The unique identifier of the page to be destroyed.
     * @notice This function can only be called by the contract owner or the page owner, and addresses that are not blacklisted.
     */
    function destroyPage(bytes32 _pageId) public {
        require(pageExists(_pageId), "Page does not exist");
        require(msg.sender == pageOwners[_pageId], "Not page owner");

        delete pageOwners[_pageId];
        delete pageContractAddresses[_pageId];
        delete pageContentHashes[_pageId];

        // If the page has a reserved name, release it
        if (bytes(_pageNames[_pageId]).length > 0) {
            string memory name = _pageNames[_pageId];
            delete _reservedNames[name];
            delete _pageNames[_pageId];
        }

        emit PageDestroyed(_pageId, msg.sender);
    }

    function pageExists(bytes32 pageId) public view returns (bool) {
        return pageOwners[pageId] != address(0);
    }

    /**
     * @dev Adds an address to the blacklist.
     * @param _address The address to be blacklisted.
     * @notice This function can only be called by the contract owner or pages admin.
     */
    function blacklistAddress(address _address) public onlyOwnerOrPagesAdmin {
        blacklistedAddresses[_address] = true;
    }

    /**
     * @dev Removes an address from the blacklist.
     * @param _address The address to be removed from the blacklist.
     * @notice This function can only be called by the contract owner or pages admin.
     */
    function removeFromBlacklist(
        address _address
    ) public onlyOwnerOrPagesAdmin {
        blacklistedAddresses[_address] = false;
    }

    /**
     * @dev Reserves a name for a page with a specified duration.
     * @param _pageId The unique identifier of the page.
     * @param _name The name to be reserved (must be URL-safe).
     * @param _months The number of months to reserve the name for (1 or 12).
     * @notice This function can only be called by the page owner and addresses that are not blacklisted.
     */
    function reserveName(
        bytes32 _pageId,
        string memory _name,
        uint256 _months
    ) public payable onlyPageOwner(_pageId) onlyNotBlacklisted {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(getReservedName(_name) == bytes32(0), "Name already reserved");
        require(isUrlSafe(_name), "Name must be URL-safe");
        require(
            _months == 1 || _months == 12,
            "Reservation must be for 1 or 12 months"
        );

        uint256 cost = calculateReservationCost(_months);
        require(msg.value >= cost, "Insufficient payment");

        _reservedNames[_name] = _pageId;
        _pageNames[_pageId] = _name;

        uint256 expiryTimestamp = block.timestamp + (_months * 30 days);
        nameReservationExpiry[_pageId] = expiryTimestamp;

        emit NameReserved(_pageId, _name, expiryTimestamp);

        // Refund excess payment
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    /**
     * @dev Calculates the cost of name reservation based on the number of months.
     * @param _months The number of months for reservation (1 or 12).
     * @return The cost in wei for the reservation.
     */
    function calculateReservationCost(
        uint256 _months
    ) public view returns (uint256) {
        if (_months == 1) {
            return reservationCostPerMonth;
        } else if (_months == 12) {
            uint256 annualCost = reservationCostPerMonth * 12;
            uint256 discount = (annualCost * RESERVATION_DISCOUNT_12_MONTHS) /
                100;
            return annualCost - discount;
        } else {
            revert("Invalid reservation period");
        }
    }

    /**
     * @dev Releases a reserved name and refunds any remaining time.
     * @param _name The name to be released.
     * @notice This function can only be called by the page owner of the reserved name and addresses that are not blacklisted.
     */
    function releaseName(string memory _name) public onlyNotBlacklisted {
        bytes32 pageId = getReservedName(_name);
        require(pageId != bytes32(0), "Name not reserved");
        require(
            msg.sender == pageOwners[pageId] ||
                msg.sender == owner() ||
                hasRole(PAGES_ADMIN_ROLE, msg.sender),
            "Only page owner, contract owner, or pages admin can release the name"
        );

        delete _reservedNames[_name];
        delete _pageNames[pageId];
        delete nameReservationExpiry[pageId];

        emit NameReleased(pageId, _name);
    }

    /**
     * @dev Checks if a string is URL-safe.
     * @param _str The string to check.
     * @return bool True if the string is URL-safe, false otherwise.
     */
    function isUrlSafe(string memory _str) internal pure returns (bool) {
        bytes memory strBytes = bytes(_str);
        for (uint i = 0; i < strBytes.length; i++) {
            bytes1 char = strBytes[i];
            if (
                !(char >= 0x30 && char <= 0x39) && // 0-9
                !(char >= 0x41 && char <= 0x5A) && // A-Z
                !(char >= 0x61 && char <= 0x7A) && // a-z
                !(char == 0x2D) && // -
                !(char == 0x5F) // _
            ) {
                return false;
            }
        }
        return true;
    }

    ////////////////////////////////
    // VIEW FUNCTIONS

    function nextPageId(
        address _owner,
        address _contractAddress
    ) public view returns (bytes32) {
        uint256 _counter = pageOwnerCounter[_owner] + 1;
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    _owner,
                    _contractAddress,
                    _counter
                )
            );
    }

    function getPageOwner(bytes32 _pageId) public view returns (address) {
        return pageOwners[_pageId];
    }

    /**
     * @dev Returns the pageId associated with a reserved name, or bytes32(0) if expired or not reserved.
     * @param _name The name to look up.
     * @return The pageId associated with the name, or bytes32(0) if expired or not reserved.
     */
    function getReservedName(
        string memory _name
    ) public view returns (bytes32) {
        bytes32 pageId = _reservedNames[_name];
        if (
            pageId != bytes32(0) &&
            block.timestamp > nameReservationExpiry[pageId]
        ) {
            return bytes32(0);
        }
        return pageId;
    }

    /**
     * @dev Returns the name associated with a pageId, or an empty string if expired or not set.
     * @param _pageId The pageId to look up.
     * @return The name associated with the pageId, or an empty string if expired or not set.
     */
    function getPageName(bytes32 _pageId) public view returns (string memory) {
        if (block.timestamp > nameReservationExpiry[_pageId]) {
            return "";
        }
        return _pageNames[_pageId];
    }

    ////////////////////////////////
    // MODIFIERS

    modifier onlyNotBlacklisted() {
        require(!blacklistedAddresses[msg.sender], "Address is blacklisted");
        _;
    }

    modifier onlyPageOwner(bytes32 _pageId) {
        require(
            msg.sender == pageOwners[_pageId],
            "Only page owner can call this function"
        );
        _;
    }

    modifier onlyOwnerOrPageOwner(bytes32 _pageId) {
        require(
            msg.sender == owner() || msg.sender == pageOwners[_pageId],
            "Only owner or page owner can call this function"
        );
        _;
    }

    modifier onlyPagesAdmin() {
        require(
            hasRole(PAGES_ADMIN_ROLE, msg.sender),
            "Only pages admin can call this function"
        );
        _;
    }

    modifier onlyOwnerOrPagesAdmin() {
        require(
            msg.sender == owner() || hasRole(PAGES_ADMIN_ROLE, msg.sender),
            "Only owner or pages admin can call this function"
        );
        _;
    }
    ////////////////////////////////
    // UPGRADE

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    ////////////////////////////////
    // ROLE FUNCTIONS

    function addPagesAdmin(address _newPagesAdmin) public onlyOwner {
        _grantRole(PAGES_ADMIN_ROLE, _newPagesAdmin);
    }

    ////////////////////////////////
    // ETH COLLECTION

    // Event to log ETH donations
    event DonationReceived(address indexed donor, uint256 amount);

    // This function allows people to donate to the contract
    function donate() external payable {
        emit DonationReceived(msg.sender, msg.value);
    }

    // This function allows the contract to receive ETH
    receive() external payable {
        // Optionally emit an event or perform some action
        emit FundsReceived(msg.sender, msg.value);
    }

    // This fallback function is called for all messages sent to the contract with no matching function signature
    // It also allows the contract to receive ETH
    fallback() external payable {
        // Optionally emit an event or perform some action
        emit FundsReceived(msg.sender, msg.value);
    }

    // Event to log ETH received
    event FundsReceived(address indexed sender, uint256 amount);

    // Function to withdraw ETH from the contract
    function withdraw(uint256 amount) public onlyOwnerOrPagesAdmin {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(_payoutAddress).transfer(amount);
        emit FundsWithdrawn(_payoutAddress, amount);
    }

    // modify payout address
    function updatePayoutAddress(address _newPayoutAddress) external onlyOwner {
        _payoutAddress = _newPayoutAddress;
    }

    // Event to log ETH withdrawn
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @dev Updates the reservation cost per month.
     * @param _newCost The new cost in wei for one month of reservation.
     * @notice This function can only be called by the contract owner.
     */
    function updateReservationCost(uint256 _newCost) public onlyOwner {
        reservationCostPerMonth = _newCost;
        emit ReservationCostUpdated(_newCost);
    }

    ////////////////////////////////
}
