// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultAuth} from "./interfaces/IVaultAuth.sol";

contract VaultAuth is IVaultAuth {
    address public admin;
    address public swapper;
    mapping(address => bool) public keepers;
    bool public paused;
    uint256 public depositCap; // 0 means no cap
    uint256 public bufferRatio; // percentage in basis points (e.g., 1000 = 10%)
    uint256 public toll; // deposit fee in basis points (e.g., 100 = 1%)
    uint256 public tax; // withdraw fee in basis points (e.g., 100 = 1%)
    uint256 public minBucketIndex; // minimum bucket index for keeper moves (0 = no restriction)
    
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized();
        _;
    }
    
    constructor() {
        admin = msg.sender;
    }
    
    function isAdmin(address account) external view returns (bool) {
        return account == admin;
    }
    
    function isSwapper(address account) external view returns (bool) {
        return account == swapper;
    }
    
    function isKeeper(address account) external view returns (bool) {
        return keepers[account];
    }
    
    function isAdminOrKeeper(address account) external view returns (bool) {
        return account == admin || keepers[account];
    }
    
    function isAdminOrSwapper(address account) external view returns (bool) {
        return account == admin || account == swapper;
    }
    
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit SetAdmin(_admin);
    }
    
    function setSwapper(address _swapper) external onlyAdmin {
        swapper = _swapper;
        emit SetSwapper(_swapper);
    }
    
    function setKeeper(address _keeper, bool _isKeeper) external onlyAdmin {
        keepers[_keeper] = _isKeeper;
        emit KeeperSet(_keeper, _isKeeper);
    }
    
    function pause() external onlyAdmin {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused();
    }
    
    function setDepositCap(uint256 _depositCap) external onlyAdmin {
        depositCap = _depositCap;
        emit DepositCapSet(_depositCap);
    }

    function setBufferRatio(uint256 _bufferRatio) external onlyAdmin {
        if (_bufferRatio > 10000) revert BufferRatioTooHigh();
        bufferRatio = _bufferRatio;
        emit BufferRatioSet(_bufferRatio);
    }

    function setToll(uint256 _toll) external onlyAdmin {
        if (_toll > 1000) revert FeeTooHigh();
        toll = _toll;
        emit TollSet(_toll);
    }

    function setTax(uint256 _tax) external onlyAdmin {
        if (_tax > 1000) revert FeeTooHigh();
        tax = _tax;
        emit TaxSet(_tax);
    }

    function setMinBucketIndex(uint256 _minBucketIndex) external onlyAdmin {
        minBucketIndex = _minBucketIndex;
        emit MinBucketIndexSet(_minBucketIndex);
    }
    
    function retrieveFees(address token, uint256 amount) external onlyAdmin {
        IERC20(token).transfer(admin, amount);
    }
}
