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
import {IVault} from "../src/interfaces/IVault.sol";
import {VaultAuth, IVaultAuth} from "../src/VaultAuth.sol";
import {ERC4626} from "../src/ERC4626.sol";

import {PoolMock} from "./mocks/PoolMock.sol";
import {SageMock} from "./mocks/SageMock.sol";

abstract contract VaultBaseTest is Test {
    
    uint256 public constant WAD = 10 ** 18;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD / 2) / WAD;
    }
    
    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public keeper  = makeAddr("keeper");
    address public admin   = makeAddr("admin");
    address public swapper = makeAddr("swapper");

    // Fork testing info
    bool    public liveFork;
    uint256 public forkBlock = 23119641;
    address public constant sUSDe_DAI_POOL = 0x34bC3D3d274A355f3404c5dEe2a96335540234de;
    address public constant AJNA_INFO = 0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE;

    Vault         public vault;
    VaultAuth     public auth;
    Buffer        public buffer;
    IPool         public pool;
    PoolInfoUtils public info;

    modifier onlyLiveFork() {
        if (!liveFork) {
            console.log("Advanced tests not enabled - Live fork not enabled");
            return;
        }
        _;
    }

    function setUp() public virtual {
        try vm.envString("ETH_RPC_URL") returns (string memory rpcUrl) {
            vm.createSelectFork(rpcUrl, forkBlock);
            pool = IPool(sUSDe_DAI_POOL);
            info = PoolInfoUtils(AJNA_INFO);
            liveFork = true;
            console.log("Advanced tests enabled with fork");
            console.log("block.timestamp", block.timestamp);
            console.log();
        } catch {
            pool = IPool(address(new PoolMock()));
            info = PoolInfoUtils(address(new SageMock()));
            console.log("block.timestamp", block.timestamp);
        }
        
        auth = new VaultAuth();
        vault = new Vault(pool, address(info), IERC20(pool.quoteTokenAddress()), "Vault", "VAULT", IVaultAuth(address(auth)));
        buffer = Buffer(vault.buffer());

        vm.startPrank(alice);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
        vm.stopPrank();

        deal(vault.asset(), alice, 1000 ether);
        deal(vault.asset(), bob, 1000 ether);

        // Transfer admin rights to test admin and configure
        auth.setAdmin(admin);
        vm.startPrank(admin);
        auth.setSwapper(swapper);
        auth.setKeeper(keeper, true);
        vm.stopPrank();
    }

    function _calculateBufferTarget(uint256 _totalAssets) internal pure returns (uint256) {
        // TODO replace with the configurable buffer ratio when admin is added
        return (_totalAssets * 1000) / 10000;
    }

    function _calculatePoolTarget(uint256 _totalAssets) internal pure returns (uint256) {
        // TODO replace with the configurable pool ratio when admin is added
        return (_totalAssets * 9000) / 10000;
    }
}