// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {PoolMock} from "./PoolMock.sol";
contract SageMock {
    uint256 public constant WAD = 1e18;

    constructor() {}

    function bucketInfo(address _pool, uint256 _bucket) external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        uint256 bucketLP = PoolMock(_pool).bucketLps(_bucket);
        uint256 bucketAssets = PoolMock(_pool).bucketAssets(_bucket);
        
        return (
            1e18,        // price
            bucketAssets, // quoteToken - should be bucket-specific assets, not global total
            0,           // collateral
            bucketLP,    // bucketLP
            0,           // scale
            0            // exchangeRate
        );
    }
    function depositFeeRate(address /* _pool */) external pure returns (uint256) {
        return WAD * 10 / 10000;
    }
    function htp(address _pool) external view returns (uint256) {}
    function lpToQuoteToken(address _pool, uint256 _lp, uint256 _index) external view returns (uint256) {}
    function lup(address /* _pool */) external pure returns (uint256) {
        return 1161400082895345507;
    }
    function lupIndex(address /* _pool */) external pure returns (uint256) {
        return 4126;
    }
    function poolLoansInfo(address _pool) external view returns (uint256) {}
    function priceToIndex(uint256 _price) external view returns (uint256) {}
}
