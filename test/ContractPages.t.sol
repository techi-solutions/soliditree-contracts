// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ContractPages.sol";

contract ContractPagesTest is Test {
    ContractPages public contractPages;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        contractPages = new ContractPages();
        contractPages.initialize(owner);
    }

    function getPageIdFromLogs() private returns (bytes32) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(entries.length > 0, "No logs were recorded");
        return bytes32(entries[0].topics[1]);
    }

    function testCreatePage() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        assertEq(contractPages.getPageOwner(pageId), user1);
        assertEq(contractPages.pageContractAddresses(pageId), contractAddress);
        assertEq(contractPages.pageContentHashes(pageId), contentHash);
        vm.stopPrank();
    }

    function testUpdatePageContentHash() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        bytes memory newContentHash = "0x5678";
        contractPages.updatePageContentHash(pageId, newContentHash);

        assertEq(contractPages.pageContentHashes(pageId), newContentHash);
        vm.stopPrank();
    }

    function testTransferPageOwnership() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        contractPages.transferPageOwnership(pageId, user2);

        assertEq(contractPages.getPageOwner(pageId), user2);
        vm.stopPrank();
    }

    function testDestroyPage() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        contractPages.destroyPage(pageId);

        assertEq(contractPages.getPageOwner(pageId), address(0));
        assertEq(contractPages.pageContractAddresses(pageId), address(0));
        assertEq(contractPages.pageContentHashes(pageId), "");
        vm.stopPrank();
    }

    function testReserveName() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        string memory name = "test-name";
        uint256 months = 1;
        uint256 cost = contractPages.calculateReservationCost(months, name);

        vm.deal(user1, cost);
        contractPages.reserveName{value: cost}(pageId, name, months);

        assertEq(contractPages.getReservedName(name), pageId);
        assertEq(contractPages.getPageName(pageId), name);
        vm.stopPrank();
    }

    function testReleaseName() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        string memory name = "test-name";
        uint256 months = 1;
        uint256 cost = contractPages.calculateReservationCost(months, name);

        vm.deal(user1, cost);
        contractPages.reserveName{value: cost}(pageId, name, months);

        contractPages.releaseName(name);

        assertEq(contractPages.getReservedName(name), bytes32(0));
        assertEq(contractPages.getPageName(pageId), "");
        vm.stopPrank();
    }

    function testDonate() public {
        uint256 donationAmount = 1 ether;
        vm.deal(user1, donationAmount);

        vm.prank(user1);
        contractPages.donate{value: donationAmount}();

        assertEq(address(contractPages).balance, donationAmount);
    }

    function testWithdraw() public {
        uint256 donationAmount = 1 ether;
        vm.deal(address(contractPages), donationAmount);

        address payoutAddress = address(0x1234);
        vm.prank(owner);
        contractPages.updatePayoutAddress(payoutAddress);

        vm.prank(owner);
        contractPages.withdraw(donationAmount);

        assertEq(address(contractPages).balance, 0);
        assertEq(payoutAddress.balance, donationAmount);
    }

    function testAdminCanWithdraw() public {
        uint256 donationAmount = 1 ether;
        vm.deal(address(contractPages), donationAmount);

        address payoutAddress = address(0x1234);
        vm.prank(owner);
        contractPages.updatePayoutAddress(payoutAddress);

        address admin = address(0x5678);
        vm.prank(owner);
        contractPages.grantRole(contractPages.PAGES_ADMIN_ROLE(), admin);

        vm.prank(admin);
        contractPages.withdraw(donationAmount);

        assertEq(address(contractPages).balance, 0);
        assertEq(payoutAddress.balance, donationAmount);
    }

    function testCannotCreatePageWithZeroAddress() public {
        vm.startPrank(user1);
        address contractAddress = address(0);
        bytes memory contentHash = "0x1234";

        vm.expectRevert("Invalid contract address");
        contractPages.createPage(contractAddress, contentHash);
        vm.stopPrank();
    }

    function testCannotUpdateNonExistentPage() public {
        vm.startPrank(user1);
        bytes32 nonExistentPageId = keccak256("non-existent");
        bytes memory newContentHash = "0x5678";

        vm.expectRevert("Only page owner can call this function");
        contractPages.updatePageContentHash(nonExistentPageId, newContentHash);
        vm.stopPrank();
    }

    function testCannotTransferOwnershipOfNonExistentPage() public {
        vm.startPrank(user1);
        bytes32 nonExistentPageId = keccak256("non-existent");

        vm.expectRevert("Page does not exist");
        contractPages.transferPageOwnership(nonExistentPageId, user2);
        vm.stopPrank();
    }

    function testCannotDestroyNonExistentPage() public {
        vm.startPrank(user1);
        bytes32 nonExistentPageId = keccak256("non-existent");

        vm.expectRevert("Page does not exist");
        contractPages.destroyPage(nonExistentPageId);
        vm.stopPrank();
    }

    function testCannotReserveExistingName() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        string memory name = "test-name";
        uint256 months = 1;
        uint256 cost = contractPages.calculateReservationCost(months, name);

        vm.deal(user1, cost * 2);
        contractPages.reserveName{value: cost}(pageId, name, months);

        vm.expectRevert("Name already reserved");
        contractPages.reserveName{value: cost}(pageId, name, months);
        vm.stopPrank();
    }

    function testCannotReleaseUnreservedName() public {
        vm.startPrank(user1);
        string memory name = "unreserved-name";

        vm.expectRevert("Only page owner, contract owner, or pages admin can perform this action");
        contractPages.releaseName(name);
        vm.stopPrank();
    }

    function testCannotWithdrawAsNonAdminOrOwner() public {
        uint256 donationAmount = 1 ether;
        vm.deal(address(contractPages), donationAmount);

        vm.prank(user1);
        vm.expectRevert("Only owner or pages admin can call this function");
        contractPages.withdraw(donationAmount);
    }

    function testCannotWithdrawMoreThanBalance() public {
        uint256 donationAmount = 1 ether;
        vm.deal(address(contractPages), donationAmount);

        vm.prank(owner);
        vm.expectRevert("Insufficient balance");
        contractPages.withdraw(donationAmount + 1);
    }

    function testCannotReserveNameWithInsufficientFunds() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();

        string memory name = "test-name";
        uint256 months = 1;
        uint256 cost = contractPages.calculateReservationCost(months, name);

        vm.deal(user1, cost - 1);
        vm.expectRevert("Insufficient payment");
        contractPages.reserveName{value: cost - 1}(pageId, name, months);
        vm.stopPrank();
    }

    function testCannotUpdatePageAsNonOwner() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();
        vm.stopPrank();

        vm.prank(user2);
        bytes memory newContentHash = "0x5678";
        vm.expectRevert("Only page owner can call this function");
        contractPages.updatePageContentHash(pageId, newContentHash);
    }

    function testCannotTransferPageOwnershipAsNonOwner() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("Not page owner");
        contractPages.transferPageOwnership(pageId, user2);
    }

    function testCannotDestroyPageAsNonOwner() public {
        vm.startPrank(user1);
        address contractAddress = address(0x123);
        bytes memory contentHash = "0x1234";

        vm.recordLogs();
        contractPages.createPage(contractAddress, contentHash);
        bytes32 pageId = getPageIdFromLogs();
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("Not page owner");
        contractPages.destroyPage(pageId);
    }

    function testCalculateReservationCost() public {
        // Test 1 month reservation for regular name
        uint256 cost = contractPages.calculateReservationCost(1, "regular-name");
        assertEq(cost, 0.005 ether, "1 month regular name cost incorrect");

        // Test 12 months reservation for regular name (20% discount)
        cost = contractPages.calculateReservationCost(12, "regular-name");
        assertEq(cost, 0.048 ether, "12 months regular name cost incorrect");

        // Test 1 month reservation for short name (10x multiplier)
        cost = contractPages.calculateReservationCost(1, "short");
        assertEq(cost, 0.05 ether, "1 month short name cost incorrect");

        // Test 12 months reservation for short name (10x multiplier and 20% discount)
        cost = contractPages.calculateReservationCost(12, "short");
        assertEq(cost, 0.48 ether, "12 months short name cost incorrect");

        // Test invalid reservation period
        vm.expectRevert("Invalid reservation period");
        contractPages.calculateReservationCost(6, "any-name");
    }

    function testCalculateReservationCostWithDifferentBaseCost() public {
        // Change the base reservation cost
        contractPages.updateReservationCost(0.01 ether);

        // Test 1 month reservation for regular name with new base cost
        uint256 cost = contractPages.calculateReservationCost(1, "regular-name");
        assertEq(cost, 0.01 ether, "1 month regular name cost incorrect with new base cost");

        // Test 12 months reservation for short name with new base cost
        cost = contractPages.calculateReservationCost(12, "short");
        assertEq(cost, 0.96 ether, "12 months short name cost incorrect with new base cost");
    }
}
