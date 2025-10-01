// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

/**
 * @title IBufferPool Interface
 * @notice Interface for the BufferPool contract, which manages the Vault's buffer reserves
 */
interface IBuffer {
    /**
     * @notice Error thrown when total quote tokens exceed maximum capacity
     * @dev Maximum capacity is 100 trillion quote tokens
     */
    error BufferPoolMaxedOut();

    /**
     * @notice Error thrown when reentrancy is detected
     */
    error ReentrancyGuardActive();

    /**
     * @notice Error thrown when non-Vault address attempts to call restricted functions
     */
    error Unauthorized();

    /**
     * @notice Returns the quote token address
     * @return address The address of the quote token
     */
    function quo() external view returns (address);

    /**
     * @notice Returns the quote token decimals
     * @return uint8 The number of decimals for the quote token
     */
    function assetDecimals() external view returns (uint8);

    /**
     * @notice Returns the Vault contract address
     * @return address The address of the Vault contract
     */
    function vault() external view returns (address);

    /**
     * @notice Returns the total quote tokens in the buffer
     * @return uint256 The total amount of quote tokens
     */
    function total() external view returns (uint256);

    /**
     * @notice Returns the total shares (mana) in the buffer
     * @return uint256 The total amount of shares
     */
    function Mana() external view returns (uint256);

    /**
     * @notice Returns the reentrancy guard status
     * @return uint8 The current state of the reentrancy guard
     */
    function bolt() external view returns (uint8);

    /**
     * @notice Adds quote tokens to the buffer
     * @param wad The amount of quote tokens to add in WAD
     * @param bucket The bucket index (unused in buffer)
     * @param expiry The expiry timestamp (unused in buffer)
     * @return uint256 The amount of shares (mana) minted
     * @return uint256 The amount of quote tokens added
     */
    function addQuoteToken(uint256 wad, uint256 bucket, uint256 expiry) external returns (uint256, uint256);

    /**
     * @notice Removes quote tokens from the buffer
     * @param wad The amount of quote tokens to remove in WAD
     * @param bucket The bucket index (unused in buffer)
     * @return uint256 The amount of quote tokens removed
     * @return uint256 The amount of shares (mana) burned
     */
    function removeQuoteToken(uint256 wad, uint256 bucket) external returns (uint256, uint256);

    /**
     * @notice Updates interest (no-op in buffer)
     */
    function updateInterest() external;

    /**
     * @notice Converts LP tokens to quote token value
     * @param lps The amount of LP tokens
     * @return uint256 The equivalent value in quote tokens
     */
    function lpToValue(uint256 lps) external view returns (uint256);
}
