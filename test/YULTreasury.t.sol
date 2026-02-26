// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULTreasury} from "../src/YULTreasury.sol";

contract YULTreasuryTest is Test {
    YULTreasury public treasury;
    address public governance = address(0x1);
    address public corporation = address(0x2);
    address public recipient = address(0x3);
    address public nonAuth = address(0x4);

    function setUp() public {
        treasury = new YULTreasury(governance, corporation);
    }

    function test_constructor() public view {
        assertEq(treasury.governance(), governance);
        assertEq(treasury.corporation(), corporation);
    }

    function test_constructor_revert_zeroGovernance() public {
        vm.expectRevert(YULTreasury.ZeroAddress.selector);
        new YULTreasury(address(0), corporation);
    }

    function test_constructor_revert_zeroCorporation() public {
        vm.expectRevert(YULTreasury.ZeroAddress.selector);
        new YULTreasury(governance, address(0));
    }

    function test_receiveEth() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(treasury).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(treasury.ethBalance(), 5 ether);
        assertEq(treasury.totalEthReceived(), 5 ether);
    }

    function test_transferEth_byGovernance() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(governance);
        treasury.transferEth(payable(recipient), 3 ether, "Payment");

        assertEq(address(treasury).balance, 7 ether);
        assertEq(recipient.balance, 3 ether);
        assertEq(treasury.totalEthSpent(), 3 ether);
    }

    function test_transferEth_byCorporation() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(corporation);
        treasury.transferEth(payable(recipient), 3 ether, "Payment");

        assertEq(address(treasury).balance, 7 ether);
        assertEq(recipient.balance, 3 ether);
    }

    function test_transferEth_revert_notAuthorized() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(nonAuth);
        vm.expectRevert(YULTreasury.OnlyCorporationOrGovernance.selector);
        treasury.transferEth(payable(recipient), 3 ether, "Payment");
    }

    function test_transferEth_revert_insufficientBalance() public {
        vm.prank(governance);
        vm.expectRevert(YULTreasury.InsufficientBalance.selector);
        treasury.transferEth(payable(recipient), 1 ether, "Payment");
    }

    function test_transferEth_revert_zeroAddress() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(governance);
        vm.expectRevert(YULTreasury.ZeroAddress.selector);
        treasury.transferEth(payable(address(0)), 1 ether, "Payment");
    }

    function test_setGovernance() public {
        address newGov = address(0x10);
        vm.prank(governance);
        treasury.setGovernance(newGov);
        assertEq(treasury.governance(), newGov);
    }

    function test_setGovernance_revert_notGovernance() public {
        vm.prank(nonAuth);
        vm.expectRevert(YULTreasury.OnlyGovernance.selector);
        treasury.setGovernance(address(0x10));
    }

    function test_setCorporation() public {
        address newCorp = address(0x10);
        vm.prank(governance);
        treasury.setCorporation(newCorp);
        assertEq(treasury.corporation(), newCorp);
    }
}
