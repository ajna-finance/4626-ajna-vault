// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {IVaultAuth} from "../src/VaultAuth.sol";

contract VaultAdminTest is VaultBaseTest {
    function test_constructor() public view {
        assertEq(auth.admin(), admin, "Admin not set");
    }

    function test_fail_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(bob);
        auth.setAdmin(address(0));
    }

    event SetAdmin(address indexed newAdmin);

    function test_setAdmin() public {
        assertEq(auth.admin(), admin, "Admin not set");
        vm.expectEmit(true, true, true, true);
        emit SetAdmin(bob);
        vm.prank(admin);
        auth.setAdmin(bob);
        assertEq(auth.admin(), bob, "Admin not set");
    }

    event SetSwapper(address indexed newSwapper);

    function test_setSwapper() public {
        assertEq(auth.swapper(), swapper, "Swapper not set");
        vm.expectEmit(true, true, true, true);
        emit SetSwapper(bob);
        vm.prank(admin);
        auth.setSwapper(bob);
        assertEq(auth.swapper(), bob, "Swapper not set after set");
    }

    function test_fail_setSwapper_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(bob);
        auth.setSwapper(bob);
    }

    event Paused();
    event Unpaused();

    function test_pause() public {
        assertEq(auth.paused(), false, "Auth should not be paused");
        vm.expectEmit(true, true, true, true);
        emit Paused();
        vm.prank(admin);
        auth.pause();
        assertEq(auth.paused(), true, "Auth should be paused");
    }

    function test_unpause() public {
        vm.prank(admin);
        auth.pause();
        assertEq(auth.paused(), true, "Auth should be paused");
        vm.expectEmit(true, true, true, true);
        emit Unpaused();
        vm.prank(admin);
        auth.unpause();
        assertEq(auth.paused(), false, "Auth should not be paused");
    }

    function test_fail_pause_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(bob);
        auth.pause();
    }

    function test_fail_unpause_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(bob);
        auth.unpause();
    }

    function test_pause_alreadyPaused() public {
        vm.prank(admin);
        auth.pause();
        // Auth allows pausing when already paused (no revert)
        vm.prank(admin);
        auth.pause();
        assertEq(auth.paused(), true, "Auth should still be paused");
    }

    function test_unpause_notPaused() public {
        // Auth allows unpausing when not paused (no revert)
        vm.prank(admin);
        auth.unpause();
        assertEq(auth.paused(), false, "Auth should still be unpaused");
    }

    function test_vault_paused_when_removedCollateralValue() public {
        // Auth can be unpaused, but vault operations remain paused if removedCollateralValue > 0
        vm.prank(admin);
        auth.pause();
        vm.prank(admin);
        auth.unpause();
        assertEq(auth.paused(), false, "Auth should be unpaused");
        
        // Set removedCollateralValue > 0 to simulate recovery state
        vm.store(address(vault), bytes32(uint256(10)), bytes32(uint256(1)));
        assertEq(vault.removedCollateralValue(), 1, "Removed collateral value should be 1");
        
        // Vault operations should still be paused due to removedCollateralValue > 0
        vm.expectRevert(abi.encodeWithSelector(IVault.VaultPaused.selector));
        vm.prank(alice);
        vault.deposit(100 ether, alice);
    }

    // KEEPER MANAGEMENT TESTS
    event KeeperSet(address indexed keeper, bool isKeeper);

    function test_addKeeper() public {
        // Verify keeper is not initially set
        assertFalse(auth.keepers(alice), "Alice should not be a keeper initially");
        
        // Admin adds keeper
        vm.expectEmit(true, true, true, true);
        emit KeeperSet(alice, true);
        vm.prank(admin);
        auth.setKeeper(alice, true);
        
        // Verify keeper is now set
        assertTrue(auth.keepers(alice), "Alice should be a keeper after being added");
    }

    function test_removeKeeper() public {
        // First add keeper
        vm.prank(admin);
        auth.setKeeper(alice, true);
        assertTrue(auth.keepers(alice), "Alice should be a keeper");
        
        // Admin removes keeper
        vm.expectEmit(true, true, true, true);
        emit KeeperSet(alice, false);
        vm.prank(admin);
        auth.setKeeper(alice, false);
        
        // Verify keeper is removed
        assertFalse(auth.keepers(alice), "Alice should not be a keeper after removal");
    }

    function test_addMultipleKeepers() public {
        // Add multiple keepers
        vm.startPrank(admin);
        auth.setKeeper(alice, true);
        auth.setKeeper(bob, true);
        vm.stopPrank();
        
        // Verify all are keepers
        assertTrue(auth.keepers(alice), "Alice should be a keeper");
        assertTrue(auth.keepers(bob), "Bob should be a keeper");
        assertTrue(auth.keepers(keeper), "Keeper should be a keeper");
    }

    function test_removeSpecificKeeper() public {
        // Add multiple keepers
        vm.startPrank(admin);
        auth.setKeeper(alice, true);
        auth.setKeeper(bob, true);
        vm.stopPrank();
        
        // Remove only bob
        vm.prank(admin);
        auth.setKeeper(bob, false);
        
        // Verify only bob is removed
        assertTrue(auth.keepers(alice), "Alice should still be a keeper");
        assertFalse(auth.keepers(bob), "Bob should not be a keeper after removal");
        assertTrue(auth.keepers(keeper), "Keeper should still be a keeper");
    }

    function test_fail_addKeeper_notAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setKeeper(bob, true);
    }

    function test_fail_removeKeeper_notAdmin() public {
        // First add keeper as admin
        vm.prank(admin);
        auth.setKeeper(alice, true);
        
        // Try to remove as non-admin
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.setKeeper(alice, false);
    }

    function test_readd_removedKeeper() public {
        // Add keeper
        vm.prank(admin);
        auth.setKeeper(alice, true);
        assertTrue(auth.keepers(alice), "Alice should be a keeper");
        
        // Remove keeper
        vm.prank(admin);
        auth.setKeeper(alice, false);
        assertFalse(auth.keepers(alice), "Alice should not be a keeper");
        
        // Re-add keeper
        vm.prank(admin);
        auth.setKeeper(alice, true);
        assertTrue(auth.keepers(alice), "Alice should be a keeper again");
    }

    function test_removeNonexistentKeeper() public {
        // Try to remove keeper that was never added - should not revert
        assertFalse(auth.keepers(alice), "Alice should not be a keeper initially");
        
        vm.prank(admin);
        auth.setKeeper(alice, false); // Should succeed even though alice was never a keeper
        
        assertFalse(auth.keepers(alice), "Alice should still not be a keeper");
    }

    function test_retrieveFees() public {
        address asset = vault.asset();
        // First generate some fees
        vm.prank(admin);
        auth.setToll(100); // 1%
        
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Check AUTH has fees
        uint256 authBalance = IERC20(asset).balanceOf(address(auth));
        uint256 expectedFees = (depositAmount * 100) / 10000; // 1%
        assertEq(authBalance, expectedFees, "AUTH should have collected fees");
        
        // Admin retrieves fees
        uint256 adminBalanceBefore = IERC20(asset).balanceOf(admin);
        vm.prank(admin);
        auth.retrieveFees(asset, authBalance);
        
        // Check fees were transferred to admin
        assertEq(
            IERC20(asset).balanceOf(admin),
            adminBalanceBefore + authBalance,
            "Admin should receive all fees"
        );
        assertEq(
            IERC20(asset).balanceOf(address(auth)),
            0,
            "AUTH should have no remaining fees"
        );
    }

    function test_fail_retrieveFees_notAdmin() public {
        address asset = vault.asset();
        // Generate some fees first
        vm.prank(admin);
        auth.setTax(200); // 2%
        
        uint256 depositAmount = 500 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        uint256 withdrawAmount = 100 ether;
        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        
        uint256 authBalance = IERC20(asset).balanceOf(address(auth));
        
        // Non-admin tries to retrieve fees
        vm.expectRevert(abi.encodeWithSelector(IVaultAuth.NotAuthorized.selector));
        vm.prank(alice);
        auth.retrieveFees(asset, authBalance);
    }
}
