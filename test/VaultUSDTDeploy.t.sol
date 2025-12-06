// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Buffer} from "../src/Buffer.sol";
import {IBuffer} from "../src/interfaces/IBuffer.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {VaultAuth, IVaultAuth} from "../src/VaultAuth.sol";
import {ERC4626} from "../src/ERC4626.sol";

/**
 * @title VaultUSDTDeployTest
 * @notice Test to reproduce USDT vault deployment failure on mainnet fork
 * @dev This test uses mainnet fork to test deployment with:
 *      - USDT (0xdac17f958d2ee523a2206206994597c13d831ec7) as quote token
 *      - wstETH/USDT pool (0xd7fef7e3ac0440086f6322dc47d72e6c96caa6ca) as underlying pool
 */
contract VaultUSDTDeployTest is Test {

    // Mainnet addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WSTETH_USDT_POOL = 0xD7feF7E3aC0440086f6322dC47d72E6C96caA6cA;
    address public constant AJNA_INFO = 0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE;

    // Test actors
    address public deployer = makeAddr("deployer");

    // Contracts
    Vault public vault;
    VaultAuth public auth;
    Buffer public buffer;
    IPool public pool;
    PoolInfoUtils public info;

    function setUp() public {
        // Fork mainnet at a recent block
        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(rpcUrl);

        console.log("=== Forked Mainnet ===");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log("");

        pool = IPool(WSTETH_USDT_POOL);
        info = PoolInfoUtils(AJNA_INFO);

        console.log("=== Pool Information ===");
        console.log("Pool address:", address(pool));
        console.log("Quote token from pool:", pool.quoteTokenAddress());
        console.log("Expected USDT address:", USDT);
        console.log("Quote token matches USDT:", pool.quoteTokenAddress() == USDT);
        console.log("");

        console.log("=== USDT Information ===");
        console.log("USDT decimals:", ERC20(USDT).decimals());
        console.log("USDT name:", ERC20(USDT).name());
        console.log("USDT symbol:", ERC20(USDT).symbol());
        console.log("");
    }

    function test_deployVaultWithUSDT() public {
        console.log("=== Attempting to Deploy Vault with USDT ===");

        vm.startPrank(deployer);

        // Deploy VaultAuth
        console.log("Deploying VaultAuth...");
        auth = new VaultAuth();
        console.log("VaultAuth deployed at:", address(auth));
        console.log("");

        // Attempt to deploy Vault with USDT
        console.log("Deploying Vault...");
        console.log("Pool:", address(pool));
        console.log("Info:", address(info));
        console.log("Asset (USDT):", USDT);
        console.log("Auth:", address(auth));
        console.log("");

        // This should fail or expose the issue
        try this.deployVault() returns (Vault v) {
            vault = v;
            console.log("SUCCESS: Vault deployed at:", address(vault));
            console.log("Vault asset:", vault.asset());
            console.log("Vault decimals:", vault.decimals());
            console.log("Vault assetDecimals:", vault.assetDecimals());
            console.log("Vault buffer:", vault.buffer());
        } catch Error(string memory reason) {
            console.log("FAILED: Deployment reverted with reason:");
            console.log(reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED: Deployment reverted with low-level error");
            console.logBytes(lowLevelData);
            revert("Deployment failed with low-level error");
        }

        vm.stopPrank();
    }

    // External function to enable try/catch
    function deployVault() external returns (Vault) {
        return new Vault(
            pool,
            address(info),
            IERC20(USDT),
            "USDT Vault",
            "vUSDT",
            IVaultAuth(address(auth))
        );
    }
}
