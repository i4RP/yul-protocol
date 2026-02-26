// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULShareToken} from "../src/YULShareToken.sol";
import {YULDividendDistributor} from "../src/YULDividendDistributor.sol";

contract YULDividendDistributorTest is Test {
    YULShareToken public shareToken;
    YULDividendDistributor public distributor;
    address public minter = address(0x1);
    address public distributorAdmin = address(0x2);
    address public shareholder1 = address(0x3);
    address public shareholder2 = address(0x4);
    address public nonShareholder = address(0x5);

    function setUp() public {
        shareToken = new YULShareToken(minter);
        distributor = new YULDividendDistributor(address(shareToken), distributorAdmin);

        // Issue shares
        vm.startPrank(minter);
        shareToken.mint(shareholder1, 700e18); // 70%
        shareToken.mint(shareholder2, 300e18); // 30%
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(address(distributor.shareToken()), address(shareToken));
        assertEq(distributor.distributor(), distributorAdmin);
        assertEq(distributor.currentRoundId(), 0);
    }

    function test_constructor_revert_zeroShareToken() public {
        vm.expectRevert(YULDividendDistributor.ZeroAddress.selector);
        new YULDividendDistributor(address(0), distributorAdmin);
    }

    function test_distributeEth() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        assertEq(distributor.currentRoundId(), 1);
        (address token, uint256 totalAmount, uint256 totalShares,,, bool active) = distributor.rounds(1);
        assertEq(token, address(0));
        assertEq(totalAmount, 10 ether);
        assertEq(totalShares, 1000e18);
        assertTrue(active);
    }

    function test_distributeEth_revert_notDistributor() public {
        vm.deal(shareholder1, 10 ether);
        vm.prank(shareholder1);
        vm.expectRevert(YULDividendDistributor.OnlyDistributor.selector);
        distributor.distributeEth{value: 10 ether}();
    }

    function test_distributeEth_revert_zeroAmount() public {
        vm.prank(distributorAdmin);
        vm.expectRevert(YULDividendDistributor.ZeroAmount.selector);
        distributor.distributeEth{value: 0}();
    }

    function test_claimEth() public {
        // Distribute 10 ETH
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        // Shareholder1 claims (70% = 7 ETH)
        uint256 balanceBefore = shareholder1.balance;
        vm.prank(shareholder1);
        distributor.claim(1);

        assertEq(shareholder1.balance - balanceBefore, 7 ether);
        assertTrue(distributor.hasClaimed(1, shareholder1));
    }

    function test_claimEth_shareholder2() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        // Shareholder2 claims (30% = 3 ETH)
        uint256 balanceBefore = shareholder2.balance;
        vm.prank(shareholder2);
        distributor.claim(1);

        assertEq(shareholder2.balance - balanceBefore, 3 ether);
    }

    function test_claim_revert_alreadyClaimed() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        vm.startPrank(shareholder1);
        distributor.claim(1);
        vm.expectRevert(YULDividendDistributor.AlreadyClaimed.selector);
        distributor.claim(1);
        vm.stopPrank();
    }

    function test_claim_revert_noShares() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        vm.prank(nonShareholder);
        vm.expectRevert(YULDividendDistributor.NoSharesAtSnapshot.selector);
        distributor.claim(1);
    }

    function test_unclaimedDividend() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        assertEq(distributor.unclaimedDividend(1, shareholder1), 7 ether);
        assertEq(distributor.unclaimedDividend(1, shareholder2), 3 ether);
        assertEq(distributor.unclaimedDividend(1, nonShareholder), 0);
    }

    function test_unclaimedDividend_afterClaim() public {
        vm.deal(distributorAdmin, 10 ether);
        vm.prank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();

        vm.prank(shareholder1);
        distributor.claim(1);

        assertEq(distributor.unclaimedDividend(1, shareholder1), 0);
    }

    function test_claimMultiple() public {
        // Create two rounds
        vm.deal(distributorAdmin, 20 ether);
        vm.startPrank(distributorAdmin);
        distributor.distributeEth{value: 10 ether}();
        distributor.distributeEth{value: 10 ether}();
        vm.stopPrank();

        uint256 balanceBefore = shareholder1.balance;
        uint256[] memory roundIds = new uint256[](2);
        roundIds[0] = 1;
        roundIds[1] = 2;

        vm.prank(shareholder1);
        distributor.claimMultiple(roundIds);

        // 70% of 10 ETH * 2 rounds = 14 ETH
        assertEq(shareholder1.balance - balanceBefore, 14 ether);
    }

    function test_setDistributor() public {
        address newDistributor = address(0x10);
        vm.prank(distributorAdmin);
        distributor.setDistributor(newDistributor);
        assertEq(distributor.distributor(), newDistributor);
    }

    function test_setDistributor_revert_notDistributor() public {
        vm.prank(shareholder1);
        vm.expectRevert(YULDividendDistributor.OnlyDistributor.selector);
        distributor.setDistributor(address(0x10));
    }
}
