// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title YULOfficerManager
 * @notice Manages corporate officer roles for the YUL Corporation.
 *         Officers have specific permissions for corporate actions.
 * @dev Roles are managed via OpenZeppelin's AccessControl.
 *      The GOVERNANCE_ROLE is the admin for all officer roles and is
 *      assigned to the YULGovernance contract.
 */
contract YULOfficerManager is AccessControl {
    /// @notice Role that can manage officers (assigned to governance)
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice Chief Executive Officer - general corporate management
    bytes32 public constant CEO_ROLE = keccak256("CEO_ROLE");

    /// @notice Chief Financial Officer - treasury and financial management
    bytes32 public constant CFO_ROLE = keccak256("CFO_ROLE");

    /// @notice Secretary - corporate records and administration
    bytes32 public constant SECRETARY_ROLE = keccak256("SECRETARY_ROLE");

    /// @notice Director role - board member
    bytes32 public constant DIRECTOR_ROLE = keccak256("DIRECTOR_ROLE");

    /// @notice Mapping from role to current officer address (for single-holder roles)
    mapping(bytes32 => address) public officerOf;

    /// @notice List of all directors
    address[] private _directors;

    /// @notice Tracks whether an address is a director
    mapping(address => bool) public isDirector;

    // Events
    event OfficerAppointed(bytes32 indexed role, address indexed officer);
    event OfficerRemoved(bytes32 indexed role, address indexed officer);
    event DirectorAdded(address indexed director);
    event DirectorRemoved(address indexed director);

    // Errors
    error AlreadyDirector();
    error NotDirector();
    error ZeroAddress();

    /**
     * @param _governance Address of the governance contract (or initial admin)
     */
    constructor(address _governance) {
        if (_governance == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(GOVERNANCE_ROLE, _governance);

        // Set GOVERNANCE_ROLE as admin for all officer roles
        _setRoleAdmin(CEO_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(CFO_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(SECRETARY_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(DIRECTOR_ROLE, GOVERNANCE_ROLE);
    }

    /**
     * @notice Appoint an officer to a role. Only governance can call this.
     * @param role The officer role to assign
     * @param officer The address to appoint
     */
    function appointOfficer(bytes32 role, address officer) external onlyRole(GOVERNANCE_ROLE) {
        if (officer == address(0)) revert ZeroAddress();

        // If there's an existing officer in this role, revoke it first
        address currentOfficer = officerOf[role];
        if (currentOfficer != address(0)) {
            _revokeRole(role, currentOfficer);
        }

        officerOf[role] = officer;
        _grantRole(role, officer);
        emit OfficerAppointed(role, officer);
    }

    /**
     * @notice Remove an officer from a role. Only governance can call this.
     * @param role The officer role to remove
     */
    function removeOfficer(bytes32 role) external onlyRole(GOVERNANCE_ROLE) {
        address currentOfficer = officerOf[role];
        if (currentOfficer != address(0)) {
            _revokeRole(role, currentOfficer);
            officerOf[role] = address(0);
            emit OfficerRemoved(role, currentOfficer);
        }
    }

    /**
     * @notice Add a director to the board. Only governance can call this.
     * @param director Address of the new director
     */
    function addDirector(address director) external onlyRole(GOVERNANCE_ROLE) {
        if (director == address(0)) revert ZeroAddress();
        if (isDirector[director]) revert AlreadyDirector();

        isDirector[director] = true;
        _directors.push(director);
        _grantRole(DIRECTOR_ROLE, director);
        emit DirectorAdded(director);
    }

    /**
     * @notice Remove a director from the board. Only governance can call this.
     * @param director Address of the director to remove
     */
    function removeDirector(address director) external onlyRole(GOVERNANCE_ROLE) {
        if (!isDirector[director]) revert NotDirector();

        isDirector[director] = false;
        _revokeRole(DIRECTOR_ROLE, director);

        // Remove from array
        for (uint256 i = 0; i < _directors.length; i++) {
            if (_directors[i] == director) {
                _directors[i] = _directors[_directors.length - 1];
                _directors.pop();
                break;
            }
        }
        emit DirectorRemoved(director);
    }

    /**
     * @notice Get all current directors
     * @return Array of director addresses
     */
    function getDirectors() external view returns (address[] memory) {
        return _directors;
    }

    /**
     * @notice Get the number of directors
     * @return Number of directors on the board
     */
    function directorCount() external view returns (uint256) {
        return _directors.length;
    }

    /**
     * @notice Transfer governance role to a new address (e.g., when upgrading governance)
     * @param newGovernance New governance address
     */
    function transferGovernance(address newGovernance) external onlyRole(GOVERNANCE_ROLE) {
        if (newGovernance == address(0)) revert ZeroAddress();
        _grantRole(GOVERNANCE_ROLE, newGovernance);
        _grantRole(DEFAULT_ADMIN_ROLE, newGovernance);
        _revokeRole(GOVERNANCE_ROLE, msg.sender);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
