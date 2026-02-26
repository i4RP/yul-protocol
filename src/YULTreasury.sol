// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YULTreasury
 * @notice Manages the corporate treasury for the YUL Corporation.
 *         Holds ETH and ERC20 tokens, with spending controlled by governance.
 * @dev Supports governance-approved spending and emergency withdrawals by CFO.
 */
contract YULTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The governance contract that controls spending
    address public governance;

    /// @notice The corporation contract
    address public corporation;

    /// @notice Total ETH received over time
    uint256 public totalEthReceived;

    /// @notice Total ETH spent over time
    uint256 public totalEthSpent;

    /// @notice Mapping of ERC20 token address to total received
    mapping(address => uint256) public totalTokenReceived;

    /// @notice Mapping of ERC20 token address to total spent
    mapping(address => uint256) public totalTokenSpent;

    // Events
    event EthReceived(address indexed from, uint256 amount);
    event EthTransferred(address indexed to, uint256 amount, string reason);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount, string reason);
    event GovernanceUpdated(address indexed previousGovernance, address indexed newGovernance);
    event CorporationUpdated(address indexed previousCorporation, address indexed newCorporation);

    // Errors
    error OnlyGovernance();
    error OnlyCorporationOrGovernance();
    error ZeroAddress();
    error InsufficientBalance();
    error TransferFailed();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    modifier onlyCorporationOrGovernance() {
        if (msg.sender != corporation && msg.sender != governance) revert OnlyCorporationOrGovernance();
        _;
    }

    /**
     * @param _governance Address of the governance contract (or initial admin)
     * @param _corporation Address of the corporation contract
     */
    constructor(address _governance, address _corporation) {
        if (_governance == address(0)) revert ZeroAddress();
        if (_corporation == address(0)) revert ZeroAddress();
        governance = _governance;
        corporation = _corporation;
    }

    /**
     * @notice Receive ETH into the treasury
     */
    receive() external payable {
        totalEthReceived += msg.value;
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @notice Transfer ETH from the treasury. Only governance or corporation can call.
     * @param to Recipient address
     * @param amount Amount of ETH to transfer
     * @param reason Description of the transfer
     */
    function transferEth(address payable to, uint256 amount, string calldata reason)
        external
        onlyCorporationOrGovernance
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (address(this).balance < amount) revert InsufficientBalance();

        totalEthSpent += amount;
        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit EthTransferred(to, amount, reason);
    }

    /**
     * @notice Transfer ERC20 tokens from the treasury. Only governance or corporation can call.
     * @param token Token contract address
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @param reason Description of the transfer
     */
    function transferToken(address token, address to, uint256 amount, string calldata reason)
        external
        onlyCorporationOrGovernance
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();

        totalTokenSpent[token] += amount;
        IERC20(token).safeTransfer(to, amount);

        emit TokenTransferred(token, to, amount, reason);
    }

    /**
     * @notice Update the governance address. Only current governance can call.
     * @param _newGovernance New governance address
     */
    function setGovernance(address _newGovernance) external onlyGovernance {
        if (_newGovernance == address(0)) revert ZeroAddress();
        emit GovernanceUpdated(governance, _newGovernance);
        governance = _newGovernance;
    }

    /**
     * @notice Update the corporation address. Only governance can call.
     * @param _newCorporation New corporation address
     */
    function setCorporation(address _newCorporation) external onlyGovernance {
        if (_newCorporation == address(0)) revert ZeroAddress();
        emit CorporationUpdated(corporation, _newCorporation);
        corporation = _newCorporation;
    }

    /**
     * @notice Get the current ETH balance of the treasury
     * @return ETH balance in wei
     */
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get the current ERC20 token balance of the treasury
     * @param token Token contract address
     * @return Token balance
     */
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
