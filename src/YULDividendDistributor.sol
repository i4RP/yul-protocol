// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YULShareToken} from "./YULShareToken.sol";

/**
 * @title YULDividendDistributor
 * @notice Distributes profits (ETH and ERC20 tokens) to YUL shareholders
 *         proportionally based on their share ownership at the time of distribution.
 * @dev Uses a pull-based (claim) mechanism for gas efficiency.
 *      Each distribution round creates a snapshot of total supply and records
 *      the amount to distribute. Shareholders can then claim their proportional share.
 */
contract YULDividendDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The YUL share token contract
    YULShareToken public immutable shareToken;

    /// @notice The governance/corporation address that can create distributions
    address public distributor;

    /// @notice Counter for distribution rounds
    uint256 public currentRoundId;

    /// @notice Represents a single dividend distribution round
    struct DividendRound {
        address token; // address(0) for ETH distributions
        uint256 totalAmount; // Total amount to distribute
        uint256 totalShares; // Total share supply at time of distribution
        uint256 blockNumber; // Block number for share balance snapshot
        uint256 claimedAmount; // Total amount already claimed
        bool active; // Whether the round is active
    }

    /// @notice Mapping from round ID to distribution details
    mapping(uint256 => DividendRound) public rounds;

    /// @notice Mapping from round ID to shareholder address to claimed status
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // Events
    event DividendDistributed(
        uint256 indexed roundId, address indexed token, uint256 totalAmount, uint256 totalShares
    );
    event DividendClaimed(uint256 indexed roundId, address indexed shareholder, uint256 amount);
    event DistributorUpdated(address indexed previousDistributor, address indexed newDistributor);

    // Errors
    error OnlyDistributor();
    error ZeroAmount();
    error ZeroShares();
    error RoundNotActive();
    error AlreadyClaimed();
    error NoSharesAtSnapshot();
    error TransferFailed();
    error ZeroAddress();

    modifier onlyDistributor() {
        if (msg.sender != distributor) revert OnlyDistributor();
        _;
    }

    /**
     * @param _shareToken Address of the YUL share token
     * @param _distributor Address authorized to create distributions (corporation/governance)
     */
    constructor(address _shareToken, address _distributor) {
        if (_shareToken == address(0)) revert ZeroAddress();
        if (_distributor == address(0)) revert ZeroAddress();
        shareToken = YULShareToken(_shareToken);
        distributor = _distributor;
    }

    /**
     * @notice Create a new ETH dividend distribution round
     * @dev The ETH to distribute must be sent with this call
     */
    function distributeEth() external payable onlyDistributor {
        if (msg.value == 0) revert ZeroAmount();

        uint256 totalShares = shareToken.totalSupply();
        if (totalShares == 0) revert ZeroShares();

        uint256 roundId = ++currentRoundId;
        rounds[roundId] = DividendRound({
            token: address(0),
            totalAmount: msg.value,
            totalShares: totalShares,
            blockNumber: block.number,
            claimedAmount: 0,
            active: true
        });

        emit DividendDistributed(roundId, address(0), msg.value, totalShares);
    }

    /**
     * @notice Create a new ERC20 token dividend distribution round
     * @param token The ERC20 token to distribute
     * @param amount The amount of tokens to distribute
     */
    function distributeToken(address token, uint256 amount) external onlyDistributor {
        if (amount == 0) revert ZeroAmount();
        if (token == address(0)) revert ZeroAddress();

        uint256 totalShares = shareToken.totalSupply();
        if (totalShares == 0) revert ZeroShares();

        // Transfer tokens from distributor to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 roundId = ++currentRoundId;
        rounds[roundId] = DividendRound({
            token: token,
            totalAmount: amount,
            totalShares: totalShares,
            blockNumber: block.number,
            claimedAmount: 0,
            active: true
        });

        emit DividendDistributed(roundId, token, amount, totalShares);
    }

    /**
     * @notice Claim dividend for a specific round
     * @param roundId The distribution round ID
     */
    function claim(uint256 roundId) external nonReentrant {
        DividendRound storage round = rounds[roundId];
        if (!round.active) revert RoundNotActive();
        if (hasClaimed[roundId][msg.sender]) revert AlreadyClaimed();

        uint256 shareholderBalance = shareToken.balanceOf(msg.sender);
        if (shareholderBalance == 0) revert NoSharesAtSnapshot();

        uint256 dividend = (round.totalAmount * shareholderBalance) / round.totalShares;
        if (dividend == 0) revert ZeroAmount();

        hasClaimed[roundId][msg.sender] = true;
        round.claimedAmount += dividend;

        if (round.token == address(0)) {
            // ETH distribution
            (bool success,) = payable(msg.sender).call{value: dividend}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 distribution
            IERC20(round.token).safeTransfer(msg.sender, dividend);
        }

        emit DividendClaimed(roundId, msg.sender, dividend);
    }

    /**
     * @notice Claim dividends for multiple rounds at once
     * @param roundIds Array of round IDs to claim
     */
    function claimMultiple(uint256[] calldata roundIds) external nonReentrant {
        for (uint256 i = 0; i < roundIds.length; i++) {
            uint256 roundId = roundIds[i];
            DividendRound storage round = rounds[roundId];
            if (!round.active) continue;
            if (hasClaimed[roundId][msg.sender]) continue;

            uint256 shareholderBalance = shareToken.balanceOf(msg.sender);
            if (shareholderBalance == 0) continue;

            uint256 dividend = (round.totalAmount * shareholderBalance) / round.totalShares;
            if (dividend == 0) continue;

            hasClaimed[roundId][msg.sender] = true;
            round.claimedAmount += dividend;

            if (round.token == address(0)) {
                (bool success,) = payable(msg.sender).call{value: dividend}("");
                if (!success) revert TransferFailed();
            } else {
                IERC20(round.token).safeTransfer(msg.sender, dividend);
            }

            emit DividendClaimed(roundId, msg.sender, dividend);
        }
    }

    /**
     * @notice Calculate the unclaimed dividend amount for a shareholder in a specific round
     * @param roundId The distribution round ID
     * @param shareholder Address of the shareholder
     * @return The unclaimed dividend amount
     */
    function unclaimedDividend(uint256 roundId, address shareholder) external view returns (uint256) {
        DividendRound storage round = rounds[roundId];
        if (!round.active || hasClaimed[roundId][shareholder]) return 0;

        uint256 shareholderBalance = shareToken.balanceOf(shareholder);
        if (shareholderBalance == 0) return 0;

        return (round.totalAmount * shareholderBalance) / round.totalShares;
    }

    /**
     * @notice Update the distributor address
     * @param _newDistributor New distributor address
     */
    function setDistributor(address _newDistributor) external onlyDistributor {
        if (_newDistributor == address(0)) revert ZeroAddress();
        emit DistributorUpdated(distributor, _newDistributor);
        distributor = _newDistributor;
    }
}
