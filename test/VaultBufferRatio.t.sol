// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {IVaultAuth} from "../src/VaultAuth.sol";

contract VaultBufferRatioTest is VaultBaseTest {
    event BufferRatioSet(uint256 newBufferRatio);

    function setUp() public override {
        super.setUp();
        
        // Give alice some assets and deposit to vault
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        deal(vault.asset(), alice, depositAmount);
        
        vm.startPrank(alice);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function test_setBufferRatio() public {
        uint256 newRatio = 1000; // 10%
        
        vm.expectEmit(true, true, true, true);
        emit BufferRatioSet(newRatio);
        
        vm.prank(admin);
        auth.setBufferRatio(newRatio);
        
        assertEq(auth.bufferRatio(), newRatio, "Buffer ratio not set correctly");
    }

    function test_fail_setBufferRatio_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setBufferRatio(1000);
    }

    function test_fail_setBufferRatio_tooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.BufferRatioTooHigh.selector));
        vm.prank(admin);
        auth.setBufferRatio(10001); // > 100%
    }

    function test_setBufferRatio_maxAllowed() public {
        vm.prank(admin);
        auth.setBufferRatio(10000); // Exactly 100%
        assertEq(auth.bufferRatio(), 10000, "Should allow exactly 100%");
    }

    function test_bufferRatio_noRestrictionWhenZero() public {
        // Default ratio should be 0 (no restriction)
        assertEq(auth.bufferRatio(), 0, "Default buffer ratio should be 0");
        
        // Should be able to move all assets to pool buckets
        uint256 bufferBalance = IERC20(vault.asset()).balanceOf(vault.buffer());
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, bufferBalance);
        
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), 0, "Buffer should be empty");
    }

    function test_moveToBuffer_respectsRatio() public {
        // Set 20% buffer ratio
        vm.prank(admin);
        auth.setBufferRatio(2000); // 20%
        
        // With 20% ratio and 1000 total, we need 200 in buffer
        // So we can move at most 800 out
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 800 * WAD);
        
        // Now buffer has exactly 20% (200 out of 1000)
        // We shouldn't be able to move more to buffer (would exceed 20%)
        vm.expectRevert(abi.encodeWithSelector(IVault.BufferRatioExceeded.selector));
        vm.prank(keeper);
        vault.moveToBuffer(htpIndex, 50 * WAD);
        
        // We can't move more from buffer (would go below 20%)
        vm.expectRevert(abi.encodeWithSelector(IVault.BufferRatioExceeded.selector));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 * WAD);
    }

    function test_moveFromBuffer_respectsRatio() public {
        // Set 30% buffer ratio  
        vm.prank(admin);
        auth.setBufferRatio(3000); // 30%
        
        // Currently buffer has 100% of assets (1000)
        // With 30% ratio, we need at least 300 in buffer
        // So we can move at most 700 out
        
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        
        // Moving 700 should work
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 700 * WAD);
        
        // Trying to move more should fail (would leave buffer below 30%)
        vm.expectRevert(abi.encodeWithSelector(IVault.BufferRatioExceeded.selector));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 100 * WAD);
    }

    function test_moveFromBuffer_exactRatio() public {
        // Set 25% buffer ratio
        vm.prank(admin);
        auth.setBufferRatio(2500); // 25%
        
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        
        // Move exactly enough to reach 25% buffer (250 out of 1000)
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 750 * WAD);
        
        // Buffer should now have exactly 25%
        uint256 bufferValue = vault.BUFFER().lpToValue(vault.bufferLps());
        uint256 totalAssets = vault.totalAssets();
        uint256 bufferPercent = (bufferValue * 10000) / totalAssets;
        
        // Allow some rounding tolerance
        assertApproxEqAbs(bufferPercent, 2500, 10, "Buffer should be approximately 25%");
    }

    function test_bufferRatio_worksWithDeposits() public {
        // Set 20% buffer ratio
        vm.prank(admin);
        auth.setBufferRatio(2000); // 20%
        
        // Move assets to maintain 20% in buffer
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 800 * WAD);
        
        // New deposit should go to buffer
        uint256 bobDeposit = 500 * 10 ** vault.assetDecimals();
        deal(vault.asset(), bob, bobDeposit);
        vm.startPrank(bob);
        IERC20(vault.asset()).approve(address(vault), bobDeposit);
        vault.deposit(bobDeposit, bob);
        vm.stopPrank();
        
        // Now we have 1500 total, buffer has 700 (46.7%)
        // We should be able to move some from buffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 400 * WAD);
        
        // Buffer should now have 300 out of 1500 (20%)
    }

    function test_bufferRatio_canBeChanged() public {
        // Set initial ratio
        vm.prank(admin);
        auth.setBufferRatio(1000); // 10%
        
        // Move to achieve 10% buffer  
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 900 * WAD);
        
        // Buffer now has 100 WAD (10% of 1000)
        
        // Change ratio to 5% (lower)
        vm.prank(admin);
        auth.setBufferRatio(500); // 5%
        
        // Now we can move more from buffer (down to 5%)
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 * WAD);
        
        // Buffer now has 50 WAD (5% of 1000)
        
        // Change ratio to 15% (higher)
        vm.prank(admin);
        auth.setBufferRatio(1500); // 15%
        
        // Now we need 150 WAD in buffer (15% of 1000) but only have 50
        // We can't move from buffer (already below target)
        vm.expectRevert(abi.encodeWithSelector(IVault.BufferRatioExceeded.selector));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 10 * WAD);
        
        // Due to pool fees, totalAssets is now less than 1000
        // So 15% target is less than 150. Let's move a smaller amount
        vm.prank(keeper);
        vault.moveToBuffer(htpIndex, 95 * WAD);
        
        // Now buffer has 145 WAD, close to the ~149 WAD target
        // Trying to move more should fail as we approach the target
        vm.expectRevert(abi.encodeWithSelector(IVault.BufferRatioExceeded.selector));
        vm.prank(keeper);
        vault.moveToBuffer(htpIndex, 10 * WAD);
    }

    function test_bufferRatio_zeroAllowsAnyMovement() public {
        // First set a ratio
        vm.prank(admin);
        auth.setBufferRatio(5000); // 50%
        
        // Move to achieve 50% buffer
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 500 * WAD);
        
        // Now set ratio back to 0 (no restriction)
        vm.prank(admin);
        auth.setBufferRatio(0);
        
        // Should be able to move all from buffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 500 * WAD);
        assertEq(vault.bufferLps(), 0, "Buffer should be empty");
    }
}