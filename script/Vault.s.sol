// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or use.

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {VaultAuth} from "../src/VaultAuth.sol";
import {AjnaVaultLibrary} from "../src/AjnaVaultLibrary.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultScript is Script {
    // Deployed contracts
    VaultAuth public auth;
    Vault public vault;

    // Deployment parameters structure
    struct DeploymentConfig {
        address pool;           // Required: Ajna pool address
        address sage;           // Required: PoolInfoUtils address
        address asset;          // Required: Quote token address
        string name;            // Optional: Vault name
        string symbol;          // Optional: Vault symbol
        address admin;          // Optional: Admin address
        address swapper;        // Optional: Swapper address
        address[] keepers;      // Optional: Initial keepers
        uint256 depositCap;     // Optional: Deposit cap
        uint256 bufferRatio;    // Optional: Buffer ratio in bps
        uint256 toll;           // Optional: Deposit fee in bps
        uint256 tax;            // Optional: Withdraw fee in bps
        uint256 minBucketIndex; // Optional: Min bucket index
    }

    function setUp() public {}

    function run() public {
        // Get config file path from environment (required)
        string memory configPath = vm.envString("CONFIG_PATH");

        // Load and parse configuration
        DeploymentConfig memory config = _loadConfig(configPath);

        // Validate configuration
        _validateConfig(config);

        vm.startBroadcast();

        // Deploy the vault system
        _deploySystem(config);

        vm.stopBroadcast();

        // Log deployment results
        _logDeployment(config);
    }

    function _loadConfig(string memory configPath) internal view returns (DeploymentConfig memory config) {
        console.log("Loading configuration from:", configPath);

        // Read the JSON file
        string memory json = vm.readFile(configPath);

        // Parse required fields
        config.pool = vm.parseJsonAddress(json, ".pool");
        config.sage = vm.parseJsonAddress(json, ".sage");
        config.asset = vm.parseJsonAddress(json, ".asset");

        // Parse optional fields with defaults
        try vm.parseJsonString(json, ".name") returns (string memory name) {
            config.name = name;
        } catch {
            config.name = "Ajna Vault";
        }

        try vm.parseJsonString(json, ".symbol") returns (string memory symbol) {
            config.symbol = symbol;
        } catch {
            config.symbol = "ajnaVAULT";
        }

        try vm.parseJsonAddress(json, ".admin") returns (address admin) {
            config.admin = admin;
        } catch {
            config.admin = msg.sender;
        }

        try vm.parseJsonAddress(json, ".swapper") returns (address swapper) {
            config.swapper = swapper;
        } catch {
            config.swapper = address(0);
        }

        try vm.parseJsonAddressArray(json, ".keepers") returns (address[] memory keepers) {
            config.keepers = keepers;
        } catch {
            config.keepers = new address[](0);
        }

        try vm.parseJsonUint(json, ".depositCap") returns (uint256 depositCap) {
            config.depositCap = depositCap;
        } catch {
            config.depositCap = 0;
        }

        try vm.parseJsonUint(json, ".bufferRatio") returns (uint256 bufferRatio) {
            config.bufferRatio = bufferRatio;
        } catch {
            config.bufferRatio = 0;
        }

        try vm.parseJsonUint(json, ".toll") returns (uint256 toll) {
            config.toll = toll;
        } catch {
            config.toll = 0;
        }

        try vm.parseJsonUint(json, ".tax") returns (uint256 tax) {
            config.tax = tax;
        } catch {
            config.tax = 0;
        }

        try vm.parseJsonUint(json, ".minBucketIndex") returns (uint256 minBucketIndex) {
            config.minBucketIndex = minBucketIndex;
        } catch {
            config.minBucketIndex = 0;
        }

        console.log("Configuration loaded successfully");
    }

    function _validateConfig(DeploymentConfig memory config) internal view {
        require(config.pool != address(0), "Pool address is required");
        require(config.sage != address(0), "Sage address is required");
        require(config.asset != address(0), "Asset address is required");
        require(config.admin != address(0), "Admin address cannot be zero");

        // Validate pool and asset compatibility
        address poolQuoteToken = IPool(config.pool).quoteTokenAddress();
        require(poolQuoteToken == config.asset, "Pool quote token must match asset");

        // Validate fee parameters (max 10% each)
        require(config.toll <= 1000, "Toll cannot exceed 10% (1000 bps)");
        require(config.tax <= 1000, "Tax cannot exceed 10% (1000 bps)");
        require(config.bufferRatio <= 10000, "Buffer ratio cannot exceed 100% (10000 bps)");

        // Validate asset is a proper ERC20
        try ERC20(config.asset).decimals() returns (uint8 decimals) {
            require(decimals > 0 && decimals <= 18, "Asset decimals must be 1-18");
        } catch {
            revert("Asset must be a valid ERC20 token");
        }

        console.log("All parameters validated");
    }

    function _deploySystem(DeploymentConfig memory config) internal {
        console.log("Deploying Vault system...");
        console.log("Deployer:", msg.sender);
        console.log("Admin:", config.admin);

        // 1. Deploy VaultAuth (msg.sender becomes admin automatically)
        console.log("Deploying VaultAuth...");
        auth = new VaultAuth();
        console.log("VaultAuth deployed at:", address(auth));

        // 2. Deploy Vault (this will automatically deploy Buffer internally)
        console.log("Deploying Vault...");
        vault = new Vault(
            IPool(config.pool),
            config.sage,
            IERC20(config.asset),
            config.name,
            config.symbol,
            auth
        );
        console.log("Vault deployed at:", address(vault));
        console.log("Buffer deployed at:", vault.buffer());

        // 3. Configure VaultAuth (deployer starts as admin)
        _configureAuth(config);

        // 4. Transfer admin rights if different from deployer
        if (config.admin != msg.sender) {
            console.log("Transferring admin rights from", msg.sender, "to", config.admin);
            auth.setAdmin(config.admin);
            console.log("Admin rights transferred successfully");
        }
    }

    function _configureAuth(DeploymentConfig memory config) internal {
        console.log("Configuring VaultAuth...");

        // Set swapper if provided
        if (config.swapper != address(0)) {
            console.log("Setting swapper:", config.swapper);
            auth.setSwapper(config.swapper);
        }

        // Set keepers
        for (uint256 i = 0; i < config.keepers.length; i++) {
            console.log("Setting keeper:", config.keepers[i]);
            auth.setKeeper(config.keepers[i], true);
        }

        // Set configuration parameters
        if (config.depositCap > 0) {
            console.log("Setting deposit cap:", config.depositCap);
            auth.setDepositCap(config.depositCap);
        }

        if (config.bufferRatio > 0) {
            console.log("Setting buffer ratio:", config.bufferRatio, "bps");
            auth.setBufferRatio(config.bufferRatio);
        }

        if (config.toll > 0) {
            console.log("Setting toll (deposit fee):", config.toll, "bps");
            auth.setToll(config.toll);
        }

        if (config.tax > 0) {
            console.log("Setting tax (withdraw fee):", config.tax, "bps");
            auth.setTax(config.tax);
        }

        if (config.minBucketIndex > 0) {
            console.log("Setting min bucket index:", config.minBucketIndex);
            auth.setMinBucketIndex(config.minBucketIndex);
        }
    }

    function _logDeployment(DeploymentConfig memory config) internal view {
        console.log("\n==========================================================");
        console.log("VAULT SYSTEM DEPLOYMENT COMPLETE");
        console.log("==========================================================");

        console.log("CONTRACTS:");
        console.log("  VaultAuth:", address(auth));
        console.log("  Vault:    ", address(vault));
        console.log("  Buffer:   ", vault.buffer());

        console.log("\nCONFIGURATION:");
        console.log("  Pool:     ", config.pool);
        console.log("  Sage:     ", config.sage);
        console.log("  Asset:    ", config.asset);
        console.log("  Name:     ", config.name);
        console.log("  Symbol:   ", config.symbol);
        console.log("  Admin:    ", config.admin);

        if (config.swapper != address(0)) {
            console.log("  Swapper:  ", config.swapper);
        }

        if (config.keepers.length > 0) {
            console.log("  Keepers:  ");
            for (uint256 i = 0; i < config.keepers.length; i++) {
                console.log("    -", config.keepers[i]);
            }
        }

        if (config.depositCap > 0) {
            console.log("  Deposit Cap:", config.depositCap);
        }

        if (config.bufferRatio > 0) {
            console.log("  Buffer Ratio:", config.bufferRatio, "bps");
        }

        if (config.toll > 0) {
            console.log("  Toll (deposit fee):", config.toll, "bps");
        }

        if (config.tax > 0) {
            console.log("  Tax (withdraw fee):", config.tax, "bps");
        }

        if (config.minBucketIndex > 0) {
            console.log("  Min Bucket Index:", config.minBucketIndex);
        }

        console.log("==========================================================");
    }
}

/**
 * @title Vault Deployment Script
 * @notice Deploys the complete Ajna Vault system using JSON configuration
 *
 * @dev Configuration File Format (config/vault-config.json):
 * {
 *   "pool": "0x123...",           // Required: Ajna pool address
 *   "sage": "0x456...",           // Required: PoolInfoUtils address
 *   "asset": "0x789...",          // Required: Quote token address
 *   "name": "My Ajna Vault",      // Optional: Vault name
 *   "symbol": "MAV",              // Optional: Vault symbol
 *   "admin": "0xabc...",          // Optional: Admin address (default: msg.sender)
 *   "swapper": "0xdef...",        // Optional: Swapper address
 *   "keepers": [                  // Optional: Array of keeper addresses
 *     "0x111...",
 *     "0x222..."
 *   ],
 *   "depositCap": "1000000000000000000000000",  // Optional: Max deposit (in wei)
 *   "bufferRatio": 1000,          // Optional: Buffer ratio (1000 = 10%)
 *   "toll": 50,                   // Optional: Deposit fee (50 = 0.5%)
 *   "tax": 25,                    // Optional: Withdraw fee (25 = 0.25%)
 *   "minBucketIndex": 2000        // Optional: Min bucket index for moves
 * }
 *
 * @dev Example Usage:
 *   # Deploy with specific config file (CONFIG_PATH is required)
 *   CONFIG_PATH=config/vault-config.json forge script script/Vault.s.sol --broadcast
 *
 *   # Deploy to mainnet
 *   CONFIG_PATH=config/mainnet-vault.json forge script script/Vault.s.sol --broadcast
 *
 *   # Deploy to testnet with verification
 *   CONFIG_PATH=config/testnet-vault.json forge script script/Vault.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
 */