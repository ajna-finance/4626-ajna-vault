// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Buffer} from "../src/Buffer.sol";
import {AjnaVaultLibrary} from "../src/AjnaVaultLibrary.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {VaultBaseTest} from "./Vault.base.t.sol";

contract VaultDecimalConversionTest is VaultBaseTest {
    
    function setUp() public override {
        super.setUp();
    }

    // Edge case tests (basic conversions are covered by fuzz tests below)

    // Test edge cases - very small amounts
    function test_ConversionPrecisionLoss_SmallAmounts() public pure {
        // Test with 1 wei in 6 decimal token
        uint256 smallAmount = 1; // 1 wei of USDC
        uint256 wadAmount = AjnaVaultLibrary.convertAssetToWad(smallAmount, 6);
        assertEq(wadAmount, 10**12, "Small amount conversion to WAD failed");
        
        // Convert back and check for precision loss
        uint256 backToAsset = AjnaVaultLibrary.convertWadToAsset(wadAmount, 6);
        assertEq(backToAsset, smallAmount, "Round trip conversion should preserve value");
    }

    // Test edge cases - very large amounts
    function test_ConversionOverflow_LargeAmounts() public pure {
        // Test with max uint256 / 10**12 (safe for 6 decimal conversion)
        uint256 maxSafeAmount = type(uint256).max / 10**12;
        uint256 wadAmount = AjnaVaultLibrary.convertAssetToWad(maxSafeAmount, 6);
        
        // Should not overflow
        assertTrue(wadAmount > 0, "Large amount conversion should not overflow");
        
        // Convert back
        uint256 backToAsset = AjnaVaultLibrary.convertWadToAsset(wadAmount, 6);
        assertEq(backToAsset, maxSafeAmount, "Large amount round trip should preserve value");
    }

    // Test precision loss in conversion
    function test_PrecisionLossInDivision() public pure {
        // Amount that doesn't divide evenly when converting from WAD to 6 decimals
        uint256 wadAmount = 1000 * 10**18 + 1; // 1000.000000000000000001 WAD
        uint256 assetAmount = AjnaVaultLibrary.convertWadToAsset(wadAmount, 6);
        
        // Should lose the extra precision
        assertEq(assetAmount, 1000 * 10**6, "Should truncate extra precision");
        
        // Convert back - will have lost precision
        uint256 backToWad = AjnaVaultLibrary.convertAssetToWad(assetAmount, 6);
        assertEq(backToWad, 1000 * 10**18, "Precision loss is expected");
        assertTrue(backToWad < wadAmount, "Should have lost precision");
    }

    // Fuzz testing for conversion functions
    function testFuzz_ConversionRoundTrip_6Decimals(uint128 amount) public pure {
        vm.assume(amount > 0 && amount < type(uint128).max);
        
        uint256 wadAmount = AjnaVaultLibrary.convertAssetToWad(amount, 6);
        uint256 backToAsset = AjnaVaultLibrary.convertWadToAsset(wadAmount, 6);
        
        assertEq(backToAsset, amount, "Round trip conversion should preserve value for 6 decimals");
    }

    function testFuzz_ConversionRoundTrip_8Decimals(uint128 amount) public pure {
        vm.assume(amount > 0 && amount < type(uint128).max);
        
        uint256 wadAmount = AjnaVaultLibrary.convertAssetToWad(amount, 8);
        uint256 backToAsset = AjnaVaultLibrary.convertWadToAsset(wadAmount, 8);
        
        assertEq(backToAsset, amount, "Round trip conversion should preserve value for 8 decimals");
    }

    function testFuzz_ConversionRoundTrip_18Decimals(uint256 amount) public pure {
        vm.assume(amount > 0 && amount < type(uint256).max);
        
        uint256 wadAmount = AjnaVaultLibrary.convertAssetToWad(amount, 18);
        uint256 backToAsset = AjnaVaultLibrary.convertWadToAsset(wadAmount, 18);
        
        assertEq(backToAsset, amount, "Round trip conversion should preserve value for 18 decimals");
    }
}
