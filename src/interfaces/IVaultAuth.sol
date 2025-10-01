// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

interface IVaultAuth {
    // ERRORS
    error NotAuthorized();
    error BufferRatioTooHigh();
    error FeeTooHigh();
    
    // EVENTS
    event SetAdmin(address indexed newAdmin);
    event SetSwapper(address indexed newSwapper);
    event KeeperSet(address indexed keeper, bool isKeeper);
    event Paused();
    event Unpaused();
    event DepositCapSet(uint256 newDepositCap);
    event BufferRatioSet(uint256 newBufferRatio);
    event TollSet(uint256 newToll);
    event TaxSet(uint256 newTax);
    event MinBucketIndexSet(uint256 newMinBucketIndex);
    
    function admin() external view returns (address);
    function swapper() external view returns (address);
    function keepers(address) external view returns (bool);
    function paused() external view returns (bool);
    function depositCap() external view returns (uint256);
    function bufferRatio() external view returns (uint256);
    function toll() external view returns (uint256);
    function tax() external view returns (uint256);
    function minBucketIndex() external view returns (uint256);
    
    function isAdmin(address account) external view returns (bool);
    function isSwapper(address account) external view returns (bool);
    function isKeeper(address account) external view returns (bool);
    function isAdminOrKeeper(address account) external view returns (bool);
    function isAdminOrSwapper(address account) external view returns (bool);
    
    function setAdmin(address _admin) external;
    function setSwapper(address _swapper) external;
    function setKeeper(address _keeper, bool _isKeeper) external;
    function setDepositCap(uint256 _depositCap) external;
    function setBufferRatio(uint256 _bufferRatio) external;
    function setToll(uint256 _toll) external;
    function setTax(uint256 _tax) external;
    function setMinBucketIndex(uint256 _minBucketIndex) external;
    function pause() external;
    function unpause() external;
}