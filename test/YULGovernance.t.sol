// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YULShareToken} from "../src/YULShareToken.sol";
import {YULGovernance} from "../src/YULGovernance.sol";

contract YULGovernanceTest is Test {
    YULShareToken public shareToken;
    YULGovernance public governance;
    address public minter = address(0x1);
    address public corporation = address(0x2);
    address public proposer = address(0x3);
    address public voter1 = address(0x4);
    address public voter2 = address(0x5);
    address public smallHolder = address(0x6);

    // Governance parameters
    uint256 constant PROPOSAL_THRESHOLD_BPS = 100; // 1%
    uint256 constant QUORUM_BPS = 2000; // 20%
    uint256 constant VOTING_PERIOD = 100; // 100 blocks for testing
    uint256 constant VOTING_DELAY = 10; // 10 blocks delay

    function setUp() public {
        shareToken = new YULShareToken(minter);
        governance = new YULGovernance(
            address(shareToken), corporation, PROPOSAL_THRESHOLD_BPS, QUORUM_BPS, VOTING_PERIOD, VOTING_DELAY
        );

        // Mint shares
        vm.startPrank(minter);
        shareToken.mint(proposer, 500e18); // 50%
        shareToken.mint(voter1, 300e18); // 30%
        shareToken.mint(voter2, 150e18); // 15%
        shareToken.mint(smallHolder, 50e18); // 5%
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(address(governance.shareToken()), address(shareToken));
        assertEq(governance.corporation(), corporation);
        assertEq(governance.proposalThresholdBps(), PROPOSAL_THRESHOLD_BPS);
        assertEq(governance.quorumBps(), QUORUM_BPS);
        assertEq(governance.votingPeriod(), VOTING_PERIOD);
        assertEq(governance.votingDelay(), VOTING_DELAY);
    }

    function test_constructor_revert_zeroShareToken() public {
        vm.expectRevert(YULGovernance.ZeroAddress.selector);
        new YULGovernance(address(0), corporation, 100, 2000, 100, 10);
    }

    function test_constructor_revert_invalidThreshold() public {
        vm.expectRevert(YULGovernance.InvalidParameter.selector);
        new YULGovernance(address(shareToken), corporation, 10001, 2000, 100, 10);
    }

    // Helper to create a basic proposal
    function _createProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(0x100);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposer);
        return governance.propose(YULGovernance.ProposalType.General, "Test proposal", targets, values, calldatas);
    }

    function test_propose() public {
        uint256 proposalId = _createProposal();
        assertEq(proposalId, 1);
        assertEq(governance.proposalCount(), 1);
        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Pending));
    }

    function test_propose_revert_insufficientShares() public {
        // SmallHolder has 5% but needs 1% (which they have), let's use address with 0 shares
        address noShares = address(0x99);
        address[] memory targets = new address[](1);
        targets[0] = address(0x100);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(noShares);
        vm.expectRevert(YULGovernance.InsufficientShares.selector);
        governance.propose(YULGovernance.ProposalType.General, "Fail", targets, values, calldatas);
    }

    function test_propose_revert_emptyTargets() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(proposer);
        vm.expectRevert(YULGovernance.InvalidProposal.selector);
        governance.propose(YULGovernance.ProposalType.General, "Fail", targets, values, calldatas);
    }

    function test_castVote() public {
        uint256 proposalId = _createProposal();

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Active));

        // Vote for
        vm.prank(proposer);
        governance.castVote(proposalId, 1);

        assertTrue(governance.hasVoted(proposalId, proposer));
        assertEq(governance.voteWeight(proposalId, proposer), 500e18);
    }

    function test_castVote_revert_notActive() public {
        uint256 proposalId = _createProposal();

        // Don't advance blocks - still Pending
        vm.prank(proposer);
        vm.expectRevert(YULGovernance.ProposalNotActive.selector);
        governance.castVote(proposalId, 1);
    }

    function test_castVote_revert_alreadyVoted() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.startPrank(proposer);
        governance.castVote(proposalId, 1);
        vm.expectRevert(YULGovernance.AlreadyVoted.selector);
        governance.castVote(proposalId, 1);
        vm.stopPrank();
    }

    function test_castVote_revert_invalidVoteType() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(proposer);
        vm.expectRevert(YULGovernance.InvalidVoteType.selector);
        governance.castVote(proposalId, 3);
    }

    function test_proposalSucceeds() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote for (50% + 30% = 80% for)
        vm.prank(proposer);
        governance.castVote(proposalId, 1);
        vm.prank(voter1);
        governance.castVote(proposalId, 1);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Succeeded));
    }

    function test_proposalDefeated_noQuorum() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only smallHolder votes (5% < 20% quorum)
        vm.prank(smallHolder);
        governance.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Defeated));
    }

    function test_proposalDefeated_moreAgainst() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote against majority
        vm.prank(proposer);
        governance.castVote(proposalId, 0); // Against (50%)
        vm.prank(voter1);
        governance.castVote(proposalId, 1); // For (30%)

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Defeated));
    }

    function test_cancel() public {
        uint256 proposalId = _createProposal();

        vm.prank(proposer);
        governance.cancel(proposalId);

        assertEq(uint8(governance.state(proposalId)), uint8(YULGovernance.ProposalState.Cancelled));
    }

    function test_cancel_revert_notProposer() public {
        uint256 proposalId = _createProposal();

        vm.prank(voter1);
        vm.expectRevert(YULGovernance.OnlyProposer.selector);
        governance.cancel(proposalId);
    }

    function test_setParameters() public {
        vm.prank(corporation);
        governance.setParameters(200, 3000, 200, 20);

        assertEq(governance.proposalThresholdBps(), 200);
        assertEq(governance.quorumBps(), 3000);
        assertEq(governance.votingPeriod(), 200);
        assertEq(governance.votingDelay(), 20);
    }

    function test_setParameters_revert_notCorporation() public {
        vm.prank(proposer);
        vm.expectRevert(YULGovernance.OnlyCorporation.selector);
        governance.setParameters(200, 3000, 200, 20);
    }

    function test_setCorporation() public {
        address newCorp = address(0x10);
        vm.prank(corporation);
        governance.setCorporation(newCorp);
        assertEq(governance.corporation(), newCorp);
    }

    function test_getProposalActions() public {
        uint256 proposalId = _createProposal();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            governance.getProposalActions(proposalId);
        assertEq(targets.length, 1);
        assertEq(targets[0], address(0x100));
        assertEq(values[0], 0);
        assertEq(calldatas[0], "");
    }
}
