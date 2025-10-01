// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {VaultAuth} from "../src/VaultAuth.sol";
import {VaultScript} from "../script/Vault.s.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PoolMock} from "./mocks/PoolMock.sol";
import {SageMock} from "./mocks/SageMock.sol";

contract VaultDeployTest is Test {
    address public deployer = makeAddr("deployer");

    function setUp() public {
        // Clear environment between tests
        vm.setEnv("CONFIG_PATH", "");
    }

    function test_deployWithMinimalConfig() public {
        VaultScript script = new VaultScript();

        // Deploy a real mock ERC20 token
        ERC20 mockAsset = new ERC20("Mock Asset", "MOCK");

        // Set up mocks to match the addresses in our config file but use real asset
        address poolAddr = address(0x1111111111111111111111111111111111111111);
        address sageAddr = address(0x2222222222222222222222222222222222222222);
        address configAssetAddr = address(0x3333333333333333333333333333333333333333);

        // Mock the pool's quoteTokenAddress to return the config asset address
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("quoteTokenAddress()"),
            abi.encode(configAssetAddr)
        );

        // Mock the pool's updateInterest call
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("updateInterest()"),
            abi.encode()
        );

        // Mock the config asset address to return our real asset's properties
        vm.etch(configAssetAddr, address(mockAsset).code);
        vm.mockCall(
            configAssetAddr,
            abi.encodeWithSignature("decimals()"),
            abi.encode(mockAsset.decimals())
        );

        // Use the minimal config file
        vm.setEnv("CONFIG_PATH", "test/mocks/vault-config-minimal.json");

        script.run();

        // Verify contracts were deployed
        VaultAuth deployedAuth = script.auth();
        Vault deployedVault = script.vault();

        assertTrue(address(deployedAuth) != address(0), "VaultAuth should be deployed");
        assertTrue(address(deployedVault) != address(0), "Vault should be deployed");

        // Verify auth configuration (admin should be the script msg.sender)
        // The admin should be the deployer from the script context
        assertTrue(deployedAuth.admin() != address(0), "Admin should be set");
        assertEq(deployedVault.name(), "Ajna Vault", "Default name should be used");
        assertEq(deployedVault.symbol(), "ajnaVAULT", "Default symbol should be used");
    }

    function test_deployWithFullConfig() public {
        VaultScript script = new VaultScript();

        // Deploy a real mock ERC20 token
        ERC20 mockAsset = new ERC20("Mock Asset", "MOCK");

        // Set up mocks to match the addresses in our config file
        address poolAddr = address(0x1111111111111111111111111111111111111111);
        address configAssetAddr = address(0x3333333333333333333333333333333333333333);

        // Mock the pool's quoteTokenAddress to return the config asset address
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("quoteTokenAddress()"),
            abi.encode(configAssetAddr)
        );

        // Mock the pool's updateInterest call
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("updateInterest()"),
            abi.encode()
        );

        // Mock the config asset address to return our real asset's properties
        vm.etch(configAssetAddr, address(mockAsset).code);
        vm.mockCall(
            configAssetAddr,
            abi.encodeWithSignature("decimals()"),
            abi.encode(mockAsset.decimals())
        );

        // Use the full config file
        vm.setEnv("CONFIG_PATH", "test/mocks/vault-config-full.json");

        script.run();

        // Verify contracts were deployed
        VaultAuth deployedAuth = script.auth();
        Vault deployedVault = script.vault();

        // Verify auth was transferred to configured admin
        assertEq(deployedAuth.admin(), address(0x4444444444444444444444444444444444444444), "Admin should be transferred");
        assertEq(deployedVault.name(), "Test Vault", "Custom name should be used");
        assertEq(deployedVault.symbol(), "TEST", "Custom symbol should be used");

        // Verify swapper was set
        assertTrue(deployedAuth.isSwapper(address(0x5555555555555555555555555555555555555555)), "Swapper should be configured");

        // Verify keepers were set
        assertTrue(deployedAuth.isKeeper(address(0x6666666666666666666666666666666666666666)), "Keeper1 should be configured");
        assertTrue(deployedAuth.isKeeper(address(0x7777777777777777777777777777777777777777)), "Keeper2 should be configured");

        // Verify parameters were set
        assertEq(deployedAuth.depositCap(), 1000 ether, "Deposit cap should be set");
        assertEq(deployedAuth.bufferRatio(), 1000, "Buffer ratio should be set");
        assertEq(deployedAuth.toll(), 50, "Toll should be set");
        assertEq(deployedAuth.tax(), 25, "Tax should be set");
        assertEq(deployedAuth.minBucketIndex(), 2000, "Min bucket index should be set");
    }

    function test_failsWithExcessiveFees() public {
        VaultScript script = new VaultScript();

        // Deploy a real mock ERC20 token
        ERC20 mockAsset = new ERC20("Mock Asset", "MOCK");

        // Set up mocks for the config with excessive fees
        address poolAddr = address(0x1111111111111111111111111111111111111111);
        address configAssetAddr = address(0x3333333333333333333333333333333333333333);

        // Mock the pool's quoteTokenAddress to return the config asset address
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("quoteTokenAddress()"),
            abi.encode(configAssetAddr)
        );

        // Mock the config asset address to return our real asset's properties
        vm.etch(configAssetAddr, address(mockAsset).code);
        vm.mockCall(
            configAssetAddr,
            abi.encodeWithSignature("decimals()"),
            abi.encode(mockAsset.decimals())
        );

        // Use the invalid fees config file
        vm.setEnv("CONFIG_PATH", "test/mocks/vault-config-invalid-fees.json");

        vm.expectRevert("Toll cannot exceed 10% (1000 bps)");
        script.run();
    }

    function test_failsWithoutConfigPath() public {
        VaultScript script = new VaultScript();

        // Clear CONFIG_PATH environment variable
        vm.setEnv("CONFIG_PATH", "");

        vm.expectRevert();
        script.run();
    }

    function test_failsWithInvalidConfigPath() public {
        VaultScript script = new VaultScript();

        vm.setEnv("CONFIG_PATH", "non-existent-file.json");

        vm.expectRevert();
        script.run();
    }

    function test_bufferDeployedAutomatically() public {
        VaultScript script = new VaultScript();

        // Deploy a real mock ERC20 token
        ERC20 mockAsset = new ERC20("Mock Asset", "MOCK");

        // Set up mocks
        address poolAddr = address(0x1111111111111111111111111111111111111111);
        address configAssetAddr = address(0x3333333333333333333333333333333333333333);

        // Mock the pool's quoteTokenAddress to return the config asset address
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("quoteTokenAddress()"),
            abi.encode(configAssetAddr)
        );

        // Mock the pool's updateInterest call
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("updateInterest()"),
            abi.encode()
        );

        // Mock the config asset address to return our real asset's properties
        vm.etch(configAssetAddr, address(mockAsset).code);
        vm.mockCall(
            configAssetAddr,
            abi.encodeWithSignature("decimals()"),
            abi.encode(mockAsset.decimals())
        );

        vm.setEnv("CONFIG_PATH", "test/mocks/vault-config-minimal.json");

        script.run();

        Vault deployedVault = script.vault();
        address bufferAddress = deployedVault.buffer();

        assertTrue(bufferAddress != address(0), "Buffer should be deployed");
        assertGt(bufferAddress.code.length, 0, "Buffer should have code deployed");
    }

    function _setupMocksForConfig(address poolAddr, address sageAddr, address assetAddr) internal {
        // Mock the pool's quoteTokenAddress to return the asset
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("quoteTokenAddress()"),
            abi.encode(assetAddr)
        );

        // Mock the asset's decimals
        vm.mockCall(
            assetAddr,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(18))
        );

        // Mock any other necessary calls for the pool and sage
        vm.mockCall(
            poolAddr,
            abi.encodeWithSignature("updateInterest()"),
            abi.encode()
        );
    }
}