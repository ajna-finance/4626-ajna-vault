// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {AjnaVaultLibrary as AVL} from "../src/AjnaVaultLibrary.sol";

contract VaultBucketLPValidationTest is VaultBaseTest {
    
    uint256 constant DANGEROUS_LP_THRESHOLD = 1_000_000;
    
    // Helper function to mock bucket info for both local and fork tests
    function _mockBucketInfo(
        address _pool,
        uint256 _bucket,
        uint256 _bucketLP,
        uint256 _quoteToken,
        uint256 _collateral
    ) internal {
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(
                PoolInfoUtils.bucketInfo.selector,
                _pool,
                _bucket
            ),
            abi.encode(
                1e18,        // price
                _quoteToken, // quoteToken
                _collateral, // collateral  
                _bucketLP,   // bucketLP
                0,           // scale
                0            // exchangeRate
            )
        );
    }
    
    // Test that move succeeds with safe bucket LP (> 1_000_000)
    function test_moveSucceedsWithSafeBucketLP() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Move funds from buffer to a bucket
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with safe LP amount (> 1_000_000)
        _mockBucketInfo(address(pool), 4100, 2_000_000, 100 ether, 0);
        
        // This should succeed as bucket LP is safe
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Test that move succeeds when bucket LP is 0 (empty bucket)
    function test_moveSucceedsWithEmptyBucket() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with 0 LP (empty bucket)
        _mockBucketInfo(address(pool), 4100, 0, 0, 0);
        
        // This should succeed as empty buckets are allowed
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Test boundary condition: exactly at threshold (1_000_000)
    function test_moveFailsAtExactThreshold() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with exactly 1_000_000 LP
        _mockBucketInfo(address(pool), 4100, DANGEROUS_LP_THRESHOLD, 1 ether, 0);
        
        // This should fail as bucket LP is exactly at dangerous threshold
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketLPDangerous.selector,
                address(pool),
                4100,
                DANGEROUS_LP_THRESHOLD
            )
        );
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Test just above threshold (1_000_001)
    function test_moveSucceedsJustAboveThreshold() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with 1_000_001 LP (just above threshold)
        _mockBucketInfo(address(pool), 4100, DANGEROUS_LP_THRESHOLD + 1, 1 ether, 0);
        
        // This should succeed as bucket LP is just above dangerous threshold
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Test moveFromBuffer with dangerous bucket LP
    function test_moveFromBufferFailsWithDangerousBucketLP() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Mock destination bucket with dangerous LP amount
        _mockBucketInfo(address(pool), 4100, 100_000, 0.1 ether, 0);
        
        // This should fail as bucket LP is dangerous
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketLPDangerous.selector,
                address(pool),
                4100,
                100_000
            )
        );
        vm.prank(keeper);
        vault.moveFromBuffer(4100, 5 ether);
    }
    
    // Test moveFromBuffer with safe bucket LP
    function test_moveFromBufferSucceedsWithSafeBucketLP() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Mock destination bucket with safe LP amount
        _mockBucketInfo(address(pool), 4100, 10_000_000, 10 ether, 0);
        
        // This should succeed as bucket LP is safe
        vm.prank(keeper);
        vault.moveFromBuffer(4100, 5 ether);
        
        // Verify the move happened
        assertGt(vault.lps(4100), 0);
    }
    
    // Test with very small dangerous LP values
    function test_moveFailsWithVerySmallDangerousLP() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Test with LP = 1 (minimum dangerous value)
        _mockBucketInfo(address(pool), 4100, 1, 0.000001 ether, 0);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketLPDangerous.selector,
                address(pool),
                4100,
                1
            )
        );
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Fuzz test for various LP values
    function testFuzz_bucketLPValidation(uint256 bucketLP) public {
        vm.assume(bucketLP < type(uint256).max / 2); // Avoid overflow
        
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with fuzzed LP amount
        _mockBucketInfo(address(pool), 4100, bucketLP, 1 ether, 0);
        
        // Determine expected behavior
        bool shouldRevert = bucketLP > 0 && bucketLP <= DANGEROUS_LP_THRESHOLD;
        
        if (shouldRevert) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IVault.BucketLPDangerous.selector,
                    address(pool),
                    4100,
                    bucketLP
                )
            );
        }
        
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
        
        // If we reach here and shouldn't have reverted, the test passes
        if (!shouldRevert) {
            assertTrue(true, "Move succeeded as expected");
        }
    }
    
    // Test for live fork - uses real pool data
    function test_bucketLPValidationOnFork() public onlyLiveFork {
        // Setup: deposit funds
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // First, move some funds to a known bucket
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 10 ether);
        
        // Get real bucket info from the fork
        (,,,uint256 realBucketLP,,) = info.bucketInfo(address(pool), htpIndex + 1);
        console.log("Real bucket LP at index", htpIndex + 1, ":", realBucketLP);
        
        // Test with a mock dangerous bucket
        _mockBucketInfo(address(pool), htpIndex + 100, 500_000, 0.5 ether, 0);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketLPDangerous.selector,
                address(pool),
                htpIndex + 100,
                500_000
            )
        );
        vm.prank(keeper);
        vault.move(htpIndex, htpIndex + 100, 5 ether);
        
        // Clear mock and test with real data if bucket is safe
        vm.clearMockedCalls();
    }
}