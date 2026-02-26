// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULCorporation} from "../src/YULCorporation.sol";
import {YULShareToken} from "../src/YULShareToken.sol";
import {YULGovernance} from "../src/YULGovernance.sol";
import {YULTreasury} from "../src/YULTreasury.sol";
import {YULDividendDistributor} from "../src/YULDividendDistributor.sol";
import {YULOfficerManager} from "../src/YULOfficerManager.sol";

contract YULCorporationTest is Test {
    YULCorporation public corporation;
    YULShareToken public shareToken;
    YULGovernance public governance;
    YULTreasury public treasury;
    YULDividendDistributor public dividendDistributor;
    YULOfficerManager public officerManager;

    address public founder;
    address public shareholder1 = address(0x10);
    address public shareholder2 = address(0x11);
    address public nonAuth = address(0x12);

    function setUp() public {
        founder = address(this);

        // Deploy corporation
        corporation = new YULCorporation("YUL Corporation", "Ethereum Network");

        // Deploy sub-modules
        shareToken = new YULShareToken(address(corporation));
        officerManager = new YULOfficerManager(address(corporation));
        treasury = new YULTreasury(address(corporation), address(corporation));
        dividendDistributor = new YULDividendDistributor(address(shareToken), address(corporation));
        governance = new YULGovernance(
            address(shareToken),
            address(corporation),
            100, // 1% threshold
            2000, // 20% quorum
            100, // 100 blocks voting period
            10 // 10 blocks delay
        );

        // Initialize
        corporation.initialize(
            address(shareToken),
            address(governance),
            payable(address(treasury)),
            address(dividendDistributor),
            address(officerManager)
        );
    }

    function test_constructor() public view {
        assertEq(corporation.name(), "YUL Corporation");
        assertEq(corporation.jurisdiction(), "Ethereum Network");
        assertEq(corporation.founder(), founder);
        assertTrue(corporation.active());
        assertTrue(corporation.initialized());
    }

    function test_initialize_revert_alreadyInitialized() public {
        vm.expectRevert(YULCorporation.AlreadyInitialized.selector);
        corporation.initialize(
            address(shareToken),
            address(governance),
            payable(address(treasury)),
            address(dividendDistributor),
            address(officerManager)
        );
    }

    function test_initialize_revert_notFounder() public {
        YULCorporation corp2 = new YULCorporation("Test", "Test");
        vm.prank(nonAuth);
        vm.expectRevert(YULCorporation.OnlyFounder.selector);
        corp2.initialize(
            address(shareToken),
            address(governance),
            payable(address(treasury)),
            address(dividendDistributor),
            address(officerManager)
        );
    }

    function test_issueShares_byFounder() public {
        corporation.issueShares(shareholder1, 1000e18, "Initial allocation");
        assertEq(shareToken.balanceOf(shareholder1), 1000e18);
    }

    function test_issueShares_revert_notAuthorized() public {
        vm.prank(nonAuth);
        vm.expectRevert(YULCorporation.OnlyGovernanceOrFounder.selector);
        corporation.issueShares(shareholder1, 1000e18, "Fail");
    }

    function test_issueShares_revert_zeroAddress() public {
        vm.expectRevert(YULCorporation.ZeroAddress.selector);
        corporation.issueShares(address(0), 1000e18, "Fail");
    }

    function test_issueShares_revert_zeroAmount() public {
        vm.expectRevert(YULCorporation.ZeroAmount.selector);
        corporation.issueShares(shareholder1, 0, "Fail");
    }

    function test_burnShares_byGovernance() public {
        corporation.issueShares(shareholder1, 1000e18, "Initial");

        vm.prank(address(governance));
        corporation.burnShares(shareholder1, 500e18, "Buyback");
        assertEq(shareToken.balanceOf(shareholder1), 500e18);
    }

    function test_burnShares_revert_notGovernance() public {
        corporation.issueShares(shareholder1, 1000e18, "Initial");

        vm.expectRevert(YULCorporation.OnlyGovernance.selector);
        corporation.burnShares(shareholder1, 500e18, "Fail");
    }

    function test_treasuryTransferEth() public {
        // Fund treasury
        vm.deal(address(treasury), 10 ether);

        vm.prank(address(governance));
        corporation.treasuryTransferEth(payable(shareholder1), 1 ether, "Payment");
        assertEq(shareholder1.balance, 1 ether);
    }

    function test_treasuryTransferEth_revert_notGovernance() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(nonAuth);
        vm.expectRevert(YULCorporation.OnlyGovernance.selector);
        corporation.treasuryTransferEth(payable(shareholder1), 1 ether, "Fail");
    }

    function test_receiveEth_forwardsToTreasury() public {
        vm.deal(address(this), 5 ether);
        (bool success,) = address(corporation).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(address(treasury).balance, 5 ether);
    }

    function test_dissolve() public {
        vm.prank(address(governance));
        corporation.dissolve();
        assertFalse(corporation.active());
    }

    function test_dissolve_revert_notGovernance() public {
        vm.prank(nonAuth);
        vm.expectRevert(YULCorporation.OnlyGovernance.selector);
        corporation.dissolve();
    }

    function test_issueShares_revert_afterDissolve() public {
        vm.prank(address(governance));
        corporation.dissolve();

        vm.expectRevert(YULCorporation.NotActive.selector);
        corporation.issueShares(shareholder1, 1000e18, "Fail");
    }

    function test_corporationInfo() public {
        corporation.issueShares(shareholder1, 1000e18, "Initial");
        vm.deal(address(treasury), 5 ether);

        (
            string memory _name,
            string memory _jurisdiction,
            uint256 _totalShares,
            uint256 _treasuryBalance,
            bool _isActive,
            uint256 _proposalCount
        ) = corporation.corporationInfo();

        assertEq(_name, "YUL Corporation");
        assertEq(_jurisdiction, "Ethereum Network");
        assertEq(_totalShares, 1000e18);
        assertEq(_treasuryBalance, 5 ether);
        assertTrue(_isActive);
        assertEq(_proposalCount, 0);
    }

    function test_appointOfficer() public {
        bytes32 ceoRole = officerManager.CEO_ROLE();
        vm.prank(address(governance));
        corporation.appointOfficer(ceoRole, shareholder1);

        assertEq(officerManager.officerOf(ceoRole), shareholder1);
    }

    function test_addDirector() public {
        vm.prank(address(governance));
        corporation.addDirector(shareholder1);

        assertTrue(officerManager.isDirector(shareholder1));
    }

    function test_removeDirector() public {
        vm.startPrank(address(governance));
        corporation.addDirector(shareholder1);
        corporation.removeDirector(shareholder1);
        vm.stopPrank();

        assertFalse(officerManager.isDirector(shareholder1));
    }

    function test_updateGovernanceParameters() public {
        vm.prank(address(governance));
        corporation.updateGovernanceParameters(200, 3000, 200, 20);

        assertEq(governance.proposalThresholdBps(), 200);
        assertEq(governance.quorumBps(), 3000);
    }
}
