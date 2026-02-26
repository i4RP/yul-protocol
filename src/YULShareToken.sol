// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title YULShareToken
 * @notice ERC20 token representing shares in the YUL for-profit corporation.
 *         Supports voting delegation (ERC20Votes) and gasless approvals (ERC20Permit).
 * @dev Only the authorized minter (YULCorporation) can mint/burn shares.
 */
contract YULShareToken is ERC20, ERC20Permit, ERC20Votes {
    /// @notice Address authorized to mint and burn shares (the YULCorporation contract)
    address public minter;

    /// @notice Emitted when the minter address is updated
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    error OnlyMinter();
    error ZeroAddress();

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    /**
     * @param _minter Address authorized to mint/burn shares
     */
    constructor(address _minter) ERC20("YUL Corporation Share", "YUL") ERC20Permit("YUL Corporation Share") {
        if (_minter == address(0)) revert ZeroAddress();
        minter = _minter;
    }

    /**
     * @notice Update the minter address. Can only be called by the current minter.
     * @param _newMinter New minter address
     */
    function setMinter(address _newMinter) external onlyMinter {
        if (_newMinter == address(0)) revert ZeroAddress();
        emit MinterUpdated(minter, _newMinter);
        minter = _newMinter;
    }

    /**
     * @notice Mint new shares to a shareholder
     * @param to Recipient address
     * @param amount Number of shares to mint
     */
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /**
     * @notice Burn shares from a shareholder
     * @param from Address to burn from
     * @param amount Number of shares to burn
     */
    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    // ========== Required Overrides ==========

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
