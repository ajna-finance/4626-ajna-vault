// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "./erc4626-tests/ERC4626.test.sol";

import {PoolMockBurnableQT} from "./mocks/PoolMockBurnableQT.sol";
import {SageMock} from "./mocks/SageMock.sol";
import {MintBurnERC20} from "./mocks/MintBurnERC20.sol";
import {Vault} from "../src/Vault.sol";
import {VaultAuth} from "../src/VaultAuth.sol";

import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";

import {IERC20 as OZ_IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC4626StdTest is ERC4626Test {
    function setUp() public override {
        PoolInfoUtils info = PoolInfoUtils(address(new SageMock()));
        VaultAuth auth = new VaultAuth();
        address quoteToken = address(new MintBurnERC20());
        IPool pool = IPool(address(new PoolMockBurnableQT(quoteToken)));

        _underlying_ = quoteToken;
        _vault_ = address(new Vault(pool, address(info), OZ_IERC20(pool.quoteTokenAddress()), "Vault", "VAULT", VaultAuth(address(auth))));
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }
}
