// SPDX-License-Identifier: LicenseRef-SkyAlpha-Proprietary
// © 2025 SkyAlpha Ventures LLC. All rights reserved. Use subject to LICENSE.txt.
// No claims against contributors: to the maximum extent permitted by applicable law, each contributor
// provides its contributions "AS IS", disclaims all warranties, and shall have no liability whatsoever
// for any damages arising from or relating to the Software or its use.

pragma solidity ^0.8.18;

import {ERC4626, ERC20} from "./ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "ajna-core/interfaces/pool/IPool.sol";
import {PoolInfoUtils} from "ajna-core/PoolInfoUtils.sol";

import { Maths } from "lib/ajna-core/src/libraries/internal/Maths.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Buffer} from "./Buffer.sol";
import {AjnaVaultLibrary as AVL} from "./AjnaVaultLibrary.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultAuth} from "./interfaces/IVaultAuth.sol";

contract Vault is IVault, ERC4626 {
    using SafeERC20 for IERC20;
    
    // CONSTANTS
    uint256 public constant WAD = 1e18;

    // IMMUTABLES
    IPool         public immutable POOL;
    PoolInfoUtils public immutable INFO;
    Buffer        public immutable BUFFER;
    IVaultAuth    public immutable AUTH;
    uint8         public immutable assetDecimals;
    uint256       public immutable LP_DUST;
    
    // STATE VARIABLES
    uint256[]                   public buckets;
    mapping(uint256 => uint256) public bucketsIndex; // (bucketIndex => index location in buckets)
    uint256                     public bufferLps;
    mapping(uint256 => uint256) public lps; // (bucketIndex => lps)
    uint8                       public bolt; // reentrancy lock: 0 = off, 1 = on
    uint256                     public removedCollateralValue;

    // MODIFIERS
    modifier lock() {
        if (bolt != 0) revert ReentrancyLockActive();
        bolt = 1;
        _;
        bolt = 0;
    }

    modifier notPaused() {
        if (_paused()) revert VaultPaused();
        _;
    }

    constructor(
        IPool _pool,
        address _sage,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        IVaultAuth _auth
    ) ERC20(_name, _symbol) ERC4626(_asset) {
        AUTH = _auth;

        POOL = _pool;
        if (POOL.quoteTokenAddress() != address(_asset)) {
            revert InvalidQuoteToken();
        }
        INFO = PoolInfoUtils(_sage);
        assetDecimals = ERC20(asset()).decimals();
        if (assetDecimals == 0 || assetDecimals > 18) revert InvalidAssetDecimals(assetDecimals);
        BUFFER = new Buffer(asset(), assetDecimals);

        LP_DUST = Math.max(WAD / (10**assetDecimals), 1e6 + 1);

        // Set up allowances for the Buffer and the pool
        IERC20(asset()).approve(address(BUFFER), type(uint256).max);
        IERC20(asset()).approve(address(POOL), type(uint256).max);
    }

    // EXTERNAL OVERRIDES
    function totalAssets() public view override returns (uint256 _sum) {
        _sum = BUFFER.lpToValue(bufferLps) + removedCollateralValue;
        for (uint256 i = 0; i < buckets.length; i++) {
            _sum += lpToValue(buckets[i]);
        }
        // Convert from WAD to underlying asset decimals for ERC4626 compliance
        _sum = _convertWadToAsset(_sum);
    }

    function decimals() public pure override returns (uint8) {
        // the vault is always 18 decimals
        // To get the asset decimals, use the assetDecimals()
        return 18;
    }
    
    /**
     * @notice Deposit assets into the vault
     * @param assets The amount of assets to deposit in underlying asset decimals
     * @param receiver The address to receive the shares
     * @return The amount of shares received
     */
    function deposit(uint256 assets, address receiver) public override lock notPaused returns (uint256) {
        POOL.updateInterest();
        
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }
 
        // Transfer full amount from user
        _transferAssetFrom(msg.sender, address(this), assets);
        
        // Calculate toll on the full assets amount
        (uint256 tollFee, uint256 netAssets) = _getFee(AUTH.toll(), assets);
        
        _sendFee(tollFee);

        uint256 shares = super.previewDeposit(netAssets); // use super.previewDeposit to get the shares without the toll
        
        // Deposit net assets after fee
        _deposit(msg.sender, receiver, netAssets, shares);

        return shares;
    }

    /**
     * @notice Mint shares from the vault
     * @param shares The amount of shares to mint in 18 decimals
     * @param receiver The address to receive the shares
     * @return The amount of shares received
     */
    function mint(uint256 shares, address receiver) public override lock notPaused returns (uint256) {    
        POOL.updateInterest();

        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = super.previewMint(shares); // use super.previewMint to get the assets without the toll

        // Calculate toll on the assets
        uint256 assetsWithToll = previewMint(shares);
        uint256 tollFee = assetsWithToll - assets;

        // Transfer full amount from user (includes toll)
        _transferAssetFrom(msg.sender, address(this), assetsWithToll);
        
        _sendFee(tollFee);

        _deposit(msg.sender, receiver, assets, shares);

        return assetsWithToll;
    }

    /**
     * @notice Withdraw assets from the vault
     * @param assets The amount of assets to withdraw in underlying asset decimals
     * @param receiver The address to receive the assets
     * @param owner The address of the owner of the shares
     * @return The amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) public override lock notPaused returns (uint256) {
        POOL.updateInterest();
        
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        
        // Calculate shares needed for assets (including tax)
        uint256 shares = previewWithdraw(assets);

        // Calculate tax on assets
        (uint256 taxFee,) = _getFee(AUTH.tax(), assets);

        // Burn shares and withdraw gross assets
        _withdraw(msg.sender, receiver, owner, assets + taxFee, shares);
        
        _sendFee(taxFee);
        
        // Send net assets to receiver
        _transferAssetFrom(address(this), receiver, assets);
        
        return shares;
    }

    /**
     * @notice Redeem shares from the vault
     * @param shares The amount of shares to redeem in 18 decimals
     * @param receiver The address to receive the assets
     * @param owner The address of the owner of the shares
     * @return The amount of net assets received by receiver
     */
    function redeem(uint256 shares, address receiver, address owner) public override lock notPaused returns (uint256) {
        POOL.updateInterest();
        
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        
        // Get gross assets for these shares
        uint256 grossAssets = super.previewRedeem(shares);
        (uint256 taxFee, uint256 assets) = _getFee(AUTH.tax(), grossAssets);
        
        // Burn shares and withdraw gross assets
        _withdraw(msg.sender, receiver, owner, grossAssets, shares);
        
        _sendFee(taxFee);
        
        // Send net assets to receiver
        _transferAssetFrom(address(this), receiver, assets);
        
        return assets;
    }

    // INTERNAL OVERRIDES
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        // Convert assets from underlying decimals to WAD for internal operations
        uint256 wadAssets = _convertAssetToWad(assets);
        
        // Move assets to the Buffer
        (uint256 _lps, /* _assets */) = BUFFER.addQuoteToken(wadAssets, 0, block.timestamp);

        _fill(address(BUFFER), 0, _lps);

        // Mint shares to the receiver
        _mint(receiver, shares);

        // Emit the deposit event with original asset amount in underlying decimals
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        // Check allowance
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Burn shares
        _burn(owner, shares);

        // Convert assets from underlying decimals to WAD for internal operations
        uint256 wadAssets = _convertAssetToWad(assets);

        // Move assets from the Buffer to the receiver
        (/* _assets */, uint256 _lps) = BUFFER.removeQuoteToken(wadAssets, 0);
        _wash(address(BUFFER), 0, _lps);

        // Emit with original asset amount in underlying decimals
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // ADMIN AND KEEPER FUNCTIONS
    function move(uint256 _fromIndex, uint256 _toIndex, uint256 _wad) external lock notPaused {
        (uint256 _fromLps, uint256 _toLps) = AVL.move(
            INFO,
            POOL,
            _fromIndex,
            _toIndex,
            _wad,
            AUTH
        );
        _wash(address(POOL), _fromIndex, _fromLps);
        _fill(address(POOL), _toIndex, _toLps);

        emit Move(msg.sender, address(POOL), _fromIndex, _toIndex, _wad);
    }

    // KEEPER FUNCTIONS  
    function moveFromBuffer(uint256 _toIndex, uint256 _wad) external lock notPaused {        
        (uint256 _fromLps, uint256 _toLps) = AVL.moveFromBuffer(
            INFO,
            AUTH,
            BUFFER,
            POOL,
            _toIndex,
            _wad
        );

        _wash(address(BUFFER), 0, _fromLps);
        _fill(address(POOL), _toIndex, _toLps);

        emit MoveFromBuffer(msg.sender, address(POOL), _toIndex, _wad);
    }

    function drain(uint256 _bucket) external lock notPaused {
        if (!AUTH.isAdminOrKeeper(msg.sender)) revert NotAuthorized();

        uint256 _lps = lps[_bucket];
        (uint256 _newLps, /* depositTime */) = POOL.lenderInfo(_bucket, address(this));

        if (_newLps >= _lps) return;

        lps[_bucket] = _newLps;

        emit Drain(msg.sender, _bucket, _lps, _newLps);
    }

    function moveToBuffer(uint256 _fromIndex, uint256 _wad) external lock notPaused {
        (uint256 _fromLps, uint256 _toLps) = AVL.moveToBuffer(
            AUTH,
            POOL,
            BUFFER,
            _fromIndex,
            _wad
        );
        _wash(address(POOL), _fromIndex, _fromLps);
        _fill(address(BUFFER), 0, _toLps);

        emit MoveToBuffer(msg.sender, address(POOL), _fromIndex, _wad);
    }

    // ADMIN and SWAPPER FUNCTIONS
    function recoverCollateral(uint256 _fromIndex, uint256 _amt) external notPaused {
        _onlyAdminOrSwapper();

        (uint256 colLps, address gem, uint256 gems, uint256 value) = AVL.recoverCollateral(
            INFO,
            POOL,
            _fromIndex,
            _amt
        );

        removedCollateralValue = value;
        
        _wash(address(POOL), _fromIndex, colLps);
        uint256 gemsToTransfer = AVL.convertWadToAsset(gems, ERC20(gem).decimals());
        IERC20(gem).safeTransfer(msg.sender, gemsToTransfer);

        emit RecoverCollateral(msg.sender, _fromIndex, _amt, colLps, value);
    }

    function returnQuoteToken(uint256 _toIndex, uint256 _amt) external {
        if (!_paused()) revert VaultUnpaused();
        _onlyAdminOrSwapper();

        removedCollateralValue = 0;
        
        _transferAssetFrom(msg.sender, address(this), _convertWadToAsset(_amt));

        (uint256 _lps) = AVL.returnQuoteToken(INFO, POOL, AUTH, _toIndex, _amt);

        _fill(address(POOL), _toIndex, _lps);

        emit ReturnQuoteToken(msg.sender, _toIndex, _amt, _lps);
    }

    // GETTERS
    function getBuckets() external view returns (uint256[] memory) {
        return buckets;
    }

    function pool() public view returns (address) {
        return address(POOL);
    }

    function buffer() public view returns (address) {
        return address(BUFFER);
    }

    function info() public view returns (address) {
        return address(INFO);
    }

    function lpToValue(uint256 _bucket) public view returns (uint256) {
        return AVL.lpToValue(INFO, POOL, _bucket, lps[_bucket]);
    }

    function paused() public view returns (bool) {
        return _paused();
    }

    function _paused() internal view returns (bool) {
        return AUTH.paused() || removedCollateralValue > 0;
    }

    function _onlyAdminOrSwapper() internal view {
        if (!AUTH.isAdminOrSwapper(msg.sender)) revert NotAuthorized();
    }

    function _convertAssetToWad(uint256 assets) internal view returns (uint256) {
        return AVL.convertAssetToWad(assets, assetDecimals);
    }

    function _convertWadToAsset(uint256 wadAssets) internal view returns (uint256) {
        return AVL.convertWadToAsset(wadAssets, assetDecimals);
    }

    function _transferAssetFrom(address from, address to, uint256 assetAmt) internal {
        AVL.transferTokenFrom(asset(), from, to, assetAmt);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (_paused()) return 0;
        
        uint256 cap = AUTH.depositCap();
        if (cap == 0) return super.maxDeposit(receiver);
        
        uint256 currentAssets = totalAssets();
        if (currentAssets >= cap) return 0;
        
        uint256 maxByCapacity = cap - currentAssets;
        uint256 maxBySuper = super.maxDeposit(receiver);
        return maxByCapacity < maxBySuper ? maxByCapacity : maxBySuper;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        if (_paused()) return 0;
        
        uint256 maxAssets = maxDeposit(receiver);
        // use super.previewDeposit to get the max shares without the toll
        return maxAssets == 0 ? 0 : super.previewDeposit(maxAssets);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (_paused()) return 0;
        return super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (_paused()) return 0;
        return super.maxRedeem(owner);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        if (_paused()) return 0;
        
        (, uint256 netAssets) = _getFee(AUTH.toll(), assets);
        
        return super.previewDeposit(netAssets);
    }
    
    function previewMint(uint256 shares) public view override returns (uint256) {
        if (_paused()) return 0;
        
        uint256 assetsWithToll = _getAssetsWithFee(AUTH.toll(), super.previewMint(shares));
        
        return assetsWithToll;
    }
    
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        if (_paused()) return 0;
        
        uint256 grossAssets = _getAssetsWithFee(AUTH.tax(), assets);
        
        return super.previewWithdraw(grossAssets);
    }
    
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        if (_paused()) return 0;
        
        uint256 grossAssets = super.previewRedeem(shares);
        (, uint256 netAssets) = _getFee(AUTH.tax(), grossAssets);
        
        return netAssets;
    }

    // Internal
    function _fill(address _pool, uint256 _bucket, uint256 _lps) internal {
        bufferLps = AVL.fill(_pool, address(BUFFER), _bucket, _lps, bufferLps, lps, buckets, bucketsIndex, LP_DUST);
    }

    function _wash(address _pool, uint256 _bucket, uint256 _lps) internal {
        bufferLps = AVL.wash(_pool, address(BUFFER), _bucket, _lps, bufferLps, lps, buckets, bucketsIndex, LP_DUST);
    }

    function _sendFee(uint256 _fee) internal {
        IERC20(asset()).safeTransfer(address(AUTH), _fee);
    }

    function _getFee(uint256 _fee, uint256 _assets) internal pure returns (uint256 feeAmt, uint256 netAmt) {
        feeAmt = (_fee * _assets) / 10000;
        netAmt = _assets - feeAmt;
    }

    function _getAssetsWithFee(uint256 _fee, uint256 _assets) internal pure returns (uint256 assetsWithFee) {
        assetsWithFee = (_assets * 10000) / (10000 - _fee);
    }
}
