# Vault & IVault API Reference
The `Vault` and `IVault` interface explain how the Ajna ERC-4626 Vault works and how to use it. It lists every callable function with purpose, inputs/outputs, and notes, plus a quick guide to errors, events, and the safety modifiers that gate actions. The ERC-4626 entry points (`totalAssets`, `decimals`, `deposit/mint`, `withdraw/redeem`) are also described so integrators can build against the vault with predictable behavior.

## Errors

| **Name** | **When it fires** | **Impact / Next steps** |
|----------|-------------------|--------------------------|
| `InvalidQuoteToken()` | Quote token doesn’t match vault’s configured asset. | Ensure the asset passed matches the vault’s `asset()`. |
| `ReentrancyLockActive()` | A function is called while the vault’s lock is active. | Prevents nested calls; retry once the lock is released. |
| `InvalidDeposit()` | Deposit is zero or otherwise fails validation. | Provide a valid non-zero deposit amount. |
| `InvalidAssetDecimals(uint8 decimals)` | Token decimals don’t match vault expectations. | Confirm correct ERC-20 asset is being used. |
| `DustyBucket(address pool, uint256 bucket)` | Operation would leave/create LP below `LP_DUST`. | Choose a bucket/amount large enough to avoid dust. |
| `FundsNotAvailable()` | Buffer lacks funds to cover withdraw/redeem/return. | Wait for a keeper to refill Buffer or reduce request. |
| `ZeroAddress()` | Operation attempted with a zero address. | Provide a valid non-zero address. |
| `NotAuthorized()` | Caller lacks required role. | Call must be from admin, keeper, or swapper as appropriate. |
| `VaultUnpaused()` | Action requires vault paused but it is active. | Pause vault first before retrying (admin only). |
| `VaultPaused()` | Action requires vault unpaused but it is paused. | Unpause vault (admin) or wait until collateral cycle is cleared. |
| `RemovedCollateralValueNotZero()` | Collateral recovery still active. | Complete `returnQuoteToken` flow before retrying. |
| `DepositCapExceeded()` | Deposit/mint would exceed cap. | Reduce amount or wait until cap is raised by admin. |
| `BufferRatioExceeded()` | Move would breach buffer ratio limits. | Adjust move size or parameters to respect configured ratio. |
| `BucketLPDangerous(address pool, uint256 bucket, uint256 bucketLP)` | Target bucket in unsafe LP state. | Select a different bucket or wait until state normalizes. |
| `BucketIndexTooLow(address pool, uint256 bucket, uint256 minBucketIndex)` | Attempted move below `minBucketIndex`. | Choose a bucket ≥ `minBucketIndex`. |

## Events

| **Name** | **When it fires** | **Impact / Next steps** |
|----------|-------------------|--------------------------|
| `MoveFromBuffer(address caller, address pool, uint256 bucket, uint256 amount)` | Liquidity moved from Buffer → Ajna bucket. | Track keeper rebalancing into pool. |
| `MoveToBuffer(address caller, address pool, uint256 bucket, uint256 amount)` | Liquidity moved from bucket → Buffer. | Monitor Buffer replenishment. |
| `Move(address caller, address pool, uint256 fromBucket, uint256 toBucket, uint256 amount)` | Liquidity reallocated between buckets. | Useful for yield optimization reporting. |
| `SetAdmin(address newAdmin)` | Admin role reassigned. | Update operator dashboards/permissions. |
| `RecoverCollateral(address caller, uint256 bucket, uint256 amount, uint256 lps, uint256 value)` | Collateral pulled from Ajna bucket into vault (pauses vault). | Signals entry into recovery mode; withdrawals disabled until resolved. |
| `ReturnQuoteToken(address caller, uint256 bucket, uint256 amount, uint256 lps)` | Collateral returned and vault unpaused. | End of recovery cycle; vault resumes normal ops. |
| `SetSwapper(address newSwapper)` | Swapper role updated. | Update operator permissions. |
| `KeeperSet(address keeper, bool isKeeper)` | Keeper role added/removed. | Update keeper infrastructure accordingly. |
| `Paused()` | Vault paused by admin. | Alert integrators: deposits/withdrawals disabled. |
| `Unpaused()` | Vault resumed by admin. | Vault back to normal operation. |

## Modifiers

- `lock()` - A reentrancy guard that prevents a function from being called again before the previous execution completes, ensuring state changes can't be exploited through nested calls.
- `notPaused()` - Restricts function execution to when the vault is active; reverts if the vault is in a paused state (set by the admin), providing a safety switch during emergencies or upgrades.

## 4626 Functions
The external override functions (`totalAssets`, `decimals`, `deposit`, `mint`, `withdraw`, `redeem`) define the user-facing ERC-4626 interface, handling asset/share conversions, enforcing caps and pause states, and ensuring that deposits, withdrawals, and fee routing are executed consistently.

### `function totalAssets() public view override returns (uint256 _sum)`
* Purpose: Returns the total amount of underlying assets managed by the vault, including both liquid funds in the buffer and those deployed into Ajna buckets.
* Note: The return value is expressed in the underlying asset's native decimal format (not raw WAD precision, 18 decimals), ensuring ERC-4626 compliance.

### `function decimals() public pure override returns (uint8)`
* Purpose: Returns the number of decimal places used for share accounting in the vault, fixed at 18, in-line with ERC-4626 conventions.
* The output `(uint8)` - the number of decimals used for the vault's ERC-20 share token are always 18.
* Note: This refers to the vault share token's decimals, not necessarily the decimals of the underlying asset (which may differ, e.g., USDC = 6).

### `function deposit(uint256 assets, address receiver) public override lock notPaused returns (uint256)`
* Purpose: Allows a user to deposit a specified amount of underlying assets into the vault and receive newly minted vault shares in return.
* Inputs:
    * `unit256 assets` - the amount of underlying asset tokens to deposit (in underlying asset decimals)
    * `address receiver` - the address that will receive the corresponding vault shares
* Outputs:
    * `uint256` - the amount of shares received
* Notes: 
    * A deposit fee `(toll)` may be applied at the discretion of the vault operator, thereby reducing the net assets converted into shares.
    * Function execution is blocked if the vault is paused or already processing another critical operation `(lock)`.
    * For avoidance of doubt, minted shares use the vault's share decimals (18), while the deposited amount is in the underlying asset's native decimals.

### `function mint(uint256 shares, address receiver) public override lock notPaused returns (uint256)`
* Purpose: Mints an exact number of vault shares for a receiver by pulling in the required amount of underlying assets from the caller.
* Inputs:
    * `uint256 shares` - the number of shares to mint
    * `address receiver` - the address that will receive the minted shares
* Outputs:
    * `uint256` - the amount of shares received
* Notes: 
    * Function execution is blocked if the vault is paused or already processing another critical operation `(lock)`.

### `function withdraw(uint256 assets, address receiver, address owner) public override lock notPaused returns (uint256)`
* Purpose: Allows a user to withdraw a specific amount of underlying assets from the vault by redeeming the necessary number of shares. The withdrawn assets are then sent to the designated receiver.
* Inputs:
    * `uint256 assets` - the amount of underlying asset tokens to withdraw in underlying asset decimals
    * `address receiver` - the address that will receive the withdrawn assets
    * `address owner` - the address whose shares will be burned to cover the withdrawal
* Outputs:
    * `uint256` - the number of shares burned from the owner to release the requested assets.
* Notes:
    * A withdrawal fee `(tax)` may be applied at the discretion of the vault operator, thereby reducing the net assets received by the `receiver`.
    * Function execution is blocked if the vault is paused `(notPaused)` or already processing another critical operation `(lock)`.
    * Input `assets` is expressed in the underlying asset's native decimals, while the output `shares` are in vault share decimals (18).
    * In contrast with `redeem`: in `withdraw`, the caller specifies how many assets to take out; in `redeem`, the caller specifies how many shares to burn.
    * Parameters `owner` and `receiver` may differ - `owner` specifies whose vault shares are being burned, and `receiver` specifies who receives the withdrawn assets. This enables scenarios such as delegates withdrawals, where one account's shares are reduced but another account receives the asets.

### `function redeem(uint256 shares, address receiver, address owner) public override lock notPaused returns (uint256)`
* Purpose: Burns a specified number of vault shares from an owner and releases the corresponding amount of underlying assets to the receiver.
* Inputs:
    * `uint256 shares` - the number of vault shares to redeem in 18 decimals.
    * `address receiver` - the address that will receive the withdrawn assets.
    * `address owner` - the address whose shares will be burned to fund the redemption.
* Output:
    * `uint256` - the amount of underlying assets transferred to the receiver
* Notes:
    * A withdrawal tax (fee) may apply, reducing the net amount of assets received relative to the shares burned.
    * Function execution is blocked if the vault is paused `(notPaused)` or already processing another critical operation `(lock)`.
    * Input `shares` is expressed in vault share decimals (18), while the returned assets are in the underlying asset's native decimals.
    * The parameters owner and receiver may differ - `owner` specifies whose vault shares are being burned, and `receiver` specifies who receives the withdrawn assets.

### `function maxDeposit(address receiver) public view override returns (uint256)`
* Purpose: Returns the maximum amount of underlying assets that can be deposited for a given receiver, subject to the vault's configured deposit cap.
* Inputs:
    * `address receiver` - the account intended to receive the minted shares.
* Outputs:
    * `uint256` - the maximum depositable asset amount in the underlying asset's native decimals.
* Notes:
    * The `receiver` parameter is included to satisfy the ERC-4626 standard but is not used in this vault's implementation.
    * If a deposit cap is set, this will return the remaining capacity (`depositCap - totalAssets`).
    * If no cap is set (depositCap = 0), the function returns `type(uint256).max`.
    * Used by integrators and frontends to determine deposit limits before submitting a transaction.

### `function maxMint(address receiver) public view override returns (uint256)`
* Purpose: Returns the maximum number of vault shares that can be minted for a given receiver, based on the vault's configured deposit cap.
* Inputs:
    * `address receiver` - the account intended to receive the minted shares.
* Outputs:
    * `uint256` - the maximum number of shares that can be minted, expressed in vault share decimals (18).
* Notes:
    * In this vault, the `receiver` parameter is required by the ERC-4626 interface but is not used in the function logic.
    * If a deposit cap is set, the value returned corresponds to the shares equivalent of the remaining capacity (`depositCap - totalAssets`), after converting through `convertToShares`.
    * If no cap is set (`depositCap = 0`), the function returns `type(uint256).max`.

### `function maxWithdraw(address owner) public view override returns (uint256)`
* Purpose: Returns the maximum amount of underlying assets that can be withdrawn from the vault on behalf of a given owner, accounting for both their share balance and the vault's liquidity.
* Inputs:
    * `address owner` - the account whose shares would be burned to cover the withdrawal.
* Outputs:
    * `uint256` - the maximum withdrawable amount of underlying assets, expressed in the asset's native decimals.
* Notes:
    * The limit is the lesser of:
        * The asset value of `owner`'s share balance.
        * The vault's available liquidity (buffer + withdrawable bucket funds).
    * Provides an upper bound for integrators and UIs; actual withdrawal amounts are enforced in the `withdraw` function.
    * Does not include any deduction for the withdrawal tax (fees are applied during execution).

### `function maxRedeem(address owner) public view override returns (uint256)`
* Purpose: Returns the maximum number of vault shares that can be redeemed (burned) on behalf of a given owner, based on their balance and allowance.
* Inputs:
    * `address owner` - the account whose shares would be burned to execute the redemption.
* Outputs:
    * `uint256` - the maximum number of shares redeemable, expressed in vault share decimals (18).
* Notes:
    * The limit is the lesser of:
        * The `owner`'s share balance.
        * The allowance that the caller has to burn `owner`'s shares (if `msg.sender != owner`).
    * Provides an upper bound for integrators and UIs; actual redemption amounts are enforced in the redeem function.
    * Corresponds to a gross asset value; fees (withdrawal tax) are applied during execution, so the net assets received may be lower.

### `function previewDeposit(uint256 assets) public view override returns (uint256)`
* Purpose: Estimates how many vault shares would be minted if a user deposited a given amount of underlying assets.
* Inputs:
    * `uint256 assets` - the amount of underlying asset tokens to hypothetically deposit (in the asset’s native decimals).
* Outputs:
    * `uint256` - the number of shares that would be minted, expressed in vault share decimals (18).
* Notes:
    * Provides a read-only preview; no state changes occur.
    * Accounts for the deposit toll (fee), so the result reflects the net shares after fees.
    * Useful for integrators and UIs to show users how many shares they would receive before submitting a transaction.

### `function previewMint(uint256 shares) public view override returns (uint256)`
* Purpose: Estimates how many underlying assets a user would need to supply in order to mint a given number of vault shares.
* Inputs:
    * `uint256 shares` - the number of vault shares to hypothetically mint (in vault share decimals, 18).
* Outputs:
    *   `uint256` - the amount of underlying assets required, expressed in the asset's native decimals.
* Notes:
    * Provides a read-only preview; no state changes occur.
    * Accounts for the deposit toll (fee), so the result reflects the gross assets required to mint the requested shares.
    * Complements `previewDeposit`: while `previewDeposit` converts assets - shares, `previewMint` converts shares - assets.
    * Useful for integrators and UIs to show users how much they must deposit before calling mint.

### `function previewWithdraw(uint256 assets) public view override returns (uint256)`
* Purpose: Estimates how many vault shares would need to be burned to withdraw a specified amount of underlying assets.
* Inputs:
    * `uint256 assets` - the amount of underlying asset tokens to hypothetically withdraw (in the asset's native decimals).
* Outputs:
    * `uint256` - the number of shares that would be burned, expressed in vault share decimals (18).
* Notes:
    * Provides a read-only preview; no state changes occur.
    * Accounts for the withdrawal tax (fee), so the result reflects the gross shares burned to deliver the requested net assets.
    * Complements `previewRedeem`: while `previewWithdraw` specifies assets to receive and outputs shares to burn, `previewRedeem` specifies shares to burn and outputs assets received.
    * Useful for integrators and UIs to show users how many shares must be given up to unlock a given asset amount.

### `function previewRedeem(uint256 shares) public view override returns (uint256)`
* Purpose: Estimates how many underlying assets a user would receive by redeeming (burning) a given number of vault shares.
* Inputs:
    * `uint256 shares` - the number of vault shares to hypothetically redeem (in vault share decimals, 18).
* Outputs:
    * `uint256` - the amount of underlying assets that would be returned, expressed in the asset's native decimals.
* Notes:
    * Provides a read-only preview; no state changes occur.
    * Accounts for the withdrawal tax (fee), so the result reflects the net assets the receiver would get after fees.
    * Complements `previewWithdraw`: while `previewRedeem` specifies shares to burn and outputs assets received, `previewWithdraw` specifies assets to withdraw and outputs shares to burn.
    * Useful for integrators and UIs to show users how much they would receive before actually calling `redeem`.

## Admin and Keeper Functions
The keeper functions `move`, `moveFromBuffer`, and `moveToBuffer` enable authorized roles to rebalance liquidity between buckets and the buffer, adjusting yield exposure versus withdrawal liquidity without impacting user shares. Subsequent Swapper functions; `recoverCollateral` and `returnQuoteToken` allow authorized roles to manage exceptional liquidity cases - recovering collateral from buckets or redeploying quote tokens back into buckets - without affecting user shares, and a list of read-only public query endpoints expose contract state in a structured, developer-friendly way.

### `function move(uint256 _fromIndex, uint256 _toIndex, uint256 _wad) external lock notPaused`
* Purpose: Repositions deployed liquidity within the Ajna pool by moving a specified amount from one bucket index to another for yield/risk rebalancing; this does not mint/burn shares or touch the buffer.
* Inputs:
    * `uint256 _fromIndex` - the Ajna bucket index to move liquidity out of.
    * `uint256 _toIndex` - the Ajna bucket index to move liquidity into.
    * `uint256 _wad` - the amount of quote-token liquidity to move, in WAD (18-decimals) fixed-point, as used by Ajna; this is not the underlying asset's native decimals.
* Outputs:
    * None (state-changing rebalancing action).
* Notes:
    * Authorization: callable only by authorized roles per vault auth (e.g., admin/keeper); ordinary users cannot call this.
    * Bucket guards: enforces any configured bucket movement restrictions (e.g., `minBucketIndex`); will revert if indices violate policy or there's insufficient LP at `_fromIndex`.
    * Fees: no deposit/withdrawal fees apply; this is an internal portfolio move and does not change user share balances.
    * Concurrency & state: protected by `lock` (reentrancy guard) and `notPaused`.

### `function moveFromBuffer(uint256 _toIndex, uint256 _wad) external lock notPaused`
* Purpose: Deploys liquidity held in the vault's buffer into a specified Ajna bucket, reducing idle funds and increasing yield-bearing exposure. This function (alongside `moveToBuffer`)enables the cycling of liquidity between the idle buffer and Ajna buckets, allowing for dynamic rebalancing of vault funds.
* Inputs:
    * `uint256 _toIndex` - the Ajna bucket index to deposit liquidity into.
    * `uint256 _wad` - the amount of liquidity to move from the buffer, expressed in WAD (18-decimals) fixed-point, as used by Ajna.
* Outputs:
    * None (state-changing rebalancing action).
* Notes:
    * Authorization: callable only by authorized roles (e.g., admin/keeper).
    * The buffer decreases by `_wad`, and the corresponding Ajna bucket position increases.
    * This does not mint or burn vault shares; it simply redistributes vault-held assets from the idle buffer to deployed liquidity.
    * Enforces bucket restrictions (e.g., `minBucketIndex`) and reverts if constraints are violated.
    * Protected by `lock` (reentrancy guard) and `notPaused`.

### `function drain(uint256 _bucket) external lock notPaused`
* Purpose: Sync internal LP accounting for a given bucket if the vault's real LP balance in the Ajna pool has decreased (e.g., loss/bankruptcy/other burns not already reflected locally). It never increases the recorded LPs-only reduces them to the on-pool value.
* Inputs:
    * `uint256 _bucket` - bucket index to reconcile.
* Outputs:
    * None (state-changing rebalancing action).
* Notes:
    * Authorization: callable only by authorized role (`AUTH.isAdminOrKeeper(msg.sender)`).
    * No tokens move; this is bookkeeping only to avoid overstating the position.

### `function moveToBuffer(uint256 _fromIndex, uint256 _wad) external lock notPaused`
* Purpose: Withdraws liquidity from a specified Ajna bucket back into the vault's buffer, increasing available idle funds for redemptions or reallocation. This function (alongside `moveFromBuffer`)enables the cycling of liquidity between the idle buffer and Ajna buckets, allowing for dynamic rebalancing of vault funds.
* Inputs:
    * `uint256 _fromIndex` - the Ajna bucket index to withdraw liquidity from.
    * `uint256 _wad` - the amount of liquidity to move from the bucket, expressed in WAD (18-decimals) fixed-point, as used by Ajna.
* Outputs:
    * None (state-changing rebalancing action).
* Notes:
    * Authorization: callable only by authorized roles (e.g., admin/keeper).
    * The buffer increases by `_wad`, and the corresponding Ajna bucket position decreases.
    * This does not mint or burn vault shares; it simply redistributes vault-held assets from deployed liquidity to idle buffer.
    * Enforces bucket restrictions (e.g., `minBucketIndex`) and reverts if constraints are violated.
    * Protected by `lock` (reentrancy guard) and `notPaused`.

### `function recoverCollateral(uint256 _fromIndex, uint256 _amt) external notPaused`
* Purpose: Withdraws collateral tokens from a specified Ajna bucket back into the vault, typically used for recovery of non-standard or stranded assets.
* Inputs:
    * `uint256 _fromIndex` - the Ajna bucket index to withdraw collateral from.
    * `uint256 _amt` - the amount of collateral to recover (using WAD precision).
* Outputs:
    * None (state-changing recovery action).
* Notes:
    * Authorization: callable only by authorized roles (admin or swapper only).
    * This function does not interact with vault shares; it is purely for moving collateral tokens out of Ajna and back into the vault.
    * Protected by `notPaused`, but not by the `lock` modifier (reentrancy guard is not applied here).
    * Operational context: this function is not part of routine rebalancing. It is intended for exceptional circumstances where collateral needs to be withdrawn from buckets back to the vault.
* Risk: 
    * Recovered collateral may not match the vault's underlying asset, creating potential asset mismatch exposure.

### `function returnQuoteToken(uint256 _toIndex, uint256 _amt) external`
* Purpose: Returns idle quote tokens held in the vault (but outside of the buffer) back into a specified Ajna bucket, effectively topping up liquidity at that index.
* Inputs:
    * `uint256 _toIndex` - the Ajna bucket index to deposit quote tokens into.
    * `uint256 _amt` - the amount of quote tokens to return (using WAD precision).
* Outputs:
    * None (state-changing liquidity action).
* Notes:
    * Authorization: callable only by authorized roles (admin or swapper only).
    * For clarity, this function differs from assets in the buffer, which is the deliberate reserve the vault uses for liquidity purposes which is controlled by the `bufferRatio`. When `returnQuoteToken` is called, the source is quote tokens currently sitting at the vault contract, but not necessarily part of the buffer allocation, and can include:
        * Ajna bucket withdrawals not yet redeployed
        * Repaid funds arriving from Ajna
        * Collateral recovery converted to quote tokens

### `function getBuckets() external view returns (uint256[] memory)`
* Purpose: Provides a list of all Ajna bucket indices currently used by the vault to hold deployed liquidity.
* Inputs:
    * None.
* Outputs:
    * `uint256[]` - an array of bucket indices where the vault has active liquidity positions.
* Notes:
    * Useful for external keepers, monitoring tools, or frontends to query where liquidity is deployed without scanning the full Ajna pool.
    * The indices are expressed as Ajna bucket indices (not asset amounts), and may change over time as keepers rebalance liquidity.

### `function pool() public view returns (address)`
* Purpose: Returns the address of the Ajna pool contract that this vault interacts with for deploying and managing liquidity.
* Inputs:
    * None.
* Outputs:
    * `address` - the Ajna pool contract address tied to this vault.
* Notes:
    * This is a fixed reference set at vault deployment and does not change over time.
    * Useful for external integrations to verify or interact directly with the underlying Ajna pool.

### `function buffer() public view returns (address)`
* Purpose: Returns the address of the buffer contract used by the vault to hold and manage idle liquidity reserves.
* Inputs:
    * None.
* Outputs:
    * `address` - the buffer contract address linked to this vault.
* Notes:
    * Fixed reference set at vault deployment.
    * Enables external integrations or keepers to interact directly with the buffer contract if needed (e.g., for monitoring or audits).

### `function info() public view returns (address)`
* Purpose: Returns the address of the vault's info contract, which provides auxiliary data or metadata about the vault.
* Inputs:
    * None.
* Outputs:
    * `address` - the info contract address associated with this vault.
* Notes:
    * Reference set at vault deployment.
    * Typically used by external services or frontends to query vault-specific information without directly interacting with core logic.

### `function lpToValue(uint256 _bucket) public view returns (uint256)`
* Purpose: Calculates the total value (in underlying asset terms) of the vault's liquidity position in a specific Ajna bucket.
* Inputs:
    * `uint256 _bucket` - the Ajna bucket index to query.
* Outputs:
    * `uint256` - the value of the vault's LP position in that bucket, expressed in the underlying asset's native decimals.
* Notes:
    * Useful for monitoring and rebalancing, as it translates bucket-specific LP tokens into an asset-denominated value.

### `function paused() public view returns (bool)`
* Purpose: Indicates whether the vault is currently paused, disabling state-changing operations like deposits, withdrawals, and keeper moves.
* Inputs:
    * None.
* Outputs:
    * `bool` - `true` if the vault is paused, `false` if active.
* Notes:
    * Used by modifiers such as `notPaused` to enforce pause checks on sensitive functions.
    * There are two ways to pause a vault, either of which makes this return `true`:
      * Global-level pause flag - when the Admin toggles `pause()/unpause()` on VaultAuth (`AUTH.paused()`), the Vault mirrors this global admin-controlled pause.
      * Vault-level pause flag - if `removedCollateralValue > 0` occurs, meaning that this vault has had collateral removed and not yet returned by the admin or the swapper, it becomes temporarily paused until returned.
    * Pausing is controlled by the admin via the `pause`/`unpause` functions (keepers cannot pause).
