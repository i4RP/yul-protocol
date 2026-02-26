// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {YULCorporation} from "../src/YULCorporation.sol";
import {YULShareToken} from "../src/YULShareToken.sol";
import {YULGovernance} from "../src/YULGovernance.sol";
import {YULTreasury} from "../src/YULTreasury.sol";
import {YULDividendDistributor} from "../src/YULDividendDistributor.sol";
import {YULOfficerManager} from "../src/YULOfficerManager.sol";

/**
 * @title DeployYUL
 * @notice Deployment script for the full YUL Corporation protocol.
 * @dev Deploy order:
 *      1. YULCorporation (main controller)
 *      2. YULShareToken (minter = corporation)
 *      3. YULOfficerManager (governance = corporation initially, transferred later)
 *      4. YULTreasury (governance = corporation initially)
 *      5. YULDividendDistributor (distributor = corporation)
 *      6. YULGovernance (shareToken, corporation)
 *      7. Initialize corporation with all modules
 */
contract DeployYUL is Script {
    // Default governance parameters
    uint256 constant PROPOSAL_THRESHOLD_BPS = 100; // 1% of total supply needed to propose
    uint256 constant QUORUM_BPS = 2000; // 20% quorum
    uint256 constant VOTING_PERIOD = 50400; // ~1 week (assuming 12s blocks)
    uint256 constant VOTING_DELAY = 7200; // ~1 day delay before voting starts

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying YUL Corporation Protocol...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the corporation
        YULCorporation corporation = new YULCorporation("YUL Corporation", "Ethereum Network");
        console.log("YULCorporation deployed at:", address(corporation));

        // 2. Deploy share token (corporation is the minter)
        YULShareToken shareToken = new YULShareToken(address(corporation));
        console.log("YULShareToken deployed at:", address(shareToken));

        // 3. Deploy officer manager (corporation as initial governance)
        YULOfficerManager officerManager = new YULOfficerManager(address(corporation));
        console.log("YULOfficerManager deployed at:", address(officerManager));

        // 4. Deploy treasury
        YULTreasury treasury = new YULTreasury(address(corporation), address(corporation));
        console.log("YULTreasury deployed at:", address(treasury));

        // 5. Deploy dividend distributor
        YULDividendDistributor dividendDistributor =
            new YULDividendDistributor(address(shareToken), address(corporation));
        console.log("YULDividendDistributor deployed at:", address(dividendDistributor));

        // 6. Deploy governance
        YULGovernance governance = new YULGovernance(
            address(shareToken),
            address(corporation),
            PROPOSAL_THRESHOLD_BPS,
            QUORUM_BPS,
            VOTING_PERIOD,
            VOTING_DELAY
        );
        console.log("YULGovernance deployed at:", address(governance));

        // 7. Initialize corporation with all modules
        corporation.initialize(
            address(shareToken),
            address(governance),
            payable(address(treasury)),
            address(dividendDistributor),
            address(officerManager)
        );
        console.log("Corporation initialized with all modules!");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== YUL Corporation Protocol Deployed ===");
        console.log("Corporation:          ", address(corporation));
        console.log("ShareToken (YUL):     ", address(shareToken));
        console.log("Governance:           ", address(governance));
        console.log("Treasury:             ", address(treasury));
        console.log("DividendDistributor:  ", address(dividendDistributor));
        console.log("OfficerManager:       ", address(officerManager));
    }
}
