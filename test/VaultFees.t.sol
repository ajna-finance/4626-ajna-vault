// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {IVaultAuth} from "../src/VaultAuth.sol";

contract VaultFeesTest is VaultBaseTest {
    event TollSet(uint256 newToll);
    event TaxSet(uint256 newTax);

    function test_setToll() public {
        uint256 newToll = 100; // 1%
        
        vm.expectEmit(true, true, true, true);
        emit TollSet(newToll);
        
        vm.prank(admin);
        auth.setToll(newToll);
        
        assertEq(auth.toll(), newToll, "Toll not set correctly");
    }

    function test_setTax() public {
        uint256 newTax = 200; // 2%
        
        vm.expectEmit(true, true, true, true);
        emit TaxSet(newTax);
        
        vm.prank(admin);
        auth.setTax(newTax);
        
        assertEq(auth.tax(), newTax, "Tax not set correctly");
    }

    function test_fail_setToll_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setToll(100);
    }

    function test_fail_setTax_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setTax(100);
    }

    function test_fail_setToll_tooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.FeeTooHigh.selector));
        vm.prank(admin);
        auth.setToll(1001); // > 10%
    }

    function test_fail_setTax_tooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.FeeTooHigh.selector));
        vm.prank(admin);
        auth.setTax(1001); // > 10%
    }

    function test_setToll_maxAllowed() public {
        vm.prank(admin);
        auth.setToll(1000); // Exactly 10%
        assertEq(auth.toll(), 1000, "Should allow exactly 10%");
    }

    function test_setTax_maxAllowed() public {
        vm.prank(admin);
        auth.setTax(1000); // Exactly 10%
        assertEq(auth.tax(), 1000, "Should allow exactly 10%");
    }

    function test_defaultFees() public view {
        // Default fees should be 0
        assertEq(auth.toll(), 0, "Default toll should be 0");
        assertEq(auth.tax(), 0, "Default tax should be 0");
    }

    function test_feesCanBeChanged() public {
        // Set initial fees
        vm.prank(admin);
        auth.setToll(100); // 1%
        
        vm.prank(admin);
        auth.setTax(200); // 2%
        
        assertEq(auth.toll(), 100, "Toll should be 1%");
        assertEq(auth.tax(), 200, "Tax should be 2%");
        
        // Change the fees
        vm.prank(admin);
        auth.setToll(150); // 1.5%
        
        vm.prank(admin);
        auth.setTax(50); // 0.5%
        
        assertEq(auth.toll(), 150, "Toll should be 1.5%");
        assertEq(auth.tax(), 50, "Tax should be 0.5%");
    }

    function test_feesCanBeSetToZero() public {
        // First set non-zero fees
        vm.prank(admin);
        auth.setToll(500); // 5%
        
        vm.prank(admin);
        auth.setTax(300); // 3%
        
        // Then set them back to zero
        vm.prank(admin);
        auth.setToll(0);
        
        vm.prank(admin);
        auth.setTax(0);
        
        assertEq(auth.toll(), 0, "Toll should be 0");
        assertEq(auth.tax(), 0, "Tax should be 0");
    }

    // TOLL APPLICATION TESTS

    function test_depositWithToll() public {
        // Set 1% toll
        vm.prank(admin);
        auth.setToll(100); // 1%
        
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        uint256 expectedToll = depositAmount / 100; // 1%
        uint256 netDeposit = depositAmount - expectedToll;
        
        uint256 authBalanceBefore = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        
        // Preview should show reduced shares due to toll
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        
        // Check shares match preview
        assertEq(shares, expectedShares, "Shares should match preview");
        
        // Check toll was sent to AUTH
        assertEq(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceBefore + expectedToll,
            "AUTH should receive toll"
        );
        
        // Check user paid full amount
        assertEq(
            IERC20(vault.asset()).balanceOf(alice),
            aliceBalanceBefore - depositAmount,
            "Alice should pay full deposit amount"
        );
        
        // Check vault received net amount (in buffer)
        assertEq(
            IERC20(vault.asset()).balanceOf(vault.buffer()),
            netDeposit,
            "Buffer should receive net deposit"
        );
    }

    function test_mintWithToll() public {
        // Set 1% toll
        vm.prank(admin);
        auth.setToll(100); // 1%
        
        uint256 sharesToMint = 500 * 10 ** vault.decimals(); // Reduce amount to stay within balance
        
        uint256 authBalanceBefore = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        
        // Preview should show increased assets due to toll
        uint256 expectedAssets = vault.previewMint(sharesToMint);
        
        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);
        
        // Check assets match preview
        assertEq(assets, expectedAssets, "Assets should match preview");
        
        // Calculate expected toll from the assets paid
        uint256 baseAssets = vault.convertToAssets(sharesToMint); // assets without toll
        uint256 expectedToll = assets - baseAssets;
        
        // Check toll was sent to AUTH
        assertEq(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceBefore + expectedToll,
            "AUTH should receive toll"
        );
        
        // Check user paid full amount (including toll)
        assertEq(
            IERC20(vault.asset()).balanceOf(alice),
            aliceBalanceBefore - assets,
            "Alice should pay full amount including toll"
        );
        
        // Check user received exact shares requested
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice should receive exact shares");
        
        // Check vault received net amount (in buffer)
        assertEq(
            IERC20(vault.asset()).balanceOf(vault.buffer()),
            baseAssets,
            "Buffer should receive base assets (after toll)"
        );
    }

    function test_depositAndMintEquivalence() public {
        // Set 2% toll
        vm.prank(admin);
        auth.setToll(200); // 2%
        
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();

        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 bobBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        
        // Alice deposits
        vm.prank(alice);
        uint256 sharesFromDeposit = vault.deposit(depositAmount, alice);
        
        // Bob mints the same number of shares
        console.log("sharesFromDeposit", sharesFromDeposit);
        vm.prank(bob);
        uint256 assetsForMint = vault.mint(sharesFromDeposit, bob);
        
        // Both should have same shares
        assertEq(
            vault.balanceOf(alice),
            vault.balanceOf(bob),
            "Alice and Bob should have same shares"
        );
        
        // Both should pay the SAME amount for the same shares
        assertEq(
            assetsForMint,
            depositAmount,
            "Deposit and mint should cost the same for equivalent shares"
        );

        assertEq(
            aliceBalanceBefore - IERC20(vault.asset()).balanceOf(alice),
            bobBalanceBefore - IERC20(vault.asset()).balanceOf(bob),
            "Alice and Bob should pay the same amount"
        );
    }

    function test_previewFunctionEquivalence() public {
        // Set 10% toll
        vm.prank(admin);
        auth.setToll(1000); // 10%
        
        uint256 assets = 1000 * 10 ** vault.assetDecimals();
        
        uint256 previewDepositShares = vault.previewDeposit(assets);
        uint256 previewMintAssets = vault.previewMint(previewDepositShares);
        
        assertEq(previewMintAssets, assets, "Preview functions should be equivalent");
        console.log("previewDepositShares", previewDepositShares);
        console.log("previewMintAssets   ", previewMintAssets);
        console.log("assets              ", assets);

        uint256 shares = 1000 * 10 ** vault.decimals();

        previewMintAssets = vault.previewMint(shares);
        previewDepositShares = vault.previewDeposit(previewMintAssets);
        assertEq(previewDepositShares, shares, "Preview functions should be equivalent");
        console.log("previewMintAssets   ", previewMintAssets);
        console.log("previewDepositShares", previewDepositShares);
        console.log("shares              ", shares);
    }

    function test_previewFunctionsWithToll() public {
        // Set 5% toll
        vm.prank(admin);
        auth.setToll(500); // 5%
        
        uint256 assets = 1000 * 10 ** vault.assetDecimals();
        uint256 shares = 1000 * 10 ** vault.decimals();
        
        // Test previewDeposit
        uint256 previewShares = vault.previewDeposit(assets);
        uint256 expectedNetAssets = (assets * 9500) / 10000; // 95% after 5% toll
        uint256 expectedShares = vault.convertToShares(expectedNetAssets);
        assertApproxEqAbs(
            previewShares,
            expectedShares,
            1,
            "previewDeposit should account for toll"
        );
        
        // Test previewMint
        uint256 previewAssets = vault.previewMint(shares);
        uint256 baseAssets = vault.convertToAssets(shares);
        // With 5% toll: user pays baseAssets / (1 - 0.05) = baseAssets / 0.95 = baseAssets * 10000 / 9500
        uint256 expectedAssets = (baseAssets * 10000) / 9500;
        assertApproxEqAbs(
            previewAssets,
            expectedAssets,
            2, // Allow for rounding differences
            "previewMint should include toll"
        );
    }

    function test_tollAccumulationInAuth() public {
        // Set 3% toll
        vm.prank(admin);
        auth.setToll(300); // 3%
        
        uint256 authBalanceStart = IERC20(vault.asset()).balanceOf(address(auth));
        
        // Multiple deposits from different users
        uint256 deposit1 = 500 * 10 ** vault.assetDecimals();
        uint256 deposit2 = 300 * 10 ** vault.assetDecimals();
        uint256 deposit3 = 200 * 10 ** vault.assetDecimals();
        
        vm.prank(alice);
        vault.deposit(deposit1, alice);
        
        vm.prank(bob);
        vault.deposit(deposit2, bob);
        
        vm.prank(alice);
        vault.deposit(deposit3, alice);
        
        uint256 totalDeposited = deposit1 + deposit2 + deposit3;
        uint256 expectedTotalToll = (totalDeposited * 300) / 10000; // 3%
        
        assertEq(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceStart + expectedTotalToll,
            "AUTH should accumulate all tolls"
        );
    }

    function test_changingTollBetweenTransactions() public {
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        
        // First deposit with 1% toll
        vm.prank(admin);
        auth.setToll(100); // 1%
        
        uint256 shares1 = vault.previewDeposit(depositAmount);
        vm.prank(alice);
        uint256 actualShares1 = vault.deposit(depositAmount, alice);
        assertEq(actualShares1, shares1, "First deposit shares should match preview");
        
        // Change toll to 5%
        vm.prank(admin);
        auth.setToll(500); // 5%
        
        // Second deposit with new toll
        uint256 shares2 = vault.previewDeposit(depositAmount);
        vm.prank(bob);
        uint256 actualShares2 = vault.deposit(depositAmount, bob);
        assertEq(actualShares2, shares2, "Second deposit shares should match preview");
        
        // Bob should get fewer shares due to higher toll
        assertLt(actualShares2, actualShares1, "Higher toll should result in fewer shares");
    }

    function test_maxDepositWithToll() public {
        // Set deposit cap
        uint256 cap = 1500 * 10 ** vault.assetDecimals(); // Reduce cap to stay within user balances
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        // Set 2% toll
        vm.prank(admin);
        auth.setToll(200); // 2%
        
        uint256 maxDep = vault.maxDeposit(alice);
        assertEq(maxDep, cap, "Max deposit should equal cap");
        
        // Deposit some amount
        uint256 firstDeposit = 500 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(firstDeposit, alice);
        
        // Total assets should be less than deposit due to toll
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 expectedNetDeposit = (firstDeposit * 9800) / 10000; // 98% after 2% toll
        assertEq(totalAssetsAfter, expectedNetDeposit, "Total assets should be net of toll");
        
        // Max deposit should still be based on gross cap
        uint256 remainingCap = cap - totalAssetsAfter;
        assertEq(vault.maxDeposit(bob), remainingCap, "Max deposit should be remaining cap");
    }

    // TAX APPLICATION TESTS

    function test_withdrawWithTax() public {
        // First deposit some assets
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Set 3% tax
        vm.prank(admin);
        auth.setTax(300); // 3%
        
        uint256 withdrawAmount = 500 * 10 ** vault.assetDecimals();
        uint256 authBalanceBefore = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 bobBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        
        // Preview should show more shares needed due to tax
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        
        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, bob, alice);
        
        // Check shares match preview
        assertEq(shares, expectedShares, "Shares should match preview");

        uint256 expectedTax = (withdrawAmount * 300) / 10000; // 3%
        
        // Check bob received exact net amount requested
        assertEq(
            IERC20(vault.asset()).balanceOf(bob),
            bobBalanceBefore + withdrawAmount,
            "Bob should receive exact withdrawal amount"
        );
        
        // Check tax was sent to AUTH (calculate expected tax)
        assertEq(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceBefore + expectedTax,
            "AUTH should receive tax"
        );
    }

    function test_redeemWithTax() public {
        // First deposit some assets
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Set 2% tax
        vm.prank(admin);
        auth.setTax(200); // 2%
        
        uint256 sharesToRedeem = 400 * 10 ** vault.decimals();
        uint256 authBalanceBefore = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 bobBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        
        // Preview should show reduced assets due to tax
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        
        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, bob, alice);
        
        // Check assets match preview
        assertEq(assets, expectedAssets, "Assets should match preview");
        
        // Check bob received net assets
        assertEq(
            IERC20(vault.asset()).balanceOf(bob),
            bobBalanceBefore + assets,
            "Bob should receive net assets"
        );
        
        // Check alice's shares were burned
        assertEq(
            vault.balanceOf(alice), 
            depositAmount - sharesToRedeem,
            "Alice's shares should be reduced"
        );
        
        // Check tax was sent to AUTH
        uint256 grossAssets = vault.convertToAssets(sharesToRedeem);
        uint256 expectedTax = (grossAssets * 200) / 10000; // 2%
        assertEq(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceBefore + expectedTax,
            "AUTH should receive tax"
        );
    }

    function test_previewAndWithdrawEquivalence() public {
        // Set 4% tax
        vm.prank(admin);
        auth.setTax(400); // 4%
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 withdrawAmount = 500 * 10 ** vault.assetDecimals();
        uint256 previewShares = vault.previewWithdraw(withdrawAmount);
        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);
        assertEq(shares, previewShares, "Shares should match preview");

        assertEq(aliceBalanceBefore + withdrawAmount, IERC20(vault.asset()).balanceOf(alice), "Alice should receive exact withdrawal amount");
        assertGt(shares, vault.convertToShares(withdrawAmount), "Shares should be greater to cover tax");
    }

    function test_previewAndRedeemEquivalence() public {
        // Set 4% tax
        vm.prank(admin);
        auth.setTax(400); // 4%
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        
        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        uint256 sharesToRedeem = vault.balanceOf(alice);
        uint256 previewAssets = vault.previewRedeem(sharesToRedeem);
        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);
        assertEq(assets, previewAssets, "Assets should match preview");

        assertEq(aliceBalanceBefore + assets, IERC20(vault.asset()).balanceOf(alice), "Alice should receive exact redemption amount");
        assertGt(sharesToRedeem, vault.convertToShares(assets), "Shares should be greater to cover tax");
    }

    function test_withdrawAndRedeemEquivalence() public {
        // Set up two identical accounts
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        vm.prank(bob);
        vault.deposit(depositAmount, bob);
        
        // Set 4% tax
        vm.prank(admin);
        auth.setTax(400); // 4%
        
        uint256 withdrawAmount = 300 * 10 ** vault.assetDecimals();

        uint256 previewSharesForWithdraw = vault.previewWithdraw(withdrawAmount);
        uint256 previewAssetsFromRedeem = vault.previewRedeem(previewSharesForWithdraw);
        
        assertApproxEqAbs(
            previewAssetsFromRedeem,
            withdrawAmount,
            1,
            "Preview functions should be equivalent for tax"
        );
        
        // Bob redeems first
        uint256 bobBalanceBefore = IERC20(vault.asset()).balanceOf(bob);
        vm.prank(bob);
        uint256 assetsFromRedeem = vault.redeem(previewSharesForWithdraw, bob, bob);
        
        // Alice withdraws specific amount after Bob's redeem
        uint256 aliceBalanceBefore = IERC20(vault.asset()).balanceOf(alice);
        vm.prank(alice);
        uint256 sharesFromWithdraw = vault.withdraw(withdrawAmount, alice, alice);
        assertEq(sharesFromWithdraw, previewSharesForWithdraw, "Shares from withdraw should be equal to shares for withdraw");

        assertEq(assetsFromRedeem, previewAssetsFromRedeem, "redeem preview should be same as redeem");

        assertEq(assetsFromRedeem, withdrawAmount, "Assets from redeem should be equal to withdraw amount");
        
        // Both should have received equivalent value
        uint256 aliceReceived = IERC20(vault.asset()).balanceOf(alice) - aliceBalanceBefore;
        uint256 bobReceived = IERC20(vault.asset()).balanceOf(bob) - bobBalanceBefore;
        
        assertEq(aliceReceived, withdrawAmount, "Alice should receive exact withdrawal amount");
        assertApproxEqAbs(
            bobReceived,
            withdrawAmount,
            1,
            "Bob should receive approximately same amount as Alice"
        );
    }

    function test_taxIncreasesSharesWithdraw() public {
        uint256 assets = 1000 * 10 ** vault.assetDecimals();
        assertEq(auth.tax(), 0);
        uint256 sharesWithoutTax = vault.previewWithdraw(assets);
        vm.prank(admin);
        auth.setTax(1000); // 10%
        uint256 sharesWithTax = vault.previewWithdraw(assets);
        assertLt(sharesWithoutTax, sharesWithTax);
    }

    function test_taxReducesAssetsRedeem() public {
        uint256 shares = 1000 * 10 ** vault.assetDecimals();
        assertEq(auth.tax(), 0);
        uint256 assetsWithoutTax = vault.previewRedeem(shares);
        vm.prank(admin);
        auth.setTax(1000); // 10%
        uint256 assetsWithTax = vault.previewRedeem(shares);
        assertGt(assetsWithoutTax, assetsWithTax);
    }

    function test_previewFunctionsTaxEquivalence() public {
        // Set 6% tax
        vm.prank(admin);
        auth.setTax(600); // 6%
        
        uint256 assets = 500 * 10 ** vault.assetDecimals();
        
        // Test withdraw preview equivalence
        uint256 sharesForWithdraw = vault.previewWithdraw(assets);
        uint256 assetsFromRedeem = vault.previewRedeem(sharesForWithdraw);
        
        assertApproxEqAbs(
            assetsFromRedeem,
            assets,
            1,
            "Preview functions should be equivalent for tax"
        );
        
        // Test redeem preview equivalence
        uint256 shares = 500 * 10 ** vault.decimals();
        uint256 assetsForRedeem = vault.previewRedeem(shares);
        uint256 sharesFromWithdraw = vault.previewWithdraw(assetsForRedeem);
        
        assertApproxEqAbs(
            sharesFromWithdraw,
            shares,
            1,
            "Preview functions should be equivalent for tax"
        );
    }

    function test_taxAccumulationInAuth() public {
        // Set 5% tax
        vm.prank(admin);
        auth.setTax(500); // 5%
        
        // Deposit from multiple users
        uint256 depositAmount = 600 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        vm.prank(bob);
        vault.deposit(depositAmount, bob);
        
        uint256 authBalanceStart = IERC20(vault.asset()).balanceOf(address(auth));
        
        // Multiple withdrawals
        uint256 withdraw1 = 200 * 10 ** vault.assetDecimals();
        uint256 withdraw2 = 150 * 10 ** vault.assetDecimals();
        
        vm.prank(alice);
        vault.withdraw(withdraw1, alice, alice);
        
        vm.prank(bob);
        vault.withdraw(withdraw2, bob, bob);
        
        // Calculate expected total tax directly from withdrawal amounts
        uint256 expectedTax1 = (withdraw1 * 500) / 10000; // 5%
        uint256 expectedTax2 = (withdraw2 * 500) / 10000; // 5% 
        uint256 expectedTotalTax = expectedTax1 + expectedTax2;
        
        assertApproxEqAbs(
            IERC20(vault.asset()).balanceOf(address(auth)),
            authBalanceStart + expectedTotalTax,
            2,
            "AUTH should accumulate all taxes"
        );
    }

    function test_changingTaxBetweenTransactions() public {
        uint256 depositAmount = 800 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        vm.prank(bob);
        vault.deposit(depositAmount, bob);
        
        uint256 withdrawAmount = 200 * 10 ** vault.assetDecimals();
        
        // First withdrawal with 2% tax
        vm.prank(admin);
        auth.setTax(200); // 2%
        
        uint256 shares1 = vault.previewWithdraw(withdrawAmount);
        vm.prank(alice);
        uint256 actualShares1 = vault.withdraw(withdrawAmount, alice, alice);
        assertEq(actualShares1, shares1, "First withdrawal shares should match preview");
        
        // Change tax to 8%
        vm.prank(admin);
        auth.setTax(800); // 8%
        
        // Second withdrawal with new tax
        uint256 shares2 = vault.previewWithdraw(withdrawAmount);
        vm.prank(bob);
        uint256 actualShares2 = vault.withdraw(withdrawAmount, bob, bob);
        assertEq(actualShares2, shares2, "Second withdrawal shares should match preview");
        
        // Bob should need more shares due to higher tax
        assertGt(actualShares2, actualShares1, "Higher tax should require more shares");
    }

    function test_taxWithZeroAmount() public {
        // Set 7% tax
        vm.prank(admin);
        auth.setTax(700); // 7%
        
        // Deposit some assets first
        uint256 depositAmount = 500 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Withdraw 0 should work
        vm.prank(alice);
        uint256 shares = vault.withdraw(0, alice, alice);
        assertEq(shares, 0, "Withdrawing 0 should burn 0 shares");
        
        // Redeem 0 should work
        vm.prank(alice);
        uint256 assets = vault.redeem(0, alice, alice);
        assertEq(assets, 0, "Redeeming 0 should return 0 assets");
    }

    function test_combinedTollAndTax() public {
        // Set both toll and tax
        vm.prank(admin);
        auth.setToll(300); // 3%
        vm.prank(admin);
        auth.setTax(250); // 2.5%
        
        uint256 depositAmount = 1000 * 10 ** vault.assetDecimals();
        uint256 authBalanceBefore = IERC20(vault.asset()).balanceOf(address(auth));
        
        // Alice deposits (pays toll)
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        uint256 authBalanceAfterDeposit = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 expectedToll = (depositAmount * 300) / 10000; // 3%
        assertEq(
            authBalanceAfterDeposit,
            authBalanceBefore + expectedToll,
            "AUTH should receive toll from deposit"
        );
        
        // Alice withdraws (pays tax)
        uint256 withdrawAmount = 400 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        
        uint256 authBalanceAfterWithdraw = IERC20(vault.asset()).balanceOf(address(auth));
        uint256 expectedTax = (withdrawAmount * 250) / 10000; // 2.5%
        
        assertApproxEqAbs(
            authBalanceAfterWithdraw,
            authBalanceAfterDeposit + expectedTax,
            1,
            "AUTH should receive tax from withdrawal"
        );
    }
}