// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {IVault} from "./interfaces/IVault.sol";
import {ERC4626} from "./ERC4626.sol";
import {Vault} from "./Vault.sol";
import {IVaultAuth} from "./interfaces/IVaultAuth.sol";
import {IBuffer} from "./interfaces/IBuffer.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {Buffer} from "./Buffer.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";
import {Maths} from "lib/ajna-core/src/libraries/internal/Maths.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library AjnaVaultLibrary { 
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;

    function move(
        PoolInfoUtils _info,
        IPool _pool,
        uint256 _fromIndex,
        uint256 _toIndex,
        uint256 _wad,
        IVaultAuth _auth
    ) external returns (uint256 _fromLps, uint256 _toLps) {
        if (!_auth.isAdminOrKeeper(msg.sender)) revert IVault.NotAuthorized();
        _pool.updateInterest();

        _validDestination(_info, _pool, _toIndex, _auth);

        uint256 _assets;
        (_fromLps, _toLps, _assets) = _pool.moveQuoteToken(
            _wad,
            _fromIndex,
            _toIndex,
            block.timestamp
        );
    }

    function moveFromBuffer(
        PoolInfoUtils _info,
        IVaultAuth _auth,
        Buffer _buffer,
        IPool _pool,
        uint256 _toIndex,
        uint256 _wad
    ) external returns (uint256 _fromLps, uint256 _toLps) {
        if (!_auth.isKeeper(msg.sender)) revert IVault.NotAuthorized();
        _pool.updateInterest();

        Vault _vault = Vault(address(this));
        _checkBufferRatio(
            _auth,
            _buffer,
            false,
            _wad,
            _convertAssetToWad(_vault.totalAssets(), _vault.assetDecimals())
        );
        _validDestination(_info, _pool, _toIndex, _auth);

        uint256 _assets;
        (_assets, _fromLps) = _buffer.removeQuoteToken(_wad, 0);
        
        (_toLps, _assets) = _pool.addQuoteToken(_assets, _toIndex, block.timestamp);
    }

    function moveToBuffer(
        IVaultAuth _auth,
        IPool _pool,
        Buffer _buffer,
        uint256 _fromIndex,
        uint256 _wad
    ) external returns (uint256 _fromLps, uint256 _toLps) {
        if (!_auth.isAdminOrKeeper(msg.sender)) revert IVault.NotAuthorized();
        _pool.updateInterest();

        Vault _vault = Vault(address(this));
        _checkBufferRatio(
            _auth,
            _buffer,
            true,
            _wad, 
            _convertAssetToWad(_vault.totalAssets(), _vault.assetDecimals())
        );

        uint256 _assets;
        (_assets, _fromLps) = _pool.removeQuoteToken(_wad, _fromIndex);

        (_toLps, _assets) = _buffer.addQuoteToken(_assets, 0, block.timestamp);
    }

    function recoverCollateral(
        PoolInfoUtils _info,
        IPool _pool,
        uint256 _fromIndex,
        uint256 _amt
    ) external returns (uint256 _colLps, address _gem, uint256 _gems, uint256 _value) {
        _pool.updateInterest();

        (
            uint256 _price,
            /* _quoteToken */,
            /* _collateral */,
            /* _bucketLP */,
            /* scale */,
            /* exchangeRate */
        ) = _info.bucketInfo(address(_pool), _fromIndex );
        _gem = _pool.collateralAddress();

        (_gems, _colLps) = _pool.removeCollateral(_amt, _fromIndex);
        _value = (_gems * _price) / WAD;
    }

    function returnQuoteToken(
        PoolInfoUtils _info,
        IPool _pool,
        IVaultAuth _auth,
        uint256 _toIndex,
        uint256 _amt
    ) external returns (uint256 _toLps) {
        _validDestination(_info, _pool, _toIndex, _auth);

        (_toLps, /* _assets */) = _pool.addQuoteToken(_amt, _toIndex, block.timestamp);
    }

    // External View Functions

    function lpToValue(
        PoolInfoUtils _info,
        IPool _pool,
        uint256 _bucket,
        uint256 _lps
    ) external view returns (uint256) {
        (
            uint256 _price,
            uint256 _quoteToken,
            uint256 _collateral,
            uint256 _bucketLP,
            /* scale */,
            /* exchangeRate */
        ) = _info.bucketInfo(address(_pool), _bucket);

        if (_quoteToken == 0 && _collateral == 0) return 0;

        if (_bucketLP == 0) return 0;

        return Math.mulDiv(
            (_quoteToken * WAD) + (_collateral * _price),
            _lps,
            _bucketLP * WAD,
            Math.Rounding.Down
        );
    }

    /**
     * @notice Helper to transfer tokens between addresses with decimal adjustment
     * @param _asset The token address to transfer
     * @param _from The source address
     * @param _to The destination address
     * @param _amt The amount to transfer in asset decimals precision
     */
    function transferTokenFrom(
        address _asset,
        address _from,
        address _to,
        uint256 _amt
    ) external {
        _transferTokenFrom(_asset, _from, _to, _amt);
    }

    /**
     * @notice Internal implementation of token transfer with decimal adjustment
     * @param _asset The token address to transfer
     * @param _from The source address
     * @param _to The destination address
     * @param _amt The amount to transfer in asset decimals precision
     */
    function _transferTokenFrom(
        address _asset,
        address _from,
        address _to,
        uint256 _amt
    ) internal {
        if (_from == address(this)) {
            IERC20(_asset).safeTransfer(_to, _amt);
        } else {
            IERC20(_asset).safeTransferFrom(_from, _to, _amt);
        }
    }

    /**
     * @notice Convert assets from underlying asset decimals to WAD (18 decimals) for internal calculations
     * @param _assetAmount Amount in underlying asset decimals
     * @param _assetDecimals Decimal places of the underlying asset
     * @return Amount in WAD precision (18 decimals)
     */
    function convertAssetToWad(uint256 _assetAmount, uint8 _assetDecimals) external pure returns (uint256) {
        return _convertAssetToWad(_assetAmount, _assetDecimals);
    }

    /**
     * @notice Convert assets from WAD (18 decimals) to underlying asset decimals for external interface
     * @param _wadAmount Amount in WAD precision (18 decimals)
     * @param _assetDecimals Decimal places of the underlying asset
     * @return Amount in underlying asset decimals
     */
    function convertWadToAsset(uint256 _wadAmount, uint8 _assetDecimals) external pure returns (uint256) {
        return _convertWadToAsset(_wadAmount, _assetDecimals);
    }

    /**
     * @notice Internal function to convert assets from underlying asset decimals to WAD (18 decimals)
     * @param _assetAmount Amount in underlying asset decimals
     * @param _assetDecimals Decimal places of the underlying asset
     * @return Amount in WAD precision (18 decimals)
     */
    function _convertAssetToWad(uint256 _assetAmount, uint8 _assetDecimals) internal pure returns (uint256) {
        if (_assetDecimals == 18) {
            return _assetAmount;
        } else if (_assetDecimals < 18) {
            return _assetAmount * (10 ** (18 - _assetDecimals));
        } else {
            return _assetAmount / (10 ** (_assetDecimals - 18));
        }
    }

    /**
     * @notice Internal function to convert assets from WAD (18 decimals) to underlying asset decimals
     * @param _wadAmount Amount in WAD precision (18 decimals)
     * @param _assetDecimals Decimal places of the underlying asset
     * @return Amount in underlying asset decimals
     */
    function _convertWadToAsset(uint256 _wadAmount, uint8 _assetDecimals) internal pure returns (uint256) {
        if (_assetDecimals == 18) {
            return _wadAmount;
        } else if (_assetDecimals < 18) {
            return _wadAmount / (10 ** (18 - _assetDecimals));
        } else {
            return _wadAmount * (10 ** (_assetDecimals - 18));
        }
    }

    function fill(
        address _pool,
        address _buffer,
        uint256 _bucket,
        uint256 _lps,
        uint256 _bufferLps,
        mapping(uint256 => uint256) storage _lpsMap,
        uint256[] storage _buckets,
        mapping(uint256 => uint256) storage _bucketsIndex,
        uint256 _lpDust
    ) external returns (uint256 bufferLps_) {
        uint256 afterLps;
        if (_pool == _buffer) {
            bufferLps_ = _bufferLps + _lps;
            afterLps = bufferLps_;
        } else {
            bufferLps_ = _bufferLps;
            if (_lpsMap[_bucket] == 0) {
                _bucketsIndex[_bucket] = _buckets.length;
                _buckets.push(_bucket);
            }
            _lpsMap[_bucket] += _lps;
            afterLps = _lpsMap[_bucket];
        }
        if (afterLps < _lpDust) revert IVault.DustyBucket(_pool, _bucket);
    }

    function wash(
        address _pool,
        address _buffer,
        uint256 _bucket,
        uint256 _lps,
        uint256 _bufferLps,
        mapping(uint256 => uint256) storage _lpsMap,
        uint256[] storage _buckets,
        mapping(uint256 => uint256) storage _bucketsIndex,
        uint256 _lpDust
    ) external returns (uint256 bufferLps_) {
        uint256 afterLps;
        if (_pool == _buffer) {
            bufferLps_ = _bufferLps - _lps;
            afterLps = bufferLps_;
        } else {
            bufferLps_ = _bufferLps;
            _lpsMap[_bucket] -= _lps;
            afterLps = _lpsMap[_bucket];
            if (afterLps == 0) {
                uint256 removedIndex = _bucketsIndex[_bucket];
                uint256 lastBucket = _buckets[_buckets.length - 1];
                _buckets[removedIndex] = lastBucket;
                _buckets.pop();
                _bucketsIndex[lastBucket] = removedIndex;
                delete _bucketsIndex[_bucket];
            }
        }
        if (afterLps != 0 && afterLps < _lpDust) revert IVault.DustyBucket(_pool, _bucket);
    }

    function _checkBufferRatio(
        IVaultAuth _auth,
        IBuffer _buffer,
        bool _isMovingToBuffer,
        uint256 _wadToMove,
        uint256 _totalWadAssets
    ) internal view {
        uint256 ratio = _auth.bufferRatio();
        if (ratio == 0) return; // No ratio set, allow any movement
        
        uint256 currentBufferValue = _buffer.total();
        uint256 targetBufferAmount = (_totalWadAssets * ratio) / 10000;
        
        if (_isMovingToBuffer) {
            // Moving to buffer: check if we would exceed target
            if (targetBufferAmount < currentBufferValue + _wadToMove) {
                revert IVault.BufferRatioExceeded();
            }
        } else {
            // Moving from buffer: check if we would go below target
            if (targetBufferAmount > currentBufferValue - _wadToMove) {
                revert IVault.BufferRatioExceeded();
            }
        }
    }

    function _validDestination(
        PoolInfoUtils _info,
        IPool _pool,
        uint256 _bucket,
        IVaultAuth _auth
    ) internal view {
        (,,, uint256 _bucketLP,,) = _info.bucketInfo(address(_pool), _bucket);
        if (_bucketLP != 0 && _bucketLP <= 1_000_000) {
            revert IVault.BucketLPDangerous(address(_pool), _bucket, _bucketLP);
        }
        
        // Check minimum bucket index restriction (0 = no restriction)
        uint256 minBucketIndex = _auth.minBucketIndex();
        if (minBucketIndex > 0 && _bucket < minBucketIndex) {
            revert IVault.BucketIndexTooLow(address(_pool), _bucket, minBucketIndex);
        }
    }
}
