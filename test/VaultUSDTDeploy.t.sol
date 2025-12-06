// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import "./Vault.base.t.sol";

/**
 * @title VaultUSDTDeployTest
 * @notice Test to reproduce USDT vault deployment failure on mainnet fork
 * @dev This test uses mainnet fork to test deployment with:
 *      - USDT (0xdac17f958d2ee523a2206206994597c13d831ec7) as quote token
 *      - wstETH/USDT pool (0xd7fef7e3ac0440086f6322dc47d72e6c96caa6ca) as underlying pool
 */
contract VaultUSDTDeployTest is VaultBaseTest {

    // Mainnet addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WSTETH_USDT_POOL = 0xD7feF7E3aC0440086f6322dC47d72E6C96caA6cA;

    // Test actors
    address public deployer = makeAddr("deployer");

    function setUp() public override {
        // Create fork at specific block for USDT pool
        try vm.envString("ETH_RPC_URL") returns (string memory rpcUrl) {
            vm.createSelectFork(rpcUrl, 23955000);
            liveFork = true;

            pool = IPool(WSTETH_USDT_POOL);
            info = PoolInfoUtils(AJNA_INFO);
        } catch {
            liveFork = false;
        }
    }

    function test_deployVaultWithUSDT() public onlyLiveFork {

        vm.startPrank(deployer);

        // Deploy VaultAuth
        auth = new VaultAuth();

        // This should fail or expose the issue
        try this.deployVault() returns (Vault v) {
            vault = v;
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
