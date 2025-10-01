// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;
import "./Vault.base.t.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract Vault4626Test is VaultBaseTest {

    function test_constructor() public view {
        assertEq(address(vault.pool()), address(pool), "Pool not set");
        assertEq(address(vault.info()), address(info), "Info not set");
        assertEq(address(pool.quoteTokenAddress()), address(vault.asset()), "Quote token not set");
        assertTrue(address(vault.buffer()) != address(0), "Buffer not set");

        assertEq(ERC20(vault).decimals(), 18, "Decimals not set");
        assertEq(ERC20(vault).name(), "Vault", "Name not set");
        assertEq(ERC20(vault).symbol(), "VAULT", "Symbol not set");
        assertEq(IERC20(vault).totalSupply(), 0, "Total supply not set");
        
        assertEq(IERC20(vault.asset()).allowance(address(vault), address(pool)), type(uint256).max, "Pool allowance not set");
        assertEq(IERC20(vault.asset()).allowance(address(vault), address(buffer)), type(uint256).max, "Buffer allowance not set");
    }

    function test_deposit() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        
        uint256 aliceShares = vault.previewDeposit(assets);
        
        uint256 aliceAssetBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobAssetBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        
        vm.prank(alice);
        vault.deposit(assets, alice);
        assertEq(vault.balanceOf(alice), aliceShares, "Alice didn't receive shares");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceAssetBalanceBefore - assets, "Alice didn't send assets");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), assets, "Buffer didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should have assets");

        uint256 bobShares = vault.previewDeposit(assets);
        
        vm.prank(bob);
        vault.deposit(assets, bob);
        assertEq(vault.balanceOf(bob), bobShares, "Bob didn't receive shares");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobAssetBalanceBefore - assets, "Bob didn't send assets");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), assets + assets, "Buffer didn't receive Bob's assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should have assets");

        vm.prank(alice);
        vault.deposit(assets / 2, alice);

        console.log("Alice shares", vault.balanceOf(alice));
        console.log("Bob shares", vault.balanceOf(bob));
        console.log("Alice Value", vault.convertToAssets(vault.balanceOf(alice)));
        console.log("Bob Value", vault.convertToAssets(vault.balanceOf(bob)));

        vm.prank(bob);
        vault.deposit(assets / 2, bob);

        console.log("Alice shares", vault.balanceOf(alice));
        console.log("Bob shares", vault.balanceOf(bob));
        console.log("Alice Value", vault.convertToAssets(vault.balanceOf(alice)));
        console.log("Bob Value", vault.convertToAssets(vault.balanceOf(bob)));

        console.log("vault.totalAssets()", vault.totalAssets());
        console.log("vault.totalSupply()", vault.totalSupply());
        console.log("vault.balanceOf(alice)", vault.balanceOf(alice));
        console.log("vault.balanceOf(bob)", vault.balanceOf(bob));
        console.log("Buffer(vault.buffer()).total()", Buffer(vault.buffer()).total());
        console.log("vault.asset().balanceOf(vault.buffer())", IERC20(vault.asset()).balanceOf(vault.buffer()));
        console.log("vault.asset().balanceOf(address(vault))", IERC20(vault.asset()).balanceOf(address(vault)));
    }

    function test_mint() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();

        uint256 aliceShares = vault.convertToShares(assets);
        uint256 aliceAssetsRequired = vault.previewMint(aliceShares);

        uint256 aliceAssetBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobAssetBalanceBefore = IERC20(vault.asset()).balanceOf(bob);

        vm.prank(alice);
        vault.mint(aliceShares, alice);
        assertEq(vault.balanceOf(alice), aliceShares, "Alice didn't receive shares");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceAssetBalanceBefore - aliceAssetsRequired, "Alice didn't send assets");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), aliceAssetsRequired, "Buffer didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should have assets");

        uint256 bobShares = vault.convertToShares(assets);
        uint256 bobAssetsRequired = vault.previewMint(bobShares);

        vm.prank(bob);
        vault.mint(bobShares, bob);
        assertEq(vault.balanceOf(bob), bobShares, "Bob didn't receive shares");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobAssetBalanceBefore - bobAssetsRequired, "Bob didn't send assets");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), aliceAssetsRequired + bobAssetsRequired, "Buffer didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should have assets");

        console.log("vault.totalAssets()", vault.totalAssets());
        console.log("vault.totalSupply()", vault.totalSupply());
        console.log("vault.balanceOf(alice)", vault.balanceOf(alice));
        console.log("vault.balanceOf(bob)", vault.balanceOf(bob));
        console.log("Buffer(vault.buffer()).total()", Buffer(vault.buffer()).total());
        console.log("vault.asset().balanceOf(vault.buffer())", IERC20(vault.asset()).balanceOf(vault.buffer()));
        console.log("vault.asset().balanceOf(address(vault))", IERC20(vault.asset()).balanceOf(address(vault)));
    }

    function test_withdraw() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();

        uint256 aliceOriginalBalance = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobOriginalBalance = IERC20(vault.asset()).balanceOf(bob);
        
        vm.prank(alice);
        vault.deposit(assets, alice);
        vm.prank(bob);
        vault.deposit(assets, bob);

        uint256 aliceMaxWithdraw = vault.maxWithdraw(alice);
        uint256 bobMaxWithdraw = vault.maxWithdraw(bob);

        uint256 aliceAssetBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobAssetBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        uint256 bufferAssetBalanceBefore = IERC20(vault.asset()).balanceOf(vault.buffer());

        vm.prank(alice);
        vault.withdraw(aliceMaxWithdraw, alice, alice);
        assertEq(vault.balanceOf(alice), 0, "Alice didn't withdraw shares");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceAssetBalanceBefore + aliceMaxWithdraw, "Alice didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceOriginalBalance, "Alice's balance didn't return to original");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), bufferAssetBalanceBefore - aliceMaxWithdraw, "Buffer should have sent assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should never have assets");

        uint256 bobMaxWithdrawAfter = vault.maxWithdraw(bob);
        assertEq(bobMaxWithdrawAfter, bobMaxWithdraw, "Bob's max withdraw should remain the same after Alice withdraws");

        vm.prank(bob);
        vault.withdraw(bobMaxWithdrawAfter, bob, bob);
        assertEq(vault.balanceOf(bob), 0, "Bob didn't withdraw shares");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobAssetBalanceBefore + bobMaxWithdrawAfter, "Bob didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobOriginalBalance, "Bob's balance didn't return to original");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), 0, "Buffer should have sent remaining assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should never have assets");

        console.log("vault.totalAssets()", vault.totalAssets());
        console.log("vault.totalSupply()", vault.totalSupply());
        console.log("vault.balanceOf(alice)", vault.balanceOf(alice));
        console.log("vault.balanceOf(bob)", vault.balanceOf(bob));
        console.log("vault.asset().balanceOf(vault.buffer())", IERC20(vault.asset()).balanceOf(vault.buffer()));
        console.log("vault.asset().balanceOf(address(vault))", IERC20(vault.asset()).balanceOf(address(vault)));
    }

    function test_redeem() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();

        uint256 aliceOriginalBalance = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobOriginalBalance = IERC20(vault.asset()).balanceOf(bob);
        
        vm.prank(alice);
        vault.deposit(assets, alice);
        vm.prank(bob);
        vault.deposit(assets, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        uint256 aliceAssetsFromRedeem = vault.previewRedeem(aliceShares);
        uint256 bobAssetsFromRedeem = vault.previewRedeem(bobShares);

        uint256 aliceAssetBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobAssetBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        uint256 bufferAssetBalanceBefore = IERC20(vault.asset()).balanceOf(vault.buffer());
        
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertEq(vault.balanceOf(alice), 0, "Alice didn't redeem shares");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceAssetBalanceBefore + aliceAssetsFromRedeem, "Alice didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(alice), aliceOriginalBalance, "Alice's balance didn't return to original");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), bufferAssetBalanceBefore - aliceAssetsFromRedeem, "Buffer should have sent assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should never have assets");

        uint256 bobAssetsFromRedeemAfter = vault.previewRedeem(bobShares);
        assertEq(bobAssetsFromRedeemAfter, bobAssetsFromRedeem, "Bob's assets should match preview after Alice redeems");

        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);
        assertEq(vault.balanceOf(bob), 0, "Bob didn't redeem shares");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobAssetBalanceBefore + bobAssetsFromRedeemAfter, "Bob didn't receive assets");
        assertEq(IERC20(vault.asset()).balanceOf(bob), bobOriginalBalance, "Bob's balance didn't return to original");
        assertEq(IERC20(vault.asset()).balanceOf(vault.buffer()), 0, "Buffer should have sent remaining assets");
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), 0, "Vault should never have assets");

        console.log("vault.totalAssets()", vault.totalAssets());
        console.log("vault.totalSupply()", vault.totalSupply());
        console.log("vault.balanceOf(alice)", vault.balanceOf(alice));
        console.log("vault.balanceOf(bob)", vault.balanceOf(bob));
        console.log("Buffer(vault.buffer()).total()", Buffer(vault.buffer()).total());
        console.log("vault.asset().balanceOf(vault.buffer())", IERC20(vault.asset()).balanceOf(vault.buffer()));
        console.log("vault.asset().balanceOf(address(vault))", IERC20(vault.asset()).balanceOf(address(vault)));
    }

    function test_fail_deposit_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(alice);
        vault.deposit(100 * WAD, alice);
    }

    function test_fail_mint_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(alice);
        vault.mint(100 * WAD, alice);
    }

    function test_fail_withdraw_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(alice);
        vault.withdraw(100 * WAD, alice, alice);
    }

    function test_fail_redeem_paused() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(alice);
        vault.redeem(100 * WAD, alice, alice);
    }

    function test_recoverCollateralAdmin() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        uint256 wadAssets = 100 * WAD;

        vm.prank(alice);
        vault.deposit(assets, alice);
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        address gem = pool.collateralAddress();
        uint256 gemBalanceBefore = IERC20(gem).balanceOf(admin);
        uint256 lpsToRecover = vault.lps(htpIndex);
        uint256 totalAssetsBefore = vault.totalAssets();
        (
            uint256 price,
            /* quoteToken */,
            /* collateral */,
            uint256 bucketLP,
            /* scale */,
            /* exchangeRate */
        ) = info.bucketInfo(address(pool), htpIndex);

        // Recovers the whole bucket
        uint256 gemsToRecover = (totalAssetsBefore * WAD) / price;

        // Pretend like the pool had collateral to remove and it sent it to the vault
        deal(gem, address(vault), gemsToRecover);
        vm.startPrank(admin);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.removeCollateral.selector, gemsToRecover, htpIndex),
            abi.encode(gemsToRecover, lpsToRecover)
        );
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(info.bucketInfo.selector, address(pool), htpIndex),
            abi.encode(price, 0, gemsToRecover, bucketLP, 0, 0)
        );
        vault.recoverCollateral(htpIndex, gemsToRecover);
        vm.stopPrank();

        assertEq(IERC20(gem).balanceOf(admin), gemBalanceBefore + gemsToRecover, "Admin didn't receive assets");
        assertEq(IERC20(gem).balanceOf(address(vault)), 0, "Vault should have no assets");
        console.log("totalAssetsAfter     ", vault.totalAssets());
        console.log("price                ", price);
        console.log("gemsToRecover        ", gemsToRecover);
        console.log("totalAssetsBefore    ", totalAssetsBefore);
        console.log("gemsToRecover * price", gemsToRecover);
        console.log("removedCollateralValue", vault.removedCollateralValue());
        assertApproxEqAbs(vault.removedCollateralValue(), totalAssetsBefore, 1, "Vault should store the removed collateral value");
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 1, "Vault should store the removed collateral value and put it in totalAssets, leaving the value the same");

        // Vault should be paused
        assertGt(vault.removedCollateralValue(), 0, "Vault should be paused");
    }

    function test_returnQuoteTokenAdmin() public {
        uint256 wadAssets = 100 * WAD;

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        uint256 totalAssetsBefore = vault.totalAssets();
        deal(vault.asset(), address(admin), wadAssets);
        uint256 adminAssetBalanceBefore = IERC20(vault.asset()).balanceOf(admin);
        assertEq(vault.balanceOf(admin), 0, "Admin should have no shares before");
        uint256 depositFee = wmul(wadAssets, info.depositFeeRate(address(pool)));

        // Vault will be paused when the admin recovers collateral
        vm.prank(admin);
        auth.pause();

        vm.startPrank(admin);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vault.returnQuoteToken(htpIndex, wadAssets);
        vm.stopPrank();

        console.log("totalAssetsAfter     ", vault.totalAssets());
        console.log("totalAssetsBefore    ", totalAssetsBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore + wadAssets - depositFee, "Vault should have more assets");
        assertEq(IERC20(vault.asset()).balanceOf(admin), adminAssetBalanceBefore - wadAssets, "Admin should have less assets");
        assertEq(vault.balanceOf(admin), 0, "Admin should have no shares");

        // Vault should be unpaused
        assertEq(vault.removedCollateralValue(), 0, "Vault should be unpaused");
        assertEq(vault.removedCollateralValue(), 0, "Vault should have no removed collateral value");
    }

    function test_recoverCollateralSwapper() public {
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        uint256 wadAssets = 100 * WAD;

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        address gem = pool.collateralAddress();
        uint256 gemBalanceBefore = IERC20(gem).balanceOf(swapper);
        uint256 lpsToRecover = vault.lps(htpIndex);
        uint256 totalAssetsBefore = vault.totalAssets();
        (
            uint256 price,
            /* quoteToken */,
            /* collateral */,
            uint256 bucketLP,
            /* scale */,
            /* exchangeRate */
        ) = info.bucketInfo(address(pool), htpIndex);

        // Recovers the whole bucket
        uint256 gemsToRecover = (totalAssetsBefore * WAD) / price;

        // Pretend like the pool has collateral to remove and it sends it to the vault
        deal(gem, address(vault), gemsToRecover);
        vm.startPrank(swapper);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.removeCollateral.selector, gemsToRecover, htpIndex),
            abi.encode(gemsToRecover, lpsToRecover)
        );
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(info.bucketInfo.selector, address(pool), htpIndex),
            abi.encode(price, 0, gemsToRecover, bucketLP, 0, 0)
        );
        vault.recoverCollateral(htpIndex, gemsToRecover);
        vm.stopPrank();

        assertEq(IERC20(gem).balanceOf(swapper), gemBalanceBefore + gemsToRecover, "Swapper didn't receive assets");
        assertEq(IERC20(gem).balanceOf(address(vault)), 0, "Vault should have no assets");
        console.log("totalAssetsAfter     ", vault.totalAssets());
        console.log("price                ", price);
        console.log("gemsToRecover        ", gemsToRecover);
        console.log("totalAssetsBefore    ", totalAssetsBefore);
        console.log("gemsToRecover * price", gemsToRecover);
        console.log("removedCollateralValue", vault.removedCollateralValue());
        assertApproxEqAbs(vault.removedCollateralValue(), totalAssetsBefore, 1, "Vault should store the removed collateral value");
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 1, "Vault should store the removed collateral value");

        // Vault should be paused
        assertGt(vault.removedCollateralValue(), 0, "Vault should be paused");
    }

    function test_returnQuoteTokenSwapper() public {
        uint256 wadAssets = 100 * WAD;

        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));

        uint256 totalAssetsBefore = vault.totalAssets();
        deal(vault.asset(), address(swapper), wadAssets);
        uint256 swapperAssetBalanceBefore = IERC20(vault.asset()).balanceOf(swapper);
        assertEq(vault.balanceOf(swapper), 0, "Swapper should have no shares before");
        uint256 depositFee = wmul(wadAssets, info.depositFeeRate(address(pool)));

        // Vault will be paused when the admin recovers collateral
        vm.prank(admin);
        auth.pause();

        vm.startPrank(swapper);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vault.returnQuoteToken(htpIndex, wadAssets);
        vm.stopPrank();

        console.log("totalAssetsAfter     ", vault.totalAssets());
        console.log("totalAssetsBefore    ", totalAssetsBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore + wadAssets - depositFee, "Vault should have more assets");
        assertEq(IERC20(vault.asset()).balanceOf(swapper), swapperAssetBalanceBefore - wadAssets, "Swapper should have less assets");
        assertEq(vault.balanceOf(swapper), 0, "Swapper should have no shares");

        // Vault should be unpaused
        assertEq(vault.removedCollateralValue(), 0, "Vault should be unpaused");
        assertEq(vault.removedCollateralValue(), 0, "Vault should have no removed collateral value");
    }

    function test_failRecoverCollateralNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(alice);
        vault.recoverCollateral(0, 0);
    }

    function test_failReturnQuoteTokenNotAdmin() public {
        vm.prank(admin);
        auth.pause();
        vm.expectRevert(abi.encodeWithSelector(IVault.NotAuthorized.selector));
        vm.prank(alice);
        vault.returnQuoteToken(0, 0);
    }

    function test_maxDeposit_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.maxDeposit(alice), 0, "Vault should have no max deposit");
    }

    function test_maxMint_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.maxMint(alice), 0, "Vault should have no max mint");
    }

    function test_maxWithdraw_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.maxWithdraw(alice), 0, "Vault should have no max withdraw");
    }
    
    function test_maxRedeem_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.maxRedeem(alice), 0, "Vault should have no max redeem");
    }

    function test_previewDeposit_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.previewDeposit(100 * WAD), 0, "Vault should have no preview deposit");
    }

    function test_previewMint_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.previewMint(100 * WAD), 0, "Vault should have no preview mint");
    }

    function test_previewWithdraw_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.previewWithdraw(100 * WAD), 0, "Vault should have no preview withdraw");
    }

    function test_previewRedeem_paused() public {
        vm.prank(admin);
        auth.pause();
        assertEq(vault.previewRedeem(100 * WAD), 0, "Vault should have no preview redeem");
    }

    function test_recoverCollateral_6DecimalToken() public {
        // Only run when not connected to ETH RPC (using mocks)
        if (liveFork) {
            console.log("Skipping 6-decimal test - Live fork is enabled");
            return;
        }

        // Deploy a mock 6-decimal token to use as collateral
        MockERC20 sixDecimalToken = new MockERC20("USDC", "USDC", 6);
        
        // Mock the pool to return our 6-decimal token as collateral
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.collateralAddress.selector),
            abi.encode(address(sixDecimalToken))
        );

        uint256 assets = 100 * 10 ** vault.assetDecimals();
        uint256 wadAssets = 100 * WAD;

        vm.prank(alice);
        vault.deposit(assets, alice);
        uint256 htpIndex = info.priceToIndex(info.htp(address(pool)));
        vm.prank(keeper);
        vault.moveFromBuffer(htpIndex, wadAssets);

        address gem = pool.collateralAddress();
        uint256 gemBalanceBefore = IERC20(gem).balanceOf(admin);
        uint256 lpsToRecover = vault.lps(htpIndex);
        uint256 totalAssetsBefore = vault.totalAssets();
        (
            uint256 price,
            /* quoteToken */,
            /* collateral */,
            uint256 bucketLP,
            /* scale */,
            /* exchangeRate */
        ) = info.bucketInfo(address(pool), htpIndex);

        // Calculate gems to recover in 6 decimals
        // totalAssetsBefore and price are both in WAD (18 decimals)
        // We want the result in 6 decimals for USDC
        uint256 gemsToRecover = (totalAssetsBefore * 10**6) / price;
        uint256 collateralWad = (totalAssetsBefore * WAD) / price;

        console.log("gemsToRecover", gemsToRecover);
        console.log("collateralWad", collateralWad);

        // Give the vault the 6-decimal collateral tokens
        deal(address(sixDecimalToken), address(vault), gemsToRecover);
        
        vm.startPrank(admin);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(pool.removeCollateral.selector, collateralWad, htpIndex),
            abi.encode(collateralWad, lpsToRecover)
        );
        vm.mockCall(
            address(info),
            abi.encodeWithSelector(info.bucketInfo.selector, address(pool), htpIndex),
            abi.encode(price, 0, collateralWad, bucketLP, 0, 0)
        );
        vault.recoverCollateral(htpIndex, collateralWad);
        vm.stopPrank();

        assertEq(IERC20(gem).balanceOf(admin), gemBalanceBefore + gemsToRecover, "Admin didn't receive 6-decimal collateral");
        console.log("IERC20(gem).balanceOf(admin)", IERC20(gem).balanceOf(admin));
        console.log("gemBalanceBefore", gemBalanceBefore);
        console.log("gemsToRecover", gemsToRecover);
        assertEq(IERC20(gem).balanceOf(address(vault)), 0, "Vault should have no 6-decimal collateral");
        
        // The recovered value calculation in the vault should handle the decimal conversion properly
        // removedCollateralValue = (gemsToRecover * price) / 10^6 (to convert from 6 decimals back to WAD)
        assertApproxEqAbs(vault.removedCollateralValue(), totalAssetsBefore, 10**12, "Vault should store the removed collateral value");
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 10**12, "Total assets should account for removed collateral");
        
        // Vault should be paused due to removed collateral
        assertGt(vault.removedCollateralValue(), 0, "Vault should be paused due to removed collateral");
        console.log("vault.removedCollateralValue()", vault.removedCollateralValue());
    }
}
