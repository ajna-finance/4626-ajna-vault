// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.


pragma solidity ^0.8.18;
import "./Vault.base.t.sol";

contract VaultAjnaTest is VaultBaseTest {

    function test_bufferTotalIsCorrect(uint256 wadAssets) public {
        vm.assume(wadAssets > vault.LP_DUST() && wadAssets <= 100 * 1_000_000_000_000 * WAD); // 100 trillion WAD max for buffer
        deal(vault.asset(), alice, wadAssets);
        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        assertEq(Buffer(vault.buffer()).total(), wadAssets, "Buffer total didn't match");

        assertEq(Buffer(vault.buffer()).total(), Buffer(vault.buffer()).lpToValue(vault.bufferLps()), "Buffer total didn't match");
    }

    function test_moveFromBuffer() public onlyLiveFork {
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        uint256 wadAssets = 100 * WAD;

        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        uint256 beforeBufferBalance = IERC20(vault.asset()).balanceOf(vault.buffer());
        uint256 beforePoolBalance = IERC20(vault.asset()).balanceOf(address(pool));
        uint256 beforeTotalAssets = vault.totalAssets();

        uint256 ajnaFee = wmul(wadAssets, info.depositFeeRate(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        assertEq(vault.totalAssets(), wadAssets - ajnaFee, "Total assets didn't decrease by fee");

        uint256 afterBufferBalance = IERC20(vault.asset()).balanceOf(vault.buffer());
        uint256 afterPoolBalance = IERC20(vault.asset()).balanceOf(address(pool));

        assertEq(afterBufferBalance, beforeBufferBalance - assets, "Buffer balance didn't decrease");
        assertEq(afterPoolBalance, beforePoolBalance + assets, "Pool balance didn't increase");
        assertEq(vault.bufferLps(), 0, "Buffer lps didn't reset");
        assertGt(vault.lps(htpIndex), 0, "Pool lps didn't increase");
        assertLt(vault.totalAssets(), beforeTotalAssets, "Total assets didn't decrease - should due to fee");
    }

    function test_moveFromBufferEarns() public onlyLiveFork {
        uint256 wadAssets = 100 * WAD;

        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        uint256 aliceValueAfterMove = vault.convertToAssets(vault.balanceOf(alice));
        assertLt(aliceValueAfterMove, wadAssets, "Alice's value didn't decrease due to fee");

        vm.warp(block.timestamp + 12 hours);

        pool.updateInterest();

        uint256 aliceValueAfterInterest = vault.convertToAssets(vault.balanceOf(alice));
        assertGt(aliceValueAfterInterest, aliceValueAfterMove, "Alice's value didn't increase due to interest");
    }

    function test_multipleDepositEarners() public onlyLiveFork {
        uint256 wadAssets = 100 * WAD;
        uint256 warpTime = 16 hours;

        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceValueBeforeMove = vault.convertToAssets(aliceShares);
        uint256 expectedAliceFee = wmul(wadAssets, info.depositFeeRate(address(pool)));

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        // Move 90% of the new deposit from the buffer to the pool
        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, Buffer(vault.buffer()).total());
        vm.stopPrank();

        uint256 aliceValueAfterMove = vault.convertToAssets(aliceShares);
        assertEq(aliceValueAfterMove, aliceValueBeforeMove - expectedAliceFee, "Alice's value didn't decrease by fee");

        vm.warp(block.timestamp + warpTime);
        pool.updateInterest();

        uint256 aliceValueAfterInterest = vault.convertToAssets(aliceShares);
        assertGt(aliceValueAfterInterest, aliceValueAfterMove, "Alice's value didn't increase due to interest");

        vm.prank(bob);
        vault.deposit(wadAssets, bob);

        uint256 bobValueBeforeMove = vault.convertToAssets(vault.balanceOf(bob));
        pool.updateInterest();
        uint256 expectedBobFee = wmul(wadAssets, info.depositFeeRate(address(pool)));

        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, Buffer(vault.buffer()).total());
        vm.stopPrank();

        uint256 bobValueAfterMove = vault.convertToAssets(vault.balanceOf(bob));
        uint256 aliceValueAfterBobMove = vault.convertToAssets(aliceShares);
        {
            uint256 bobsShareOfFee = (expectedBobFee * vault.balanceOf(bob)) / vault.totalSupply();
            assertEq(bobValueAfterMove, bobValueBeforeMove - bobsShareOfFee, "Bob's value didn't decrease by share of Bob's move fee");
            uint256 alicesShareOfFee = (expectedBobFee * vault.balanceOf(alice)) / vault.totalSupply();
            assertEq(aliceValueAfterBobMove, aliceValueAfterInterest - alicesShareOfFee, "Alice's value didn't decrease by share of Bob's move fee");
        }
        uint256 totalAssetsBeforeInterest = vault.totalAssets();
        
        vm.warp(block.timestamp + warpTime);
        pool.updateInterest();

        {
            assertGt(vault.totalAssets(), totalAssetsBeforeInterest, "Total assets didn't increase with interest");
            uint256 earnedInterest = vault.totalAssets() - totalAssetsBeforeInterest;
            
            assertGt(vault.convertToAssets(vault.balanceOf(bob)), bobValueAfterMove, "Bob's value didn't increase due to interest");
            assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(bob)) - bobValueAfterMove, ((earnedInterest * vault.balanceOf(bob)) / vault.totalSupply()), 1, "Bob's earned interest didn't match his share of the total earned interest");

            assertGt(vault.convertToAssets(aliceShares), aliceValueAfterMove, "Alice's value didn't increase due to interest");
            assertEq((vault.convertToAssets(aliceShares) - aliceValueAfterBobMove), ((earnedInterest * vault.balanceOf(alice)) / vault.totalSupply()), "Alice's earned interest didn't match her share of the total earned interest");
        }
    }

    function test_moveToBuffer() public onlyLiveFork {
        uint256 wadAssets = 100 * WAD;
        uint256 warpTime = 14 days;
        
        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        // Move 90% of the deposit from the pool to the buffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, _calculatePoolTarget(wadAssets));

        vm.warp(block.timestamp + warpTime);
        pool.updateInterest();

        // Over time the Pool earns interest, so need to refill the buffer to keep
        // 90% in pool and 10% in buffer
        uint256 targetForBuffer = _calculateBufferTarget(vault.totalAssets());
        uint256 amountToMove = targetForBuffer - Buffer(vault.buffer()).total();
        console.log("amountToMove                  ", amountToMove);
        console.log("targetForBuffer               ", targetForBuffer);
        console.log("Buffer(vault.buffer()).total()", Buffer(vault.buffer()).total());
        console.log("vault.totalAssets()           ", vault.totalAssets());
        console.log("wadAssets                     ", wadAssets);

        vm.prank(keeper);
        vault.moveToBuffer(htpIndex, amountToMove);

        assertEq(Buffer(vault.buffer()).total(), targetForBuffer, "Buffer total didn't increase to target");
    }

    function test_moveBetweenBucketsNoFee() public onlyLiveFork {
        uint256 wadAssets = 100 * WAD;
        uint256 warpTime = 14 days;

        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 lupIndex = info.priceToIndex(info.lup(address(pool)));

        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, _calculatePoolTarget(wadAssets));
        vm.stopPrank();

        vm.warp(block.timestamp + warpTime);
        pool.updateInterest();

        uint256 amtToMove = _calculatePoolTarget(vault.totalAssets()) / 2;
        uint256 totalAssetsBeforeMove = vault.totalAssets();
        uint256 htpBucketBeforeMove = vault.lpToValue(htpIndex);

        vm.prank(keeper);
        vault.move(htpIndex, lupIndex, amtToMove);
        // No move fee since we're moving to a lower bucket (HTP -> LUP)
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBeforeMove, 1, "Total assets didn't stay the same");

        assertEq(vault.lpToValue(htpIndex), htpBucketBeforeMove - amtToMove, "Should still have some in htp bucket");
        assertGt(vault.lps(lupIndex), 0, "LUP Bucket should have lps");
        assertApproxEqAbs(vault.lpToValue(lupIndex), amtToMove, 1, "LUP Bucket should have amount moved");

        // buckets can be consolidated
        vm.startPrank(keeper);
        vault.move(htpIndex, lupIndex, vault.lpToValue(htpIndex));
        vm.stopPrank();
        assertEq(vault.lpToValue(htpIndex), 0, "Htp bucket should be empty");
        assertGt(vault.lps(lupIndex), 0, "LUP Bucket should have lps");
        assertEq(vault.lpToValue(lupIndex), vault.totalAssets() - buffer.total(), "LUP Bucket should have non-buffer amount");
    }

    function test_moveBetweenBucketsWithFee() public onlyLiveFork {
        uint256 wadAssets = 100 * WAD;
        uint256 warpTime = 14 days;

        vm.prank(alice);
        vault.deposit(wadAssets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 lupIndex = info.priceToIndex(info.lup(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(lupIndex, _calculatePoolTarget(wadAssets));

        vm.warp(block.timestamp + warpTime);
        pool.updateInterest();

        uint256 amtToMove = _calculatePoolTarget(vault.totalAssets()) / 2;
        uint256 totalAssetsBeforeMove = vault.totalAssets();
        uint256 htpBucketBeforeMove = vault.lpToValue(lupIndex);

        uint256 moveFee = wmul(amtToMove, info.depositFeeRate(address(pool)));

        vm.prank(keeper);
        vault.move(lupIndex, htpIndex, amtToMove);
        // Moving from LUP -> HTP moves up so there is a fee
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBeforeMove - moveFee, 1, "Total assets didn't decrease by move fee");

        assertApproxEqAbs(vault.lpToValue(lupIndex), htpBucketBeforeMove - amtToMove, 1, "Should still have some in lup bucket");
        assertGt(vault.lps(htpIndex), 0, "HTP Bucket should have lps");
        assertApproxEqAbs(vault.lpToValue(htpIndex), amtToMove - moveFee, 1, "HTP Bucket should have amount moved");

        // buckets can be consolidated
        vm.startPrank(keeper);
        vault.move(lupIndex, htpIndex, vault.lpToValue(lupIndex));
        vm.stopPrank();
        assertEq(vault.lpToValue(lupIndex), 0, "LUP bucket should be empty");
        assertGt(vault.lps(htpIndex), 0, "HTP Bucket should have lps");
        assertEq(vault.lpToValue(htpIndex), vault.totalAssets() - buffer.total(), "HTP Bucket should have non-buffer amount");
    }

    function test_fail_moveFromBuffer_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(keeper);
        vault.moveFromBuffer(0, 0);
    }

    function test_fail_moveToBuffer_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(keeper);
        vault.moveToBuffer(0, 0);
    }

    function test_fail_move_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(keeper);
        vault.move(0, 0, 0);
    }

    // KEEPER PERMISSION TESTS
    function test_keeper_canCallMove() public {
        // Setup: deposit funds and move to bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // First setup some funds in a bucket
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Keeper should be able to call move
        vm.prank(keeper);
        vault.move(htpIndex, htpIndex + 100, 10 ether);
        
        // Verify the move worked
        assertTrue(vault.lps(htpIndex + 100) > 0, "Move should have created LPs in destination bucket");
    }

    function test_admin_canCallMove() public {
        // Setup: deposit funds and move to bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Admin should be able to call move
        vm.prank(admin);
        vault.move(htpIndex, htpIndex + 100, 10 ether);
        
        // Verify the move worked
        assertTrue(vault.lps(htpIndex + 100) > 0, "Admin move should have worked");
    }

    function test_keeper_canCallMoveFromBuffer() public {
        // Setup: deposit funds 
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Keeper should be able to call moveFromBuffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Verify the move worked
        assertTrue(vault.lps(htpIndex) > 0, "MoveFromBuffer should have created LPs in bucket");
        assertTrue(vault.bufferLps() < 100 ether, "Buffer LPs should have decreased");
    }

    function test_keeper_canCallMoveToBuffer_shouldWork() public {
        // Setup: deposit funds and create bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Only admin/keeper should be able to call moveToBuffer
        vm.prank(keeper);
        vault.moveToBuffer(htpIndex, 10 ether);
        
        // Verify the move worked
        assertTrue(vault.bufferLps() > 0, "MoveToBuffer should have increased buffer LPs");
    }

    function test_fail_nonKeeper_cannotCallMove() public {
        // Setup: deposit funds and move to bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Non-keeper, non-admin should not be able to call move
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(bob);
        vault.move(htpIndex, htpIndex + 100, 10 ether);
    }

    function test_fail_nonKeeper_cannotCallMoveFromBuffer() public {
        // Setup: deposit funds
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Non-keeper should not be able to call moveFromBuffer
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(bob);
        vault.moveFromBuffer(htpIndex, 50 ether);
    }

    function test_fail_admin_cannotCallMoveFromBuffer() public {
        // Setup: deposit funds
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Admin should not be able to call moveFromBuffer (only keepers)
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(admin);
        vault.moveFromBuffer(htpIndex, 50 ether);
    }

    function test_removedKeeper_cannotCallMove() public {
        // Setup: deposit funds 
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Setup initial bucket
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        // Verify bob can call move
        vm.prank(keeper);
        vault.move(htpIndex, htpIndex + 100, 5 ether);
        
        // Remove keeper
        vm.prank(admin);
        auth.setKeeper(keeper, false);
        
        // Keeper should no longer be able to call move
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(keeper);
        vault.move(htpIndex, htpIndex + 200, 5 ether);
    }

    function test_removedKeeper_cannotCallMoveFromBuffer() public {
        // Setup: deposit funds
        vm.prank(alice);
        vault.deposit(100 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Verify bob can call moveFromBuffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 20 ether);
        
        // Remove keeper
        vm.prank(admin);
        auth.setKeeper(keeper, false);
        
        // Keeper should no longer be able to call moveFromBuffer
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex + 100, 20 ether);
    }

    function test_multipleKeepers_canAllCallFunctions() public {
        // Setup: deposit funds 
        vm.prank(alice);
        vault.deposit(200 ether, alice);
        
        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;
        
        // Add multiple keepers
        vm.startPrank(admin);
        auth.setKeeper(keeper, true);
        auth.setKeeper(bob, true);
        vm.stopPrank();
        
        // Both keepers should be able to call moveFromBuffer
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);
        
        vm.prank(bob);
        vault.moveFromBuffer(htpIndex + 100, 50 ether);
        
        // Both keepers should be able to call move
        vm.prank(keeper);
        vault.move(htpIndex, htpIndex + 200, 10 ether);
        
        vm.prank(bob);
        vault.move(htpIndex + 100, htpIndex + 300, 10 ether);
        
        // Verify all operations worked
        assertTrue(vault.lps(htpIndex) > 0, "Keeper's moveFromBuffer should have worked");
        assertTrue(vault.lps(htpIndex + 100) > 0, "Bob's moveFromBuffer should have worked");
        assertTrue(vault.lps(htpIndex + 200) > 0, "Keeper's move should have worked");
        assertTrue(vault.lps(htpIndex + 300) > 0, "Bob's move should have worked");
    }

    function test_fail_nonAuthUser_cannotCallMoveToBuffer() public {
        // Setup: deposit funds and create bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);

        // Non-admin, non-keeper (bob) should not be able to call moveToBuffer
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(bob);
        vault.moveToBuffer(htpIndex, 10 ether);
    }

    function test_admin_canCallMoveToBuffer() public {
        // Setup: deposit funds and create bucket
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        uint256 htpIndex = liveFork ? info.priceToIndex(info.htp(address(pool))) : 2550;

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, 50 ether);

        // Admin should be able to call moveToBuffer
        vm.prank(admin);
        vault.moveToBuffer(htpIndex, 10 ether);

        // Verify the move worked
        assertTrue(vault.bufferLps() > 0, "Admin moveToBuffer should have increased buffer LPs");
    }
}
