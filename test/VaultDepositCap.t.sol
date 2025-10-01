// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {IVaultAuth} from "../src/VaultAuth.sol";
import {ERC4626} from "../src/ERC4626.sol";

contract VaultDepositCapTest is VaultBaseTest {
    event DepositCapSet(uint256 newDepositCap);

    function test_setDepositCap() public {
        uint256 newCap = 1000 ether;
        
        vm.expectEmit(true, true, true, true);
        emit DepositCapSet(newCap);
        
        vm.prank(admin);
        auth.setDepositCap(newCap);
        
        assertEq(auth.depositCap(), newCap, "Deposit cap not set correctly");
    }

    function test_fail_setDepositCap_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setDepositCap(1000 ether);
    }

    function test_depositCap_noCapByDefault() public {
        // Default deposit cap should be 0 (no cap)
        assertEq(auth.depositCap(), 0, "Default deposit cap should be 0");
        
        // Should be able to deposit without restriction
        uint256 assets = 500 * 10 ** vault.assetDecimals();
        
        vm.prank(alice);
        vault.deposit(assets, alice);
        
        assertEq(vault.balanceOf(alice), assets, "Alice should receive shares");
    }

    function test_depositCap_allowsDepositsUnderCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 depositAmount = 500 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        assertEq(vault.balanceOf(alice), depositAmount, "Alice should receive shares");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");
    }

    function test_depositCap_preventsDepositsOverCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 depositAmount = 1200 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, alice, depositAmount, cap));
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
    }

    function test_depositCap_preventsDepositsThatWouldExceedCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 firstDeposit = 600 * 10 ** vault.assetDecimals();
        uint256 secondDeposit = 500 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        // First deposit should succeed
        vm.prank(alice);
        vault.deposit(firstDeposit, alice);
        
        // Second deposit should fail as it would exceed cap
        uint256 maxAllowed = cap - firstDeposit;
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, bob, secondDeposit, maxAllowed));
        vm.prank(bob);
        vault.deposit(secondDeposit, bob);
    }

    function test_depositCap_allowsExactCapDeposit() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        vm.prank(alice);
        vault.deposit(cap, alice);
        
        assertEq(vault.totalAssets(), cap, "Total assets should equal cap");
    }

    function test_mintCap_preventsMintsThatWouldExceedCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 sharesToMint = 1200 * 10 ** vault.decimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        uint256 maxMintAllowed = vault.maxMint(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, alice, sharesToMint, maxMintAllowed));
        vm.prank(alice);
        vault.mint(sharesToMint, alice);
    }

    function test_maxDeposit_respectsDepositCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, cap, "Max deposit should equal cap when no assets deposited");
        
        // After depositing some assets, max should be reduced
        uint256 firstDeposit = 300 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(firstDeposit, alice);
        
        uint256 maxDepositAfter = vault.maxDeposit(bob);
        assertEq(maxDepositAfter, cap - firstDeposit, "Max deposit should be reduced by existing deposits");
    }

    function test_maxDeposit_returnsZeroWhenCapReached() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        vm.prank(alice);
        vault.deposit(cap, alice);
        
        uint256 maxDeposit = vault.maxDeposit(bob);
        assertEq(maxDeposit, 0, "Max deposit should be 0 when cap is reached");
    }

    function test_maxMint_respectsDepositCap() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        uint256 maxMint = vault.maxMint(alice);
        assertGt(maxMint, 0, "Max mint should be greater than 0");
        
        // After reaching cap, max mint should be 0
        vm.prank(alice);
        vault.deposit(cap, alice);
        
        uint256 maxMintAfter = vault.maxMint(bob);
        assertEq(maxMintAfter, 0, "Max mint should be 0 when cap is reached");
    }

    function test_depositCap_canBeRaised() public {
        uint256 initialCap = 1000 * 10 ** vault.assetDecimals();
        uint256 newCap = 2000 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(initialCap);
        
        // Fill to initial cap
        vm.prank(alice);
        vault.deposit(initialCap, alice);
        
        // Should not be able to deposit more
        uint256 attemptAmount = 100 * 10 ** vault.assetDecimals();
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, bob, attemptAmount, 0));
        vm.prank(bob);
        vault.deposit(attemptAmount, bob);
        
        // Raise the cap
        vm.prank(admin);
        auth.setDepositCap(newCap);
        
        // Now should be able to deposit more
        uint256 additionalDeposit = 500 * 10 ** vault.assetDecimals();
        vm.prank(bob);
        vault.deposit(additionalDeposit, bob);
        
        assertEq(vault.totalAssets(), initialCap + additionalDeposit, "Total assets should include additional deposit");
    }

    function test_depositCap_canBeLowered() public {
        uint256 initialCap = 2000 * 10 ** vault.assetDecimals();
        uint256 newCap = 1000 * 10 ** vault.assetDecimals();
        uint256 currentDeposits = 800 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(initialCap);
        
        // Deposit some assets
        vm.prank(alice);
        vault.deposit(currentDeposits, alice);
        
        // Lower the cap
        vm.prank(admin);
        auth.setDepositCap(newCap);
        
        // Should still be able to deposit up to new cap
        uint256 remainingCapacity = newCap - currentDeposits;
        vm.prank(bob);
        vault.deposit(remainingCapacity, bob);
        
        // But not more
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, bob, 1, 0));
        vm.prank(bob);
        vault.deposit(1, bob);
    }

    function test_depositCap_canBeRemovedBySettingToZero() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 largeDeposit = 2000 * 10 ** vault.assetDecimals();
        
        // Give alice enough balance for the large deposit
        deal(vault.asset(), alice, largeDeposit);
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        // Should not be able to deposit large amount
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, alice, largeDeposit, cap));
        vm.prank(alice);
        vault.deposit(largeDeposit, alice);
        
        // Remove cap by setting to 0
        vm.prank(admin);
        auth.setDepositCap(0);
        
        // Now should be able to deposit large amount
        vm.prank(alice);
        vault.deposit(largeDeposit, alice);
        
        assertEq(vault.totalAssets(), largeDeposit, "Should be able to deposit large amount with no cap");
    }

    function test_depositCap_previewFunctionsStillWork() public {
        uint256 cap = 1000 * 10 ** vault.assetDecimals();
        uint256 assets = 500 * 10 ** vault.assetDecimals();
        
        vm.prank(admin);
        auth.setDepositCap(cap);
        
        // Preview functions should still work normally
        uint256 previewShares = vault.previewDeposit(assets);
        uint256 previewAssets = vault.previewMint(assets);
        
        assertGt(previewShares, 0, "Preview deposit should return shares");
        assertGt(previewAssets, 0, "Preview mint should return assets");
    }
}