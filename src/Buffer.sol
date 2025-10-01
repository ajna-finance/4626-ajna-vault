// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';
import { IBuffer } from "./interfaces/IBuffer.sol";

/**
 * @title BufferPool
 * @notice Implementation of the BufferPool interface
 * @dev See {IBufferPool} for detailed function documentation
 */
contract Buffer is IBuffer {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD       = 1e18;
    uint256 internal constant RAY       = 1e27;
    uint256 internal constant TRILLION  = 1_000_000_000_000 * WAD;

    address public immutable quo;
    uint8   public immutable assetDecimals;
    address public immutable vault;

    uint256 public total;               // [WAD] total QT accounting (32 bytes)
    uint256 public Mana;                // [WAD] total Mana accounting (32 bytes)
    uint8   public bolt;                // [mutex] Reentrancy guard (1 byte)

    constructor(
        address _quo,
        uint8 _assetDecimals
    ) {
        quo           = _quo;
        assetDecimals = _assetDecimals;
        vault         = msg.sender;

        IERC20(quo).approve(msg.sender, type(uint256).max);
    }

    /**
     * @notice Prevents reentrancy attacks by using a mutex lock
     * @dev Sets the bolt flag to 1 during execution and resets it to 0 after
     * @dev Reverts with ReentrancyGuardActive if called while already locked
     */
    modifier lock {
        if (bolt != 0) revert ReentrancyGuardActive();
        bolt = 1;
        _;
        bolt = 0;
    }

    /**
     * @notice Restricts function access to only the Vault contract
     * @dev Ensures only the Vault contract (set during construction) can call the function
     * @dev Reverts with Unauthorized if called by any other address
     */
    modifier onlyVault() {
        if (msg.sender != vault) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @inheritdoc IBuffer
     */
    function addQuoteToken(
        uint256 _wad,
        uint256 /* _bucket */,
        uint256 /* _expiry */
    ) external onlyVault lock returns (uint256, uint256) {
        // calculate Mana based on total supply
        uint256 _sip  = (Mana > 0) ? (_wad * RAY) / ((total  * RAY) / Mana) : _wad;
        Mana         += _sip;
        total        += _wad;

        if (total > 100 * TRILLION) {
            revert BufferPoolMaxedOut();
        }

        uint256 _transferAmt = (_wad * (10**assetDecimals)) / WAD;
        IERC20(quo).safeTransferFrom(msg.sender, address(this), _transferAmt);
        return (_sip, _wad);
    }

    /**
     * @inheritdoc IBuffer
     */
    function removeQuoteToken(
        uint256 _wad,
        uint256 _bucket
    ) external onlyVault lock returns (uint256, uint256) {
        // clear unused variables
        _bucket;

        uint256 _sip  = Math.mulDiv(_wad * RAY, Mana, total * RAY, Math.Rounding.Up);
        Mana         -= _sip;
        total        -= _wad;

        uint256 _transferAmt = (_wad * (10**assetDecimals)) / WAD;
        IERC20(quo).safeTransfer(msg.sender, _transferAmt);
        return (_wad, _sip);
    }

    /**
     * @inheritdoc IBuffer
     */
    function updateInterest() external {
        // do nothing
    }
  
    //
    // Public view functions
    //

    /**
     * @inheritdoc IBuffer
     */
    function lpToValue(uint256 _lps) public view returns (uint256) {
        if (_lps == 0 || Mana == 0) return 0;
        return (_lps * total) / Mana;
    }
}
