// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

interface IVault {
    // ERRORS
    error InvalidQuoteToken();
    error ReentrancyLockActive();
    error InvalidDeposit();
    error InvalidAssetDecimals(uint8 decimals);
    error DustyBucket(address pool, uint256 bucket); // (Pool or Buffer, bucketIndex)
    error ZeroAddress();
    error NotAuthorized();
    error VaultUnpaused();
    error VaultPaused();
    error RemovedCollateralValueNotZero();
    error DepositCapExceeded();
    error BufferRatioExceeded();
    error BucketLPDangerous(address pool, uint256 bucket, uint256 bucketLP);
    error BucketIndexTooLow(address pool, uint256 bucket, uint256 minBucketIndex);

    // EVENTS
    event MoveFromBuffer(address indexed caller, address indexed pool, uint256 bucket, uint256 amount);
    event MoveToBuffer(address indexed caller, address indexed pool, uint256 bucket, uint256 amount);
    event Move(address indexed caller, address indexed pool, uint256 fromBucket, uint256 toBucket, uint256 amount);
    event SetAdmin(address indexed newAdmin);
    event RecoverCollateral(address indexed caller, uint256 bucket, uint256 amount, uint256 lps, uint256 value);
    event ReturnQuoteToken(address indexed caller, uint256 bucket, uint256 amount, uint256 lps);
    event SetSwapper(address indexed newSwapper);
    event KeeperSet(address indexed keeper, bool isKeeper);
    event Paused();
    event Unpaused();
    event Drain(address caller, uint256 bucket, uint256 lps, uint256 newLps);
}
