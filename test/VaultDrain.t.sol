// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {IVault} from "../src/interfaces/IVault.sol";

contract VaultDrainTest is VaultBaseTest {

    function setUp() public override {
        super.setUp();

        // Setup initial vault state with funds
        deal(vault.asset(), alice, 1000 ether);
        vm.prank(alice);
        vault.deposit(1000 ether, alice);
    }

    // Helper function to mock lenderInfo for both local and fork tests
    function _mockLenderInfo(uint256 _bucket, uint256 _newLps) internal {
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(
                pool.lenderInfo.selector,
                _bucket,
                address(vault)
            ),
            abi.encode(_newLps, block.timestamp)
        );
    }

    // PERMISSION TESTS

    event Drain(address caller, uint256 bucket, uint256 lps, uint256 newLps);

    function test_admin_canCallDrain() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return fewer LPs (simulating a drain scenario)
        uint256 newLps = originalLps / 2;
        _mockLenderInfo(4000, newLps);

        // Admin should be able to call drain
        vm.expectEmit(true, true, true, true);
        emit Drain(admin, 4000, originalLps, newLps);

        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were updated
        assertEq(vault.lps(4000), newLps, "LPs should be updated to new value");
    }

    function test_keeper_canCallDrain() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return fewer LPs
        uint256 newLps = originalLps / 3;
        _mockLenderInfo(4000, newLps);

        // Keeper should be able to call drain
        vm.expectEmit(true, true, true, true);
        emit Drain(keeper, 4000, originalLps, newLps);

        vm.prank(keeper);
        vault.drain(4000);

        // Verify the LPs were updated
        assertEq(vault.lps(4000), newLps, "LPs should be updated to new value");
    }

    function test_fail_unauthorizedUser_cannotCallDrain() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        // Unauthorized user should not be able to call drain
        vm.expectRevert(IVault.NotAuthorized.selector);
        vm.prank(alice);
        vault.drain(4000);
    }

    function test_fail_nonKeeper_cannotCallDrain() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        // Non-keeper, non-admin user should not be able to call drain
        vm.expectRevert(IVault.NotAuthorized.selector);
        vm.prank(bob);
        vault.drain(4000);
    }

    function test_fail_drain_whenPaused() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        // Pause the vault
        vm.prank(admin);
        auth.pause();

        // Drain should fail when vault is paused
        vm.expectRevert(IVault.VaultPaused.selector);
        vm.prank(admin);
        vault.drain(4000);
    }

    // FUNCTIONALITY TESTS

    function test_drain_updatesLpsWhenPoolHasLess() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 200 ether);

        uint256 originalLps = vault.lps(4000);
        uint256 originalTotalAssets = vault.totalAssets();
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return fewer LPs (75% of original)
        uint256 newLps = (originalLps * 75) / 100;
        _mockLenderInfo(4000, newLps);

        // Call drain
        vm.expectEmit(true, true, true, true);
        emit Drain(admin, 4000, originalLps, newLps);

        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were updated
        assertEq(vault.lps(4000), newLps, "LPs should be updated to new value");

        // Total assets should be reduced (since we lost some LPs)
        assertLt(vault.totalAssets(), originalTotalAssets, "Total assets should decrease when LPs are drained");
    }

    function test_drain_doesNothingWhenPoolHasMore() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 200 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return more LPs (120% of original)
        uint256 newLps = (originalLps * 120) / 100;
        _mockLenderInfo(4000, newLps);

        // Call drain - should do nothing and not emit event
        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were NOT updated (remained the same)
        assertEq(vault.lps(4000), originalLps, "LPs should remain unchanged when pool has more");
    }

    function test_drain_doesNothingWhenPoolHasEqual() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 200 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return exactly the same LPs
        _mockLenderInfo(4000, originalLps);

        // Call drain - should do nothing
        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were NOT updated (remained the same)
        assertEq(vault.lps(4000), originalLps, "LPs should remain unchanged when pool has equal amount");
    }

    function test_drain_handlesZeroTrackedLps() public {
        // Use a bucket that has no tracked LPs
        uint256 emptyBucket = 5000;
        assertEq(vault.lps(emptyBucket), 0, "Bucket should start with 0 LPs");

        // Mock the pool to also return 0 LPs
        _mockLenderInfo(emptyBucket, 0);

        // Call drain - should handle gracefully
        vm.prank(admin);
        vault.drain(emptyBucket);

        // Should still be 0
        assertEq(vault.lps(emptyBucket), 0, "Empty bucket should remain empty");
    }

    function test_drain_handlesZeroPoolLps() public {
        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Mock the pool to return 0 LPs (complete drain)
        _mockLenderInfo(4000, 0);

        // Call drain
        vm.expectEmit(true, true, true, true);
        emit Drain(admin, 4000, originalLps, 0);

        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were set to 0
        assertEq(vault.lps(4000), 0, "LPs should be set to 0 when pool is completely drained");
    }

    // FORK-SPECIFIC TESTS (use real pool data)

    function test_drain_onLiveFork() public onlyLiveFork {
        // Setup with real pool data
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        // Move some funds to a bucket
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);

        uint256 originalLps = vault.lps(htpIndex);
        uint256 originalTotalAssets = vault.totalAssets();
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Get the actual pool LPs for this bucket
        (uint256 actualPoolLps, /* depositTime */) = pool.lenderInfo(htpIndex, address(vault));

        console.log("Original tracked LPs:", originalLps);
        console.log("Actual pool LPs:", actualPoolLps);

        if (actualPoolLps < originalLps) {
            // If pool has less, drain should update
            vm.expectEmit(true, true, true, true);
            emit Drain(admin, htpIndex, originalLps, actualPoolLps);

            vm.prank(admin);
            vault.drain(htpIndex);

            assertEq(vault.lps(htpIndex), actualPoolLps, "LPs should be updated to actual pool value");
            assertLe(vault.totalAssets(), originalTotalAssets, "Total assets should not increase");
        } else {
            // If pool has same or more, drain should do nothing
            vm.prank(admin);
            vault.drain(htpIndex);

            assertEq(vault.lps(htpIndex), originalLps, "LPs should remain unchanged");
            assertEq(vault.totalAssets(), originalTotalAssets, "Total assets should remain unchanged");
        }
    }

    function test_drain_multipleRealBuckets_onLiveFork() public onlyLiveFork {
        // Use real bucket indices around HTP
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 bucket1 = htpIndex;
        uint256 bucket2 = htpIndex + 100;
        uint256 bucket3 = htpIndex + 200;

        // Move funds to multiple real buckets
        vm.prank(keeper);
        vault.moveFromBuffer(bucket1, 30 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(bucket2, 30 ether);
        vm.prank(keeper);
        vault.moveFromBuffer(bucket3, 30 ether);

        // Get actual pool LPs for each bucket
        (uint256 actualLps1, ) = pool.lenderInfo(bucket1, address(vault));
        (uint256 actualLps2, ) = pool.lenderInfo(bucket2, address(vault));
        (uint256 actualLps3, ) = pool.lenderInfo(bucket3, address(vault));

        uint256 totalAssetsBefore = vault.totalAssets();

        // Drain each bucket
        vm.prank(admin);
        vault.drain(bucket1);
        vm.prank(admin);
        vault.drain(bucket2);
        vm.prank(admin);
        vault.drain(bucket3);

        // Verify all buckets are now synchronized with actual pool state
        assertEq(vault.lps(bucket1), actualLps1, "Bucket 1 should match actual pool LPs");
        assertEq(vault.lps(bucket2), actualLps2, "Bucket 2 should match actual pool LPs");
        assertEq(vault.lps(bucket3), actualLps3, "Bucket 3 should match actual pool LPs");

        // Total assets should not increase (can only decrease or stay same)
        assertLe(vault.totalAssets(), totalAssetsBefore, "Total assets should not increase after drain");
    }

    // FUZZ TESTS

    function testFuzz_drain_withVariousLpReductions(uint256 _reductionPercent) public {
        // Bound the reduction percentage to 0-100%
        _reductionPercent = bound(_reductionPercent, 0, 100);

        // Setup: move funds to create bucket with LPs
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 100 ether);

        uint256 originalLps = vault.lps(4000);
        assertGt(originalLps, 0, "Should have LPs in bucket");

        // Calculate new LPs based on reduction percentage
        uint256 newLps = (originalLps * (100 - _reductionPercent)) / 100;
        _mockLenderInfo(4000, newLps);

        uint256 originalTotalAssets = vault.totalAssets();

        if (newLps < originalLps) {
            // Should emit drain event
            vm.expectEmit(true, true, true, true);
            emit Drain(admin, 4000, originalLps, newLps);
        }

        vm.prank(admin);
        vault.drain(4000);

        // Verify the LPs were updated correctly
        assertEq(vault.lps(4000), newLps, "LPs should be updated to new value");

        if (newLps < originalLps) {
            // Total assets should decrease when LPs are reduced
            assertLt(vault.totalAssets(), originalTotalAssets, "Total assets should decrease when LPs are drained");
        } else {
            // Total assets should remain the same when no drain occurs
            assertEq(vault.totalAssets(), originalTotalAssets, "Total assets should remain same when no drain occurs");
        }
    }
}