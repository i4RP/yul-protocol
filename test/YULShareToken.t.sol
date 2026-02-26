// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULShareToken} from "../src/YULShareToken.sol";

contract YULShareTokenTest is Test {
    YULShareToken public token;
    address public minter = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function setUp() public {
        token = new YULShareToken(minter);
    }

    function test_constructor() public view {
        assertEq(token.name(), "YUL Corporation Share");
        assertEq(token.symbol(), "YUL");
        assertEq(token.minter(), minter);
        assertEq(token.totalSupply(), 0);
    }

    function test_constructor_revert_zeroAddress() public {
        vm.expectRevert(YULShareToken.ZeroAddress.selector);
        new YULShareToken(address(0));
    }

    function test_mint() public {
        vm.prank(minter);
        token.mint(user1, 1000e18);
        assertEq(token.balanceOf(user1), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_mint_revert_notMinter() public {
        vm.prank(user1);
        vm.expectRevert(YULShareToken.OnlyMinter.selector);
        token.mint(user1, 1000e18);
    }

    function test_burn() public {
        vm.prank(minter);
        token.mint(user1, 1000e18);

        vm.prank(minter);
        token.burn(user1, 500e18);
        assertEq(token.balanceOf(user1), 500e18);
        assertEq(token.totalSupply(), 500e18);
    }

    function test_burn_revert_notMinter() public {
        vm.prank(minter);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        vm.expectRevert(YULShareToken.OnlyMinter.selector);
        token.burn(user1, 500e18);
    }

    function test_setMinter() public {
        vm.prank(minter);
        token.setMinter(user1);
        assertEq(token.minter(), user1);
    }

    function test_setMinter_revert_notMinter() public {
        vm.prank(user1);
        vm.expectRevert(YULShareToken.OnlyMinter.selector);
        token.setMinter(user2);
    }

    function test_setMinter_revert_zeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(YULShareToken.ZeroAddress.selector);
        token.setMinter(address(0));
    }

    function test_transfer() public {
        vm.prank(minter);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.transfer(user2, 300e18);
        assertEq(token.balanceOf(user1), 700e18);
        assertEq(token.balanceOf(user2), 300e18);
    }

    function test_delegate() public {
        vm.prank(minter);
        token.mint(user1, 1000e18);

        vm.prank(user1);
        token.delegate(user1);
        assertEq(token.getVotes(user1), 1000e18);
    }
}
