// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {console} from "forge-std/console.sol";

contract PoolMockBurnableQT {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD       = 1e18;
    uint256 internal constant RAY       = 1e27;

    address public immutable quoteTokenAddress;
    address public immutable collateralAddress;
    uint256 public total; // Assets
    uint256 public fee;    
    uint8   public immutable assetDecimals;
    uint256 public lastInterestUpdate;
    
    // Per-bucket LP tracking
    mapping(uint256 => uint256) public bucketLps; // bucket => LP amount
    mapping(uint256 => uint256) public bucketAssets; // bucket => asset amount

    constructor(address token) {
        quoteTokenAddress = token;
        collateralAddress = token;
        assetDecimals = 18;
        lastInterestUpdate = block.timestamp;
    }

    function updateInterest() public {
        uint256 increase = ((block.timestamp - lastInterestUpdate) * 10000 / 8 hours);
        uint256 interest = fee * increase / 10000;
        total += interest;
        if (fee <= interest) {
            fee = 0;
        } else {
            fee -= interest;
        }
        lastInterestUpdate = block.timestamp;
    }

     function addQuoteToken(
        uint256 _wad,
        uint256 _bucket,
        uint256 /* _expiry */
    ) external returns (uint256, uint256) {
        updateInterest();
        
        // Calculate LP tokens to award
        uint256 _sip = (bucketLps[_bucket] > 0) ? (_wad * bucketLps[_bucket]) / bucketAssets[_bucket] : _wad;
        
        // Apply deposit fee
        uint256 _fee = (_wad * 10) / 10000;
        uint256 assetsAfterFee = _wad - _fee;
        
        // Update tracking
        bucketLps[_bucket] += _sip;
        bucketAssets[_bucket] += assetsAfterFee;
        total += assetsAfterFee;
        fee += _fee;

        uint256 _transferAmt = (_wad * (10**assetDecimals)) / WAD;
        IERC20(quoteTokenAddress).safeTransferFrom(msg.sender, address(this), _transferAmt);
        return (_sip, assetsAfterFee);
    }

    function removeQuoteToken(
        uint256 _wad,
        uint256 _bucket
    ) external returns (uint256, uint256) {
        updateInterest();
        
        // Handle edge case where total is 0 or bucket has no assets
        if (total == 0 || bucketAssets[_bucket] == 0) {
            return (0, 0);
        }
        
        // Calculate how much we can actually remove (limited by what's in the bucket)
        uint256 assetsToRemove = _wad;
        if (assetsToRemove > bucketAssets[_bucket]) {
            assetsToRemove = bucketAssets[_bucket];
        }
        
        // Calculate LPs to burn proportionally: (LPs * assetsToRemove) / totalAssetsInBucket
        uint256 _burnLps = (bucketLps[_bucket] * assetsToRemove) / bucketAssets[_bucket];
        
        // Update bucket tracking
        bucketLps[_bucket] -= _burnLps;
        bucketAssets[_bucket] -= assetsToRemove;
        
        // Update global tracking
        if (total >= assetsToRemove) {
            total -= assetsToRemove;
        } else {
            total = 0;
        }
        
        uint256 _transferAmt = (assetsToRemove * (10**assetDecimals)) / WAD;
        IERC20(quoteTokenAddress).safeTransfer(msg.sender, _transferAmt);
        return (assetsToRemove, _burnLps);
    }

    function moveQuoteToken(
        uint256 _wad,
        uint256 _fromBucket,
        uint256 _toBucket,
        uint256 /* _expiry */
    ) external returns (uint256, uint256, uint256) {
        updateInterest();
        
        // Remove from source bucket
        if (bucketAssets[_fromBucket] == 0) {
            return (0, 0, 0);
        }
        
        uint256 assetsToMove = _wad;
        if (assetsToMove > bucketAssets[_fromBucket]) {
            assetsToMove = bucketAssets[_fromBucket];
        }
        
        uint256 fromLpsToRemove = (bucketLps[_fromBucket] * assetsToMove) / bucketAssets[_fromBucket];
        
        // Update from bucket
        bucketLps[_fromBucket] -= fromLpsToRemove;
        bucketAssets[_fromBucket] -= assetsToMove;
        
        // For moves from lower to higher bucket indices, apply fee (like deposit)
        uint256 actualAssetsAfterFee = assetsToMove;
        if (_fromBucket < _toBucket) {
            uint256 moveFee = (assetsToMove * 10) / 10000; // 0.1% fee  
            actualAssetsAfterFee = assetsToMove - moveFee;
            fee += moveFee;
        }
        
        // Add to destination bucket 
        uint256 toLps = (bucketLps[_toBucket] > 0) ? (actualAssetsAfterFee * RAY) / ((total * RAY) / bucketLps[_toBucket]) : actualAssetsAfterFee;
        bucketLps[_toBucket] += toLps;
        bucketAssets[_toBucket] += actualAssetsAfterFee;
        
        return (fromLpsToRemove, toLps, actualAssetsAfterFee);
    }

    function removeCollateral(uint256 _amount, uint256 /* _index */) external pure returns (uint256, uint256) {
        // This should be mocked so it works in the live fork as well
        return (_amount, _amount);
    }

}
