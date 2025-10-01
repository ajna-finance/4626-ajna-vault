// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {AjnaVaultLibrary as AVL} from "../src/AjnaVaultLibrary.sol";

contract VaultBucketIndexRestrictionTest is VaultBaseTest {
    
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
    
    // Test that move succeeds when no bucket index restriction is set (default 0)
    function test_moveSucceedsWithNoRestriction() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Move funds from buffer to a bucket
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Mock destination bucket with safe LP
        _mockBucketInfo(address(pool), 3500, 5_000_000, 100 ether, 0);
        
        // This should succeed as no restriction is set (minBucketIndex = 0)
        vm.prank(keeper);
        vault.move(4000, 3500, 5 ether);
    }
    
    // Test that admin can set minimum bucket index
    function test_adminCanSetMinBucketIndex() public {
        uint256 newMinIndex = 4000;
        
        vm.prank(admin);
        auth.setMinBucketIndex(newMinIndex);
        
        assertEq(auth.minBucketIndex(), newMinIndex);
    }
    
    // Test that non-admin cannot set minimum bucket index
    function test_nonAdminCannotSetMinBucketIndex() public {
        vm.expectRevert(IVaultAuth.NotAuthorized.selector);
        vm.prank(alice);
        auth.setMinBucketIndex(4000);
    }
    
    // Test that move fails when destination bucket index is below minimum
    function test_moveFailsWhenBucketIndexTooLow() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Set minimum bucket index to 4000
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        
        // Mock destination bucket with safe LP but index below minimum
        _mockBucketInfo(address(pool), 3900, 5_000_000, 100 ether, 0);
        
        // This should fail as destination bucket index (3900) < minimum (4000)
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketIndexTooLow.selector,
                address(pool),
                3900,
                4000
            )
        );
        vm.prank(keeper);
        vault.move(4000, 3900, 5 ether);
    }
    
    // Test that move succeeds when destination bucket index equals minimum
    function test_moveSucceedsAtExactMinimum() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Set minimum bucket index to 4100
        vm.prank(admin);
        auth.setMinBucketIndex(4100);
        
        // Mock destination bucket with safe LP and index equal to minimum
        _mockBucketInfo(address(pool), 4100, 5_000_000, 100 ether, 0);
        
        // This should succeed as destination bucket index (4100) == minimum (4100)
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Test that move succeeds when destination bucket index is above minimum
    function test_moveSucceedsAboveMinimum() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Set minimum bucket index to 4000
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        
        // Mock destination bucket with safe LP and index above minimum
        _mockBucketInfo(address(pool), 4200, 5_000_000, 100 ether, 0);
        
        // This should succeed as destination bucket index (4200) > minimum (4000)
        vm.prank(keeper);
        vault.move(4000, 4200, 5 ether);
    }
    
    // Test that moveFromBuffer respects bucket index restriction
    function test_moveFromBufferFailsWhenBucketIndexTooLow() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Set minimum bucket index to 4000
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        
        // Mock destination bucket with safe LP but index below minimum
        _mockBucketInfo(address(pool), 3800, 5_000_000, 100 ether, 0);
        
        // This should fail as destination bucket index (3800) < minimum (4000)
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketIndexTooLow.selector,
                address(pool),
                3800,
                4000
            )
        );
        vm.prank(keeper);
        vault.moveFromBuffer(3800, 5 ether);
    }
    
    // Test that moveFromBuffer succeeds when bucket index is valid
    function test_moveFromBufferSucceedsWithValidBucketIndex() public {
        // Setup: deposit funds to vault
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Set minimum bucket index to 4000
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        
        // Mock destination bucket with safe LP and valid index
        _mockBucketInfo(address(pool), 4100, 5_000_000, 100 ether, 0);
        
        // This should succeed as destination bucket index (4100) >= minimum (4000)
        vm.prank(keeper);
        vault.moveFromBuffer(4100, 5 ether);
        
        // Verify the move happened
        assertGt(vault.lps(4100), 0);
    }
    
    // Test updating minimum bucket index
    function test_updatingMinBucketIndex() public {
        // Initially no restriction
        assertEq(auth.minBucketIndex(), 0);
        
        // Set initial minimum
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        assertEq(auth.minBucketIndex(), 4000);
        
        // Update to stricter restriction (lower index = higher price)
        vm.prank(admin);
        auth.setMinBucketIndex(3500);
        assertEq(auth.minBucketIndex(), 3500);
        
        // Update to looser restriction (higher index = lower price)
        vm.prank(admin);
        auth.setMinBucketIndex(5000);
        assertEq(auth.minBucketIndex(), 5000);
        
        // Remove restriction
        vm.prank(admin);
        auth.setMinBucketIndex(0);
        assertEq(auth.minBucketIndex(), 0);
    }
    
    // Test both LP and index restrictions together
    function test_bothLPAndIndexRestrictions() public {
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Set minimum bucket index
        vm.prank(admin);
        auth.setMinBucketIndex(4000);
        
        // Test 1: Safe LP but bucket index too low
        _mockBucketInfo(address(pool), 3900, 5_000_000, 100 ether, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketIndexTooLow.selector,
                address(pool),
                3900,
                4000
            )
        );
        vm.prank(keeper);
        vault.move(4000, 3900, 5 ether);
        
        // Test 2: Valid bucket index but dangerous LP
        _mockBucketInfo(address(pool), 4100, 500_000, 0.5 ether, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketLPDangerous.selector,
                address(pool),
                4100,
                500_000
            )
        );
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
        
        // Test 3: Both restrictions satisfied
        _mockBucketInfo(address(pool), 4100, 5_000_000, 100 ether, 0);
        vm.prank(keeper);
        vault.move(4000, 4100, 5 ether);
    }
    
    // Fuzz test for bucket index validation
    function testFuzz_bucketIndexValidation(uint256 bucketIndex, uint256 minBucketIndex) public {
        // Bound inputs to reasonable values
        bucketIndex = bound(bucketIndex, 1, 7388); // Ajna's bucket range
        minBucketIndex = bound(minBucketIndex, 0, 7388);
        
        // Setup: deposit funds and move to a bucket
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        vm.prank(keeper);
        vault.moveFromBuffer(4000, 10 ether);
        
        // Set minimum bucket index
        vm.prank(admin);
        auth.setMinBucketIndex(minBucketIndex);
        
        // Mock destination bucket with safe LP
        _mockBucketInfo(address(pool), bucketIndex, 5_000_000, 100 ether, 0);
        
        // Determine expected behavior
        bool shouldRevert = minBucketIndex > 0 && bucketIndex < minBucketIndex;
        
        if (shouldRevert) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IVault.BucketIndexTooLow.selector,
                    address(pool),
                    bucketIndex,
                    minBucketIndex
                )
            );
        }
        
        vm.prank(keeper);
        vault.move(4000, bucketIndex, 1 ether);
        
        // If we reach here and shouldn't have reverted, the test passes
        if (!shouldRevert) {
            assertTrue(true, "Move succeeded as expected");
        }
    }
    
    // Test for live fork - uses real pool data
    function test_bucketIndexRestrictionOnFork() public onlyLiveFork {
        // Setup: deposit funds
        deal(vault.asset(), alice, 100 ether);
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        // Move some funds to a known bucket
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 10 ether);
        
        console.log("HTP index:", htpIndex);
        
        // Test 1: Set minimum bucket index above HTP (stricter - higher price)
        uint256 minIndex = htpIndex > 100 ? htpIndex - 100 : 1;
        vm.prank(admin);
        auth.setMinBucketIndex(minIndex);
        
        console.log("Set min bucket index to:", minIndex);
        
        // Try to move to a bucket below minimum (should fail)
        uint256 lowIndex = minIndex > 50 ? minIndex - 50 : minIndex - 1;
        if (lowIndex < minIndex && lowIndex > 0) {
            // Mock a safe LP bucket at the low index
            _mockBucketInfo(address(pool), lowIndex, 5_000_000, 1 ether, 0);
            
            vm.expectRevert(
                abi.encodeWithSelector(
                    IVault.BucketIndexTooLow.selector,
                    address(pool),
                    lowIndex,
                    minIndex
                )
            );
            vm.prank(keeper);
            vault.move(htpIndex, lowIndex, 1 ether);
            
            console.log("Move to low index", lowIndex, "failed as expected");
        }
        
        // Clear mocks for real data test
        vm.clearMockedCalls();
        
        // Test 2: Move to a valid bucket (at or above minimum)
        uint256 validIndex = htpIndex + 100;
        (,,,uint256 validBucketLP,,) = info.bucketInfo(address(pool), validIndex);
        
        console.log("Valid index", validIndex, "LP:", validBucketLP);
        
        if (validBucketLP == 0 || validBucketLP > 1_000_000) {
            vm.prank(keeper);
            vault.move(htpIndex, validIndex, 1 ether);
            console.log("Move to valid index", validIndex, "succeeded");
        } else {
            console.log("Valid index has dangerous LP, skipping move test");
        }
    }

    event MinBucketIndexSet(uint256 newMinBucketIndex);

    // Test event emission
    function test_minBucketIndexSetEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MinBucketIndexSet(4000);

        vm.prank(admin);
        auth.setMinBucketIndex(4000);
    }

    // Test that returnQuoteToken fails when toIndex is invalid (below minimum)
    function test_returnQuoteToken_failsWithInvalidToIndex() public {
        // Setup: pause vault and give admin some tokens
        vm.prank(admin);
        auth.pause();

        deal(vault.asset(), admin, 100 ether);
        vm.startPrank(admin);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);

        // Set minimum bucket index to 4000
        auth.setMinBucketIndex(4000);

        // Mock destination bucket with safe LP but index below minimum
        _mockBucketInfo(address(pool), 3800, 5_000_000, 100 ether, 0);

        // This should fail as destination bucket index (3800) < minimum (4000)
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.BucketIndexTooLow.selector,
                address(pool),
                3800,
                4000
            )
        );
        vault.returnQuoteToken(3800, 10 ether);
        vm.stopPrank();
    }
}
