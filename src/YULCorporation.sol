// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YULShareToken} from "./YULShareToken.sol";
import {YULGovernance} from "./YULGovernance.sol";
import {YULTreasury} from "./YULTreasury.sol";
import {YULDividendDistributor} from "./YULDividendDistributor.sol";
import {YULOfficerManager} from "./YULOfficerManager.sol";

/**
 * @title YULCorporation
 * @notice Main controller contract for the YUL for-profit corporation protocol.
 *         Coordinates all sub-modules: shares, governance, treasury, dividends, and officers.
 * @dev Acts as the central hub connecting all corporate modules.
 *      Deployed first, then sub-modules are deployed and linked via initialize().
 */
contract YULCorporation is ReentrancyGuard {
    /// @notice Corporation name
    string public name;

    /// @notice Corporation registration/jurisdiction info
    string public jurisdiction;

    /// @notice The share token contract
    YULShareToken public shareToken;

    /// @notice The governance contract
    YULGovernance public governance;

    /// @notice The treasury contract
    YULTreasury public treasury;

    /// @notice The dividend distributor contract
    YULDividendDistributor public dividendDistributor;

    /// @notice The officer manager contract
    YULOfficerManager public officerManager;

    /// @notice The founder/deployer address
    address public founder;

    /// @notice Whether the corporation has been initialized with all modules
    bool public initialized;

    /// @notice Whether the corporation is active
    bool public active;

    /// @notice Incorporation timestamp
    uint256 public incorporatedAt;

    // Events
    event CorporationIncorporated(string name, string jurisdiction, address founder);
    event CorporationInitialized(
        address shareToken, address governance, address treasury, address dividendDistributor, address officerManager
    );
    event SharesIssued(address indexed to, uint256 amount, string reason);
    event SharesBurned(address indexed from, uint256 amount, string reason);
    event DividendDistributed(uint256 amount, bool isEth);
    event CorporationDissolved(uint256 timestamp);

    // Errors
    error OnlyFounder();
    error OnlyGovernance();
    error OnlyGovernanceOrFounder();
    error AlreadyInitialized();
    error NotInitialized();
    error NotActive();
    error ZeroAddress();
    error ZeroAmount();

    modifier onlyFounder() {
        if (msg.sender != founder) revert OnlyFounder();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != address(governance)) revert OnlyGovernance();
        _;
    }

    modifier onlyGovernanceOrFounder() {
        if (msg.sender != address(governance) && msg.sender != founder) {
            revert OnlyGovernanceOrFounder();
        }
        _;
    }

    modifier whenInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    /**
     * @param _name Corporation name
     * @param _jurisdiction Jurisdiction/registration info
     */
    constructor(string memory _name, string memory _jurisdiction) {
        name = _name;
        jurisdiction = _jurisdiction;
        founder = msg.sender;
        incorporatedAt = block.timestamp;
        active = true;

        emit CorporationIncorporated(_name, _jurisdiction, msg.sender);
    }

    /**
     * @notice Initialize the corporation with all module contracts.
     *         Can only be called once by the founder.
     * @param _shareToken Address of the deployed YULShareToken
     * @param _governance Address of the deployed YULGovernance
     * @param _treasury Address of the deployed YULTreasury
     * @param _dividendDistributor Address of the deployed YULDividendDistributor
     * @param _officerManager Address of the deployed YULOfficerManager
     */
    function initialize(
        address _shareToken,
        address _governance,
        address payable _treasury,
        address _dividendDistributor,
        address _officerManager
    ) external onlyFounder {
        if (initialized) revert AlreadyInitialized();
        if (_shareToken == address(0)) revert ZeroAddress();
        if (_governance == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_dividendDistributor == address(0)) revert ZeroAddress();
        if (_officerManager == address(0)) revert ZeroAddress();

        shareToken = YULShareToken(_shareToken);
        governance = YULGovernance(_governance);
        treasury = YULTreasury(_treasury);
        dividendDistributor = YULDividendDistributor(_dividendDistributor);
        officerManager = YULOfficerManager(_officerManager);
        initialized = true;

        emit CorporationInitialized(_shareToken, _governance, _treasury, _dividendDistributor, _officerManager);
    }

    /**
     * @notice Issue new shares to an address. Only governance or founder (before governance is active).
     * @param to Recipient of the shares
     * @param amount Number of shares to issue
     * @param reason Reason for issuance
     */
    function issueShares(address to, uint256 amount, string calldata reason)
        external
        whenInitialized
        whenActive
        onlyGovernanceOrFounder
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        shareToken.mint(to, amount);
        emit SharesIssued(to, amount, reason);
    }

    /**
     * @notice Burn shares from an address. Only governance can call.
     * @param from Address to burn shares from
     * @param amount Number of shares to burn
     * @param reason Reason for burning
     */
    function burnShares(address from, uint256 amount, string calldata reason)
        external
        whenInitialized
        whenActive
        onlyGovernance
    {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        shareToken.burn(from, amount);
        emit SharesBurned(from, amount, reason);
    }

    /**
     * @notice Distribute ETH dividends from treasury to shareholders.
     *         Only governance can call.
     * @param amount Amount of ETH to distribute
     */
    function distributeEthDividend(uint256 amount) external whenInitialized whenActive onlyGovernance nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Transfer ETH from treasury to dividend distributor
        treasury.transferEth(payable(address(dividendDistributor)), amount, "Dividend distribution");

        // Note: The dividend distributor needs to be called separately to create the round
        emit DividendDistributed(amount, true);
    }

    /**
     * @notice Transfer ETH from treasury. Only governance can call.
     * @param to Recipient
     * @param amount Amount of ETH
     * @param reason Reason for the transfer
     */
    function treasuryTransferEth(address payable to, uint256 amount, string calldata reason)
        external
        whenInitialized
        whenActive
        onlyGovernance
    {
        treasury.transferEth(to, amount, reason);
    }

    /**
     * @notice Transfer ERC20 tokens from treasury. Only governance can call.
     * @param token Token address
     * @param to Recipient
     * @param amount Amount of tokens
     * @param reason Reason for the transfer
     */
    function treasuryTransferToken(address token, address to, uint256 amount, string calldata reason)
        external
        whenInitialized
        whenActive
        onlyGovernance
    {
        treasury.transferToken(token, to, amount, reason);
    }

    /**
     * @notice Appoint an officer. Only governance can call.
     * @param role The officer role
     * @param officer Address of the officer
     */
    function appointOfficer(bytes32 role, address officer) external whenInitialized whenActive onlyGovernance {
        officerManager.appointOfficer(role, officer);
    }

    /**
     * @notice Remove an officer. Only governance can call.
     * @param role The officer role to remove
     */
    function removeOfficer(bytes32 role) external whenInitialized whenActive onlyGovernance {
        officerManager.removeOfficer(role);
    }

    /**
     * @notice Add a director. Only governance can call.
     * @param director Address of the new director
     */
    function addDirector(address director) external whenInitialized whenActive onlyGovernance {
        officerManager.addDirector(director);
    }

    /**
     * @notice Remove a director. Only governance can call.
     * @param director Address of the director to remove
     */
    function removeDirector(address director) external whenInitialized whenActive onlyGovernance {
        officerManager.removeDirector(director);
    }

    /**
     * @notice Update governance parameters. Only governance can call.
     */
    function updateGovernanceParameters(
        uint256 proposalThresholdBps,
        uint256 quorumBps,
        uint256 votingPeriod,
        uint256 votingDelay
    ) external whenInitialized onlyGovernance {
        governance.setParameters(proposalThresholdBps, quorumBps, votingPeriod, votingDelay);
    }

    /**
     * @notice Dissolve the corporation. Only governance can call.
     *         This is an irreversible action.
     */
    function dissolve() external whenInitialized whenActive onlyGovernance {
        active = false;
        emit CorporationDissolved(block.timestamp);
    }

    /**
     * @notice Allow the corporation to receive ETH (forwards to treasury)
     */
    receive() external payable {
        if (initialized) {
            (bool success,) = address(treasury).call{value: msg.value}("");
            require(success, "Treasury forward failed");
        }
    }

    /**
     * @notice Get a summary of the corporation's state
     * @return _name Corporation name
     * @return _jurisdiction Jurisdiction
     * @return _totalShares Total shares outstanding
     * @return _treasuryBalance ETH in treasury
     * @return _isActive Whether the corporation is active
     * @return _proposalCount Number of governance proposals
     */
    function corporationInfo()
        external
        view
        whenInitialized
        returns (
            string memory _name,
            string memory _jurisdiction,
            uint256 _totalShares,
            uint256 _treasuryBalance,
            bool _isActive,
            uint256 _proposalCount
        )
    {
        return (
            name, jurisdiction, shareToken.totalSupply(), address(treasury).balance, active, governance.proposalCount()
        );
    }
}
