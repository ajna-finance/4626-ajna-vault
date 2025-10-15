// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.
pragma solidity ^0.8.18;

// Proof of concept and bug identified by 
// https://github.com/imbaniac

import {Test, console} from "forge-std/Test.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Vault} from "../src/Vault.sol";
import {VaultAuth, IVaultAuth} from "../src/VaultAuth.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {PoolMock} from "./mocks/PoolMock.sol";
import {SageMock} from "./mocks/SageMock.sol";

/**
 * @title Vault Share Decimals Bug - Proof of Concept
 * @notice Single file demonstrating the critical bug in vault share calculation for non-18 decimal assets
 *
 * THE BUG:
 * - USDC vault (6 decimals) returns shares in 6 decimals instead of 18
 * - Vault.decimals() claims 18, but shares are actually in asset decimals
 * - UI displays 0.000000495 instead of 495 for a 500 USDC deposit
 *
 * ROOT CAUSE:
 * - Vault doesn't override _decimalsOffset(), defaults to 0
 * - ERC4626 formula: shares = assets * (totalSupply + 10^offset) / (totalAssets + 1)
 * - With offset=0, no scaling from 6 decimals to 18 decimals
 *
 * THE FIX:
 * Add to Vault.sol:
 *   function _decimalsOffset() internal view override returns (uint8) {
 *       return 18 - assetDecimals;
 *   }
 *
 * RUN: forge test --match-contract VaultShareDecimalsBugProof -vv
 */

// ============================================================================
// Tests
// ============================================================================

contract VaultShareDecimalsBugProof is Test {
    uint256 public constant WAD = 10 ** 18;
    uint256 public constant TOLL = 100; // 1%

    address public alice = makeAddr("alice");

    Vault public vaultUSDC;
    Vault public vaultDAI;
    VaultAuth public auth;
    MockERC20 public usdc;
    MockERC20 public dai;

    function setUp() public {
        // Create tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdcCollateral = new MockERC20("USDC Collateral", "USDCC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        MockERC20 daiCollateral = new MockERC20("DAI Collateral", "DAIC", 18);

        // Create pools
        PoolMock poolUSDC = new PoolMock(address(usdc), address(usdcCollateral));
        PoolMock poolDAI = new PoolMock(address(dai), address(daiCollateral));

        // Create auth and info
        auth = new VaultAuth();
        auth.setToll(TOLL);
        PoolInfoUtils info = PoolInfoUtils(address(new SageMock()));

        // Create vaults
        vaultUSDC = new Vault(
            IPool(address(poolUSDC)),
            address(info),
            IERC20(address(usdc)),
            "USDC Vault",
            "vUSDC",
            IVaultAuth(address(auth))
        );

        vaultDAI = new Vault(
            IPool(address(poolDAI)),
            address(info),
            IERC20(address(dai)),
            "DAI Vault",
            "vDAI",
            IVaultAuth(address(auth))
        );

        // Setup alice
        usdc.mint(alice, 1000 * 10**6);
        dai.mint(alice, 1000 * 10**18);

        vm.startPrank(alice);
        usdc.approve(address(vaultUSDC), type(uint256).max);
        dai.approve(address(vaultDAI), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice MAIN TEST - Demonstrates the bug with side-by-side comparison
     */
    function test_BugProof_USDCvsDAI() public view {
        uint256 usdcDeposit = 500 * 10**6;   // 500 USDC (6 decimals)
        uint256 daiDeposit = 500 * 10**18;   // 500 DAI (18 decimals)

        uint256 usdcShares = vaultUSDC.previewDeposit(usdcDeposit);
        uint256 daiShares = vaultDAI.previewDeposit(daiDeposit);

        console.log("========================================");
        console.log("VAULT SHARE DECIMALS BUG - PROOF");
        console.log("========================================");
        console.log("");
        console.log("Depositing 500 tokens into each vault:");
        console.log("");
        console.log("USDC Vault (6 decimal asset):");
        console.log("  decimals():          ", vaultUSDC.decimals(), " (claims 18)");
        console.log("  Shares received:     ", usdcShares);
        console.log("  UI displays:         ", usdcShares / 1e18, " (WRONG!)");
        console.log("  Expected display:     495");
        console.log("");
        console.log("DAI Vault (18 decimal asset):");
        console.log("  decimals():          ", vaultDAI.decimals());
        console.log("  Shares received:     ", daiShares);
        console.log("  UI displays:         ", daiShares / 1e18, " (correct)");
        console.log("  Expected display:     495");
        console.log("");
        console.log("THE BUG:");
        console.log("  USDC shares are in 6 decimals:", usdcShares);
        console.log("  But vault claims 18 decimals");
        console.log("  UI divides by 1e18, showing:", usdcShares / 1e18);
        console.log("");
        console.log("ROOT CAUSE:");
        console.log("  Vault doesn't override _decimalsOffset()");
        console.log("  Defaults to 0, providing no decimal scaling");
        console.log("");
        console.log("THE FIX:");
        console.log("  Override _decimalsOffset() to return (18 - assetDecimals)");
        console.log("========================================");

        // Assertions proving the bug
        assertEq(vaultUSDC.decimals(), 18, "USDC vault claims 18 decimals");
        assertEq(vaultDAI.decimals(), 18, "DAI vault claims 18 decimals");

        // DAI works correctly - shares in 18 decimals
        assertGt(daiShares, 400 * 10**18, "DAI: Shares correctly in 18 decimals");

        // USDC is broken - shares in 6 decimals (this will FAIL)
        assertGt(usdcShares, 400 * 10**18, "BUG: USDC shares should be in 18 decimals but are in 6!");
    }

    /**
     * @notice Shows exact numbers for USDC bug
     */
    function test_BugProof_USDCNumbers() public view {
        uint256 depositAmount = 500 * 10**6; // 500 USDC
        uint256 shares = vaultUSDC.previewDeposit(depositAmount);

        console.log("========================================");
        console.log("USDC VAULT - EXACT NUMBERS");
        console.log("========================================");
        console.log("Deposit:                  500 USDC");
        console.log("Deposit amount:          ", depositAmount, " (500 * 10^6)");
        console.log("After 1% toll:            495 USDC");
        console.log("");
        console.log("Shares received:         ", shares);
        console.log("Expected shares:          495000000000000000000 (495 * 10^18)");
        console.log("Actual shares:           ", shares, " (495 * 10^6)");
        console.log("");
        console.log("Vault decimals():        ", vaultUSDC.decimals());
        console.log("UI calculation:           shares / 10^18");
        console.log("UI displays:             ", shares / 1e18);
        console.log("Should display:           495");
        console.log("========================================");

        assertEq(shares, 495 * 10**18, "Shares are in 18 decimals (proving the bug is fixed)");
    }

    /**
     * @notice Shows the formula breakdown
     */
    function test_BugProof_FormulaBreakdown() public view {
        console.log("========================================");
        console.log("ERC4626 FORMULA BREAKDOWN");
        console.log("========================================");
        console.log("");
        console.log("Formula: shares = assets * (totalSupply + 10^offset) / (totalAssets + 1)");
        console.log("");
        console.log("For USDC vault (6 decimals):");
        console.log("  assets:              500000000 (500 * 10^6)");
        console.log("  totalSupply:         0");
        console.log("  totalAssets:         0");
        console.log("  _decimalsOffset:     0 (BUG!)");
        console.log("  10^offset:           1");
        console.log("");
        console.log("Calculation:");
        console.log("  shares = 500000000 * (0 + 1) / (0 + 1)");
        console.log("  shares = 500000000 * 1");
        console.log("  shares = 500000000 (only 6 decimals!)");
        console.log("");
        console.log("With correct offset = 12:");
        console.log("  10^offset:           1000000000000");
        console.log("  shares = 500000000 * 1000000000000 / 1");
        console.log("  shares = 500000000000000000000 (correct 18 decimals!)");
        console.log("========================================");
    }
}