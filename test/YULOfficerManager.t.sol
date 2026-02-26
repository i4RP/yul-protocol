// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULOfficerManager} from "../src/YULOfficerManager.sol";

contract YULOfficerManagerTest is Test {
    YULOfficerManager public manager;
    address public governance = address(0x1);
    address public ceo = address(0x2);
    address public cfo = address(0x3);
    address public secretary = address(0x4);
    address public director1 = address(0x5);
    address public director2 = address(0x6);
    address public nonGovernance = address(0x7);

    function setUp() public {
        manager = new YULOfficerManager(governance);
    }

    function test_constructor() public view {
        assertTrue(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), governance));
        assertTrue(manager.hasRole(manager.GOVERNANCE_ROLE(), governance));
    }

    function test_constructor_revert_zeroAddress() public {
        vm.expectRevert(YULOfficerManager.ZeroAddress.selector);
        new YULOfficerManager(address(0));
    }

    function test_appointOfficer_CEO() public {
        bytes32 ceoRole = manager.CEO_ROLE();
        vm.prank(governance);
        manager.appointOfficer(ceoRole, ceo);

        assertEq(manager.officerOf(ceoRole), ceo);
        assertTrue(manager.hasRole(ceoRole, ceo));
    }

    function test_appointOfficer_replaces_existing() public {
        vm.startPrank(governance);
        manager.appointOfficer(manager.CEO_ROLE(), ceo);
        manager.appointOfficer(manager.CEO_ROLE(), cfo);
        vm.stopPrank();

        assertEq(manager.officerOf(manager.CEO_ROLE()), cfo);
        assertFalse(manager.hasRole(manager.CEO_ROLE(), ceo));
        assertTrue(manager.hasRole(manager.CEO_ROLE(), cfo));
    }

    function test_appointOfficer_revert_notGovernance() public {
        bytes32 ceoRole = manager.CEO_ROLE();
        vm.prank(nonGovernance);
        vm.expectRevert();
        manager.appointOfficer(ceoRole, ceo);
    }

    function test_appointOfficer_revert_zeroAddress() public {
        bytes32 ceoRole = manager.CEO_ROLE();
        vm.prank(governance);
        vm.expectRevert(YULOfficerManager.ZeroAddress.selector);
        manager.appointOfficer(ceoRole, address(0));
    }

    function test_removeOfficer() public {
        vm.startPrank(governance);
        manager.appointOfficer(manager.CEO_ROLE(), ceo);
        manager.removeOfficer(manager.CEO_ROLE());
        vm.stopPrank();

        assertEq(manager.officerOf(manager.CEO_ROLE()), address(0));
        assertFalse(manager.hasRole(manager.CEO_ROLE(), ceo));
    }

    function test_addDirector() public {
        vm.prank(governance);
        manager.addDirector(director1);

        assertTrue(manager.isDirector(director1));
        assertTrue(manager.hasRole(manager.DIRECTOR_ROLE(), director1));
        assertEq(manager.directorCount(), 1);
    }

    function test_addDirector_revert_alreadyDirector() public {
        vm.startPrank(governance);
        manager.addDirector(director1);
        vm.expectRevert(YULOfficerManager.AlreadyDirector.selector);
        manager.addDirector(director1);
        vm.stopPrank();
    }

    function test_removeDirector() public {
        vm.startPrank(governance);
        manager.addDirector(director1);
        manager.addDirector(director2);
        assertEq(manager.directorCount(), 2);

        manager.removeDirector(director1);
        vm.stopPrank();

        assertFalse(manager.isDirector(director1));
        assertTrue(manager.isDirector(director2));
        assertEq(manager.directorCount(), 1);
    }

    function test_removeDirector_revert_notDirector() public {
        vm.prank(governance);
        vm.expectRevert(YULOfficerManager.NotDirector.selector);
        manager.removeDirector(director1);
    }

    function test_getDirectors() public {
        vm.startPrank(governance);
        manager.addDirector(director1);
        manager.addDirector(director2);
        vm.stopPrank();

        address[] memory directors = manager.getDirectors();
        assertEq(directors.length, 2);
    }

    function test_transferGovernance() public {
        address newGovernance = address(0x10);
        vm.prank(governance);
        manager.transferGovernance(newGovernance);

        assertTrue(manager.hasRole(manager.GOVERNANCE_ROLE(), newGovernance));
        assertFalse(manager.hasRole(manager.GOVERNANCE_ROLE(), governance));
    }

    function test_transferGovernance_revert_zeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(YULOfficerManager.ZeroAddress.selector);
        manager.transferGovernance(address(0));
    }
}
