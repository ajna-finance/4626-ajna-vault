// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import "./Vault.base.t.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PoolMock} from "./mocks/PoolMock.sol";
import {IVault} from "../src/interfaces/IVault.sol";

contract VaultBranchCoverageTest is VaultBaseTest {

    // Test Line 63: Invalid quote token in constructor
    function test_fail_constructor_invalidQuoteToken() public {
        // Create a pool mock (which creates its own quote token)
        PoolMock poolWithWrongQuoteToken = new PoolMock();
        
        // Try to create vault with a different asset than the pool's quote token
        MockERC20 differentToken = new MockERC20("Different", "DIFF", 18);
        
        vm.expectRevert(IVault.InvalidQuoteToken.selector);
        new Vault(
            IPool(address(poolWithWrongQuoteToken)), 
            address(info), 
            IERC20(address(differentToken)), 
            "Test", 
            "TEST", 
            IVaultAuth(address(auth))
        );
    }

    // Test Line 68: Invalid asset decimals in constructor (0 decimals)
    function test_fail_constructor_zeroDecimals() public {
        PoolMock testPool = new PoolMock();
        address quoteToken = testPool.quoteTokenAddress();
        
        // Mock the decimals call to return 0
        vm.mockCall(
            quoteToken,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(0))
        );
        
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAssetDecimals.selector, 0));
        new Vault(
            IPool(address(testPool)), 
            address(info), 
            IERC20(quoteToken), 
            "Test", 
            "TEST", 
            IVaultAuth(address(auth))
        );
    }

    // Test Line 68: Invalid asset decimals in constructor (>18 decimals)
    function test_fail_constructor_tooManyDecimals() public {
        PoolMock testPool = new PoolMock();
        address quoteToken = testPool.quoteTokenAddress();
        
        // Mock the decimals call to return 19
        vm.mockCall(
            quoteToken,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(19))
        );
        
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAssetDecimals.selector, 19));
        new Vault(
            IPool(address(testPool)), 
            address(info), 
            IERC20(quoteToken), 
            "Test", 
            "TEST", 
            IVaultAuth(address(auth))
        );
    }

    // Test Line 165: Withdraw exceeding maxWithdraw
    function test_fail_withdraw_exceedsMax() public {
        // First deposit some assets
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(assets, alice);
        
        // Try to withdraw more than the user has
        uint256 maxWithdrawable = vault.maxWithdraw(alice);
        uint256 excessiveAmount = maxWithdrawable + 1;
        
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, excessiveAmount, maxWithdrawable));
        vm.prank(alice);
        vault.withdraw(excessiveAmount, alice, alice);
    }

    // Test Line 197: Redeem exceeding maxRedeem
    function test_fail_redeem_exceedsMax() public {
        // First deposit some assets
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        vault.deposit(assets, alice);
        
        // Try to redeem more shares than the user has
        uint256 maxRedeemable = vault.maxRedeem(alice);
        uint256 excessiveShares = maxRedeemable + 1;
        
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, alice, excessiveShares, maxRedeemable));
        vm.prank(alice);
        vault.redeem(excessiveShares, alice, alice);
    }

    // Test Line 236: Withdraw/redeem with allowance (caller != owner)
    function test_withdraw_withAllowance() public {
        // First deposit some assets as alice
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        
        // Give bob an allowance to withdraw on alice's behalf
        vm.prank(alice);
        vault.approve(bob, shares);
        
        // Bob withdraws on alice's behalf
        uint256 withdrawAmount = assets / 2;
        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, alice);
        
        // Check that the allowance was spent
        assertTrue(vault.allowance(alice, bob) < shares, "Allowance should be reduced");
    }

    function test_redeem_withAllowance() public {
        // First deposit some assets as alice
        uint256 assets = 100 * 10 ** vault.assetDecimals();
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        
        // Give bob an allowance to redeem on alice's behalf
        vm.prank(alice);
        vault.approve(bob, shares);
        
        // Bob redeems on alice's behalf
        uint256 redeemShares = shares / 2;
        vm.prank(bob);
        vault.redeem(redeemShares, bob, alice);
        
        // Check that the allowance was spent
        assertTrue(vault.allowance(alice, bob) < shares, "Allowance should be reduced");
    }

    // Test Line 325: returnQuoteToken when vault is not paused (should revert)
    function test_fail_returnQuoteToken_notPaused() public {
        // Vault should be unpaused initially
        assertFalse(vault.paused(), "Vault should not be paused");
        
        // Try to call returnQuoteToken when vault is not paused
        vm.expectRevert(IVault.VaultUnpaused.selector);
        vm.prank(admin);
        vault.returnQuoteToken(1000, 1 ether);
    }
}
