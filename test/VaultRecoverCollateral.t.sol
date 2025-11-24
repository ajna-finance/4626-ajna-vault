// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.

pragma solidity ^0.8.18;
import "./Vault.base.t.sol";

contract VaultRecoverCollateralTest is VaultBaseTest {

    event RecoverCollateral(address indexed caller, uint256 indexed fromIndex, uint256 amt, uint256 colLps, uint256 value);
    event ReturnQuoteToken(address indexed caller, uint256 indexed toIndex, uint256 amt, uint256 lps);

    struct RecoveryParams {
        address gem;
        uint256 lps;
        uint256 price;
        uint256 bucketLP;
        uint256 gems;
    }

    function setUp() public override {
        super.setUp();
        deal(vault.asset(), alice, 1000 ether);
        vm.prank(alice);
        vault.deposit(1000 ether, alice);
    }

    // ============ HELPER FUNCTIONS ============

    function _setupRecoveryParams(uint256 bucketIndex, uint256 wadAssets) internal view returns (RecoveryParams memory) {
        RecoveryParams memory params;
        params.gem = pool.collateralAddress();
        params.lps = vault.lps(bucketIndex);
        (params.price,,,params.bucketLP,,) = info.bucketInfo(address(pool), bucketIndex);
        params.gems = (wadAssets * WAD) / params.price;
        return params;
    }

    function _mockAndRecoverSingle(uint256 bucketIndex, RecoveryParams memory params, address caller) internal {
        deal(params.gem, address(vault), params.gems);

        vm.startPrank(caller);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.removeCollateral.selector, params.gems, bucketIndex),
            abi.encode(params.gems, params.lps)
        );
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(info.bucketInfo.selector, address(pool), bucketIndex),
            abi.encode(params.price, 0, params.gems, params.bucketLP, 0, 0)
        );

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = bucketIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = params.gems;
        vault.recoverCollateral(indexes, amounts);
        vm.stopPrank();
    }

    function _mockAndRecoverTwo(
        uint256 bucket1,
        uint256 bucket2,
        RecoveryParams memory params1,
        RecoveryParams memory params2,
        address caller
    ) internal {
        deal(params1.gem, address(vault), params1.gems + params2.gems);

        vm.startPrank(caller);
        _setupMocksForBucket(bucket1, params1);
        _setupMocksForBucket(bucket2, params2);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = bucket1;
        indexes[1] = bucket2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = params1.gems;
        amounts[1] = params2.gems;
        vault.recoverCollateral(indexes, amounts);
        vm.stopPrank();
    }

    function _setupMocksForBucket(uint256 bucketIndex, RecoveryParams memory params) internal {
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.removeCollateral.selector, params.gems, bucketIndex),
            abi.encode(params.gems, params.lps)
        );
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(info.bucketInfo.selector, address(pool), bucketIndex),
            abi.encode(params.price, 0, params.gems, params.bucketLP, 0, 0)
        );
    }

    // ============ SINGLE BUCKET TESTS ============

    function test_recoverCollateral_singleBucket_admin() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        uint256 gemBalanceBefore = IERC20(pool.collateralAddress()).balanceOf(admin);
        RecoveryParams memory params = _setupRecoveryParams(htpIndex, wadAssets);

        _mockAndRecoverSingle(htpIndex, params, admin);

        assertEq(IERC20(params.gem).balanceOf(admin), gemBalanceBefore + params.gems, "Admin didn't receive gems");
        assertApproxEqAbs(vault.removedCollateralValue(), wadAssets, 1, "Removed collateral value incorrect");
        assertTrue(vault.paused(), "Vault should be paused");
    }

    function test_recoverCollateral_singleBucket_swapper() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        uint256 gemBalanceBefore = IERC20(pool.collateralAddress()).balanceOf(swapper);
        RecoveryParams memory params = _setupRecoveryParams(htpIndex, wadAssets);

        _mockAndRecoverSingle(htpIndex, params, swapper);

        assertEq(IERC20(params.gem).balanceOf(swapper), gemBalanceBefore + params.gems, "Swapper didn't receive gems");
        assertTrue(vault.paused(), "Vault should be paused");
    }

    // ============ MULTIPLE BUCKET TESTS ============

    function test_recoverCollateral_twoBuckets() public {
        uint256 wadAssets1 = 100 * WAD;
        uint256 wadAssets2 = 150 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 bucket2 = htpIndex + 100;

        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets1);
        vault.moveFromBuffer(bucket2, wadAssets2);
        vm.stopPrank();

        address gem = pool.collateralAddress();
        uint256 gemBalanceBefore = IERC20(gem).balanceOf(admin);

        RecoveryParams memory params1 = _setupRecoveryParams(htpIndex, wadAssets1);
        RecoveryParams memory params2 = _setupRecoveryParams(bucket2, wadAssets2);

        _mockAndRecoverTwo(htpIndex, bucket2, params1, params2, admin);

        assertGt(IERC20(gem).balanceOf(admin), gemBalanceBefore, "Admin should receive gems");
        assertGt(vault.removedCollateralValue(), 0, "Should have removed collateral value");
        assertTrue(vault.paused(), "Vault should be paused");
        assertLt(vault.lps(htpIndex), params1.lps, "Bucket 1 should have fewer LPs");
        assertLt(vault.lps(bucket2), params2.lps, "Bucket 2 should have fewer LPs");
    }

    // ============ END-TO-END RECOVERY AND RETURN TESTS ============

    function test_endToEnd_recoverAndReturn_singleBucket() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        RecoveryParams memory params = _setupRecoveryParams(htpIndex, wadAssets);
        _mockAndRecoverSingle(htpIndex, params, admin);

        assertTrue(vault.paused(), "Vault should be paused");
        assertGt(vault.removedCollateralValue(), 0, "Should have removed collateral value");

        // Step 2: Return quote token
        deal(vault.asset(), admin, wadAssets);

        vm.startPrank(admin);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vault.returnQuoteToken(htpIndex, wadAssets);
        vm.stopPrank();

        assertEq(vault.removedCollateralValue(), 0, "Removed collateral value should be reset");
        assertFalse(vault.paused(), "Vault should be unpaused");
    }

    function test_endToEnd_recoverAndReturn_multipleBuckets() public {
        pool.updateInterest();
        uint256 wadAssets1 = 100 * WAD;
        uint256 wadAssets2 = 150 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 bucket2 = htpIndex + 100;

        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets1);
        vault.moveFromBuffer(bucket2, wadAssets2);
        vm.stopPrank();

        RecoveryParams memory params1 = _setupRecoveryParams(htpIndex, wadAssets1);
        RecoveryParams memory params2 = _setupRecoveryParams(bucket2, wadAssets2);

        _mockAndRecoverTwo(htpIndex, bucket2, params1, params2, admin);

        assertTrue(vault.paused(), "Vault should be paused");
        uint256 removedValue = vault.removedCollateralValue();
        assertGt(removedValue, 0, "Should have removed collateral value");

        // Step 2: Return quote token
        deal(vault.asset(), admin, removedValue);

        vm.startPrank(admin);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vault.returnQuoteToken(htpIndex, removedValue);
        vm.stopPrank();

        assertEq(vault.removedCollateralValue(), 0, "Removed collateral value should be reset");
        assertFalse(vault.paused(), "Vault should be unpaused");
    }

    // ============ PAUSE BLOCKING TESTS ============

    function test_fail_recoverCollateral_whenPaused() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        vm.prank(admin);
        auth.pause();

        assertTrue(vault.paused(), "Vault should be paused");

        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(admin);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = htpIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;
        vault.recoverCollateral(indexes, amounts);
    }

    function test_recoverCollateral_whenPaused_byRemovedCollateral() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        uint256 bucket2 = htpIndex + 100;

        vm.startPrank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);
        vault.moveFromBuffer(bucket2, wadAssets);
        vm.stopPrank();

        RecoveryParams memory params = _setupRecoveryParams(htpIndex, wadAssets);
        _mockAndRecoverSingle(htpIndex, params, admin);

        assertTrue(vault.paused(), "Vault should be paused");
        uint256 removedValue = vault.removedCollateralValue();
        assertGt(removedValue, 0, "Should have removed collateral value");

        // Attempting another recovery should succeed because vault is only paused by removed collateral value
        RecoveryParams memory params2 = _setupRecoveryParams(bucket2, wadAssets);
        _mockAndRecoverSingle(bucket2, params2, admin);

        assertTrue(vault.paused(), "Vault should be paused");
        assertGt(vault.removedCollateralValue(), removedValue, "Should have added to removed more collateral value");
    }

    function test_recoverCollateral_canResumeAfterUnpause() public {
        uint256 wadAssets = 100 * WAD;
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        vm.prank(admin);
        auth.pause();

        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(admin);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = htpIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;
        vault.recoverCollateral(indexes, amounts);

        vm.prank(admin);
        auth.unpause();

        assertFalse(vault.paused(), "Vault should be unpaused");

        RecoveryParams memory params = _setupRecoveryParams(htpIndex, wadAssets);
        _mockAndRecoverSingle(htpIndex, params, admin);

        assertTrue(vault.paused(), "Vault should be paused after recovery");
    }

    // ============ EDGE CASE TESTS ============

    function test_recoverCollateral_emptyArray() public {
        uint256 removedValueBefore = vault.removedCollateralValue();

        vm.prank(admin);
        uint256[] memory indexes = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        vault.recoverCollateral(indexes, amounts);

        assertEq(vault.removedCollateralValue(), removedValueBefore, "Removed collateral value should not change");
        assertFalse(vault.paused(), "Vault should not be paused");
    }
}
