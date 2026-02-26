// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YULShareToken} from "./YULShareToken.sol";

/**
 * @title YULGovernance
 * @notice Governance contract for the YUL Corporation.
 *         Shareholders can create and vote on proposals to manage the corporation.
 * @dev Voting power is proportional to share ownership.
 *      Proposals have a voting period and require a quorum to pass.
 */
contract YULGovernance is ReentrancyGuard {
    /// @notice The YUL share token used for voting weight
    YULShareToken public immutable shareToken;

    /// @notice The corporation contract that executes approved proposals
    address public corporation;

    /// @notice Minimum shares required to create a proposal (basis points of total supply)
    uint256 public proposalThresholdBps;

    /// @notice Minimum participation required for a vote to be valid (basis points)
    uint256 public quorumBps;

    /// @notice Duration of the voting period in blocks
    uint256 public votingPeriod;

    /// @notice Delay before voting starts after proposal creation (in blocks)
    uint256 public votingDelay;

    /// @notice Counter for proposal IDs
    uint256 public proposalCount;

    /// @notice Proposal status
    enum ProposalState {
        Pending, // Created but voting hasn't started
        Active, // Voting is open
        Defeated, // Voting ended, did not pass
        Succeeded, // Voting ended, passed
        Executed, // Proposal was executed
        Cancelled // Proposal was cancelled
    }

    /// @notice Types of proposals
    enum ProposalType {
        General, // General governance proposal
        OfficerElection, // Elect/remove an officer
        DividendDistribution, // Distribute dividends
        TreasurySpending, // Spend from treasury
        ParameterChange // Change governance parameters
    }

    /// @notice Proposal data
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string description;
        // Execution data
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        // Voting
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 totalSharesAtCreation;
        // State
        bool executed;
        bool cancelled;
    }

    /// @notice Mapping from proposal ID to Proposal
    mapping(uint256 => Proposal) public proposals;

    /// @notice Mapping from proposal ID to voter address to whether they have voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    /// @notice Mapping from proposal ID to voter address to their vote weight
    mapping(uint256 => mapping(address => uint256)) public voteWeight;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description,
        uint256 startBlock,
        uint256 endBlock
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event CorporationUpdated(address indexed previousCorporation, address indexed newCorporation);
    event ParametersUpdated(uint256 proposalThresholdBps, uint256 quorumBps, uint256 votingPeriod, uint256 votingDelay);

    // Errors
    error OnlyCorporation();
    error InsufficientShares();
    error InvalidProposal();
    error ProposalNotActive();
    error AlreadyVoted();
    error InvalidVoteType();
    error ProposalNotSucceeded();
    error ProposalAlreadyExecuted();
    error ExecutionFailed();
    error OnlyProposer();
    error ProposalNotPending();
    error ArrayLengthMismatch();
    error ZeroAddress();
    error InvalidParameter();

    modifier onlyCorporation() {
        if (msg.sender != corporation) revert OnlyCorporation();
        _;
    }

    /**
     * @param _shareToken Address of the YUL share token
     * @param _corporation Address of the corporation contract
     * @param _proposalThresholdBps Minimum shares to propose (in basis points, e.g., 100 = 1%)
     * @param _quorumBps Quorum requirement (in basis points, e.g., 2000 = 20%)
     * @param _votingPeriod Number of blocks for voting
     * @param _votingDelay Number of blocks before voting starts
     */
    constructor(
        address _shareToken,
        address _corporation,
        uint256 _proposalThresholdBps,
        uint256 _quorumBps,
        uint256 _votingPeriod,
        uint256 _votingDelay
    ) {
        if (_shareToken == address(0)) revert ZeroAddress();
        if (_corporation == address(0)) revert ZeroAddress();
        if (_proposalThresholdBps > 10000) revert InvalidParameter();
        if (_quorumBps > 10000) revert InvalidParameter();

        shareToken = YULShareToken(_shareToken);
        corporation = _corporation;
        proposalThresholdBps = _proposalThresholdBps;
        quorumBps = _quorumBps;
        votingPeriod = _votingPeriod;
        votingDelay = _votingDelay;
    }

    /**
     * @notice Create a new proposal
     * @param proposalType Type of the proposal
     * @param description Description of the proposal
     * @param targets Target contract addresses for execution
     * @param values ETH values for each call
     * @param calldatas Encoded function calls
     * @return proposalId The ID of the created proposal
     */
    function propose(
        ProposalType proposalType,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external returns (uint256 proposalId) {
        if (targets.length != values.length || values.length != calldatas.length) {
            revert ArrayLengthMismatch();
        }
        if (targets.length == 0) revert InvalidProposal();

        uint256 totalSupply = shareToken.totalSupply();
        uint256 proposerBalance = shareToken.balanceOf(msg.sender);
        uint256 threshold = (totalSupply * proposalThresholdBps) / 10000;

        if (proposerBalance < threshold) revert InsufficientShares();

        proposalId = ++proposalCount;
        uint256 startBlock = block.number + votingDelay;
        uint256 endBlock = startBlock + votingPeriod;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.proposalType = proposalType;
        proposal.description = description;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.startBlock = startBlock;
        proposal.endBlock = endBlock;
        proposal.totalSharesAtCreation = totalSupply;

        emit ProposalCreated(proposalId, msg.sender, proposalType, description, startBlock, endBlock);
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId The proposal to vote on
     * @param support 0 = Against, 1 = For, 2 = Abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        if (support > 2) revert InvalidVoteType();

        Proposal storage proposal = proposals[proposalId];
        if (state(proposalId) != ProposalState.Active) revert ProposalNotActive();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        uint256 weight = shareToken.balanceOf(msg.sender);
        if (weight == 0) revert InsufficientShares();

        hasVoted[proposalId][msg.sender] = true;
        voteWeight[proposalId][msg.sender] = weight;

        if (support == 0) {
            proposal.againstVotes += weight;
        } else if (support == 1) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Execute a succeeded proposal
     * @param proposalId The proposal to execute
     */
    function execute(uint256 proposalId) external nonReentrant {
        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded();

        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(proposal.calldatas[i]);
            if (!success) revert ExecutionFailed();
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a pending proposal (only by proposer)
     * @param proposalId The proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (msg.sender != proposal.proposer) revert OnlyProposer();
        if (proposal.executed || proposal.cancelled) revert ProposalAlreadyExecuted();

        proposal.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Get the current state of a proposal
     * @param proposalId The proposal ID
     * @return The current state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.cancelled) return ProposalState.Cancelled;
        if (proposal.executed) return ProposalState.Executed;
        if (block.number < proposal.startBlock) return ProposalState.Pending;
        if (block.number <= proposal.endBlock) return ProposalState.Active;

        // Voting has ended - check results
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 quorumRequired = (proposal.totalSharesAtCreation * quorumBps) / 10000;

        if (totalVotes < quorumRequired) return ProposalState.Defeated;
        if (proposal.forVotes > proposal.againstVotes) return ProposalState.Succeeded;

        return ProposalState.Defeated;
    }

    /**
     * @notice Get proposal execution data
     * @param proposalId The proposal ID
     * @return targets Target addresses
     * @return values ETH values
     * @return calldatas Encoded calls
     */
    function getProposalActions(uint256 proposalId)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.targets, proposal.values, proposal.calldatas);
    }

    /**
     * @notice Update governance parameters. Only callable by corporation.
     * @param _proposalThresholdBps New proposal threshold in basis points
     * @param _quorumBps New quorum in basis points
     * @param _votingPeriod New voting period in blocks
     * @param _votingDelay New voting delay in blocks
     */
    function setParameters(
        uint256 _proposalThresholdBps,
        uint256 _quorumBps,
        uint256 _votingPeriod,
        uint256 _votingDelay
    ) external onlyCorporation {
        if (_proposalThresholdBps > 10000) revert InvalidParameter();
        if (_quorumBps > 10000) revert InvalidParameter();

        proposalThresholdBps = _proposalThresholdBps;
        quorumBps = _quorumBps;
        votingPeriod = _votingPeriod;
        votingDelay = _votingDelay;

        emit ParametersUpdated(_proposalThresholdBps, _quorumBps, _votingPeriod, _votingDelay);
    }

    /**
     * @notice Update the corporation address. Only callable by current corporation.
     * @param _newCorporation New corporation address
     */
    function setCorporation(address _newCorporation) external onlyCorporation {
        if (_newCorporation == address(0)) revert ZeroAddress();
        emit CorporationUpdated(corporation, _newCorporation);
        corporation = _newCorporation;
    }
}
