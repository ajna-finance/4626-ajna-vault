// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Buffer} from "../src/Buffer.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {VaultBaseTest} from "./Vault.base.t.sol";

contract VaultBucketManagementTest is VaultBaseTest {
    
    function setUp() public override {
        super.setUp();
        
        // Give alice some funds in the vault to work with
        vm.startPrank(alice);
        vault.deposit(500 ether, alice);
        vm.stopPrank();
    }

    // Test bucket array management edge cases
    function test_BucketArrayManagement_RemoveLastBucket() public {
        // Move funds to multiple buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(300, 50 ether);
        
        uint256[] memory bucketsBeforeRemoval = vault.getBuckets();
        assertEq(bucketsBeforeRemoval.length, 3, "Should have 3 buckets");
        
        // Remove all funds from the last bucket (index 300) - request max to get everything available
        uint256 actualAmount = vault.lpToValue(300);
        vm.prank(keeper);
        vault.moveToBuffer(300, actualAmount);
        
        uint256[] memory bucketsAfterRemoval = vault.getBuckets();
        assertEq(bucketsAfterRemoval.length, 2, "Should have 2 buckets after removal");
        assertEq(vault.lps(300), 0, "Bucket 300 should have 0 LPs");
    }

    function test_BucketArrayManagement_RemoveMiddleBucket() public {
        // Move funds to multiple buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(300, 50 ether);
        
        uint256[] memory bucketsBeforeRemoval = vault.getBuckets();
        assertEq(bucketsBeforeRemoval.length, 3, "Should have 3 buckets");
        
        // Remove all funds from the middle bucket (index 200) - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(200);
        vm.prank(keeper);
        vault.moveToBuffer(200, actualAmount);
        
        uint256[] memory bucketsAfterRemoval = vault.getBuckets();
        assertEq(bucketsAfterRemoval.length, 2, "Should have 2 buckets after removal");
        assertEq(vault.lps(200), 0, "Bucket 200 should have 0 LPs");
        
        // Verify the last bucket was moved to the middle position
        assertEq(bucketsAfterRemoval[1], 300, "Bucket 300 should be at index 1");
    }

    function test_BucketArrayManagement_RemoveFirstBucket() public {
        // Move funds to multiple buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(300, 50 ether);
        
        uint256[] memory bucketsBeforeRemoval = vault.getBuckets();
        assertEq(bucketsBeforeRemoval.length, 3, "Should have 3 buckets");
        
        // Remove all funds from the first bucket (index 100) - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(100);
        vm.prank(keeper);
        vault.moveToBuffer(100, actualAmount);
        
        uint256[] memory bucketsAfterRemoval = vault.getBuckets();
        assertEq(bucketsAfterRemoval.length, 2, "Should have 2 buckets after removal");
        assertEq(vault.lps(100), 0, "Bucket 100 should have 0 LPs");
        
        // Verify the last bucket was moved to the first position
        assertEq(bucketsAfterRemoval[0], 300, "Bucket 300 should be at index 0");
        assertEq(bucketsAfterRemoval[1], 200, "Bucket 200 should be at index 1");
    }

    function test_BucketArrayManagement_RemoveOnlyBucket() public {
        // Move funds to only one bucket
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        
        uint256[] memory bucketsBeforeRemoval = vault.getBuckets();
        assertEq(bucketsBeforeRemoval.length, 1, "Should have 1 bucket");
        
        // Remove all funds from the only bucket - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(100);
        vm.prank(keeper);
        vault.moveToBuffer(100, actualAmount);
        
        uint256[] memory bucketsAfterRemoval = vault.getBuckets();
        assertEq(bucketsAfterRemoval.length, 0, "Should have 0 buckets after removal");
        assertEq(vault.lps(100), 0, "Bucket 100 should have 0 LPs");
    }

    function test_BucketIndexMapping_Consistency() public {
        // Move funds to multiple buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(300, 50 ether);
        
        // Check initial bucket indices
        assertEq(vault.bucketsIndex(100), 0, "Bucket 100 should be at index 0");
        assertEq(vault.bucketsIndex(200), 1, "Bucket 200 should be at index 1");
        assertEq(vault.bucketsIndex(300), 2, "Bucket 300 should be at index 2");
        
        // Remove middle bucket - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(200);
        vm.prank(keeper);
        vault.moveToBuffer(200, actualAmount);
        
        // Check updated indices
        assertEq(vault.bucketsIndex(100), 0, "Bucket 100 should still be at index 0");
        assertEq(vault.bucketsIndex(200), 0, "Bucket 200 index should be deleted (default 0)");
        assertEq(vault.bucketsIndex(300), 1, "Bucket 300 should now be at index 1");
        
        // Verify bucket array
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets[0], 100, "First bucket should be 100");
        assertEq(buckets[1], 300, "Second bucket should be 300");
    }

    // Test dusty bucket prevention
    function test_DustyBucket_PreventionOnFill() public {
        uint256 dustAmount = vault.LP_DUST() - 1;
        
        // Try to create a dusty bucket (should revert)
        vm.expectRevert(abi.encodeWithSelector(IVault.DustyBucket.selector, address(pool), 100));
        vm.prank(keeper);
        vault.moveFromBuffer(100, dustAmount);
    }

    function test_DustyBucket_PreventionOnWash() public {
        // First create a valid bucket  
        uint256 validAmount = 10 ether;
        uint256 bucketIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(bucketIndex, validAmount);
        
        // Calculate amount to remove that would leave LP_DUST - 1 LPs remaining
        uint256 vaultLps = vault.lps(bucketIndex);
        uint256 vaultQuoteTokens = vault.lpToValue(bucketIndex);
        uint256 targetRemainingLps = vault.LP_DUST() - 1;
        uint256 lpsToRemove = vaultLps - targetRemainingLps;
        
        // Convert LPs to quote tokens for removal (proportional calculation)
        uint256 removeAmount = (vaultQuoteTokens * lpsToRemove) / vaultLps;
        vm.expectRevert(abi.encodeWithSelector(IVault.DustyBucket.selector, address(pool), bucketIndex));
        vm.prank(keeper);
        vault.moveToBuffer(bucketIndex, removeAmount);
    }

    function test_DustyBucket_AllowCompleteRemoval() public {
        // Create a valid bucket
        uint256 validAmount = 10 ether;
        vm.prank(keeper);
        vault.moveFromBuffer(100, validAmount);
        
        // Complete removal should work - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(100);
        vm.prank(keeper);
        vault.moveToBuffer(100, actualAmount);
        
        assertEq(vault.lps(100), 0, "Bucket should be empty");
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 0, "Should have no buckets");
    }

    // Test buffer LP management
    function test_BufferLps_DustyPrevention() public {
        // Move most funds to a bucket, leaving potential dust in buffer
        uint256 totalInBuffer = vault.totalAssets();
        uint256 moveAmount = totalInBuffer - (vault.LP_DUST() - 1);
        
        // This should revert because it would leave dust in the buffer
        vm.expectRevert(abi.encodeWithSelector(IVault.DustyBucket.selector, address(buffer), 0));
        vm.prank(keeper);
        vault.moveFromBuffer(100, moveAmount);
    }

    function test_BufferLps_AllowCompleteEmptying() public {
        // Move all funds from buffer should work
        uint256 totalInBuffer = vault.totalAssets();
        vm.prank(keeper);
        vault.moveFromBuffer(100, totalInBuffer);
        
        assertEq(vault.bufferLps(), 0, "Buffer should be empty");
    }

    // Test multiple buckets with same index (should not be possible)
    function test_NoDuplicateBucketIndices() public {
        // Add funds to bucket 100
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        
        // Add more funds to same bucket - should increase LPs, not create duplicate
        vm.prank(keeper);
        vault.moveFromBuffer(100, 50 ether);
        
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 1, "Should still have only 1 bucket");
        assertTrue(vault.lps(100) > 50 ether, "Bucket 100 should have more LPs");
    }

    // Test moving funds between buckets
    function test_MoveBetweenBuckets() public {
        // Setup: funds in bucket 100
        vm.prank(keeper);
        vault.moveFromBuffer(100, 100 ether);
        
        // Move funds from bucket 100 to bucket 200
        vm.prank(keeper);
        vault.move(100, 200, 50 ether);
        
        // Verify the move
        assertTrue(vault.lps(100) > 0, "Bucket 100 should still have funds");
        assertTrue(vault.lps(200) > 0, "Bucket 200 should have funds");
        
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 2, "Should have 2 buckets");
    }

    // Test bucket operations with maximum number of buckets
    function test_ManyBuckets_Operations() public {
        // Create many buckets (e.g., 10)
        uint256 amountPerBucket = 40 ether;
        for (uint i = 1; i <= 10; i++) {
            vm.prank(keeper);
            vault.moveFromBuffer(i * 100, amountPerBucket);
        }
        
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 10, "Should have 10 buckets");
        
        // Remove a bucket in the middle - use actual amount in bucket
        uint256 actualAmount = vault.lpToValue(500);
        vm.prank(keeper);
        vault.moveToBuffer(500, actualAmount);
        
        buckets = vault.getBuckets();
        assertEq(buckets.length, 9, "Should have 9 buckets after removal");
        
        // Verify no bucket 500 exists
        assertEq(vault.lps(500), 0, "Bucket 500 should be empty");
    }

    // Test totalAssets calculation with multiple buckets
    function test_TotalAssets_MultipleBuckets() public {
        uint256 initialTotal = vault.totalAssets();
        
        // Distribute funds across multiple buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 100 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 100 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(300, 100 ether);
        
        // Total assets should remain the same (minus any fees)
        uint256 finalTotal = vault.totalAssets();
        
        // Allow for small rounding differences or fees
        assertApproxEqAbs(finalTotal, initialTotal, 1 ether, "Total assets should be preserved");
    }

    // Test using HTP (Highest Threshold Price) index
    function test_HTPBucketIndex() public {
        // Use HTP index which is always valid in both mock and live environments
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        assertTrue(vault.lps(htpIndex) > 0, "HTP bucket should have LPs");
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 1, "Should have 1 bucket");
        assertEq(buckets[0], htpIndex, "Should be HTP bucket");
    }

    // Test removing all buckets and then adding new ones
    function test_RemoveAllBuckets_ThenAddNew() public {
        // Create buckets
        vm.prank(keeper);
        vault.moveFromBuffer(100, 100 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(200, 100 ether);
        
        // Remove all buckets - use actual amounts in buckets
        uint256 actualAmount100 = vault.lpToValue(100);
        uint256 actualAmount200 = vault.lpToValue(200);
        vm.prank(keeper);
        vault.moveToBuffer(100, actualAmount100);
        vm.prank(keeper);
        vault.moveToBuffer(200, actualAmount200);
        
        uint256[] memory buckets = vault.getBuckets();
        assertEq(buckets.length, 0, "Should have no buckets");
        
        // Add new buckets
        vm.prank(keeper);
        vault.moveFromBuffer(300, 50 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(400, 50 ether);
        
        buckets = vault.getBuckets();
        assertEq(buckets.length, 2, "Should have 2 new buckets");
        assertEq(buckets[0], 300, "First bucket should be 300");
        assertEq(buckets[1], 400, "Second bucket should be 400");
    }
}