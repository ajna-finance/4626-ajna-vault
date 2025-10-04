# VaultAuth & IVaultAuth API Reference
The VaultAuth contract manages role-based access control (admin, swapper, keepers), vault configuration parameters (deposit cap, buffer ratio, fees, bucket limits), and emergency controls (pause/unpause). It also provides functions to query roles, update permissions, and retrieve accrued fees, forming the administrative and policy layer that governs vault operations.

## Errors
| Name                   | When it reverts                                                                                                                                      | Impact / Next Steps                                                                                                                                                                |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NotAuthorized()`      | The caller lacks the required role for the action (e.g., an admin-only, keeper-only, or swapper-only function is called by an unauthorized address). | The transaction is reverted. Verify the caller address, update roles/allowlists if intended (set admin/swapper/keeper), or execute the action from the correct privileged account. |
| `BufferRatioTooHigh()` | An attempt is made to set `bufferRatio` above the allowed maximum (typically capped at MAX\_BPS = 10,000 = 100%).                                    | The transaction is reverted. Choose a lower ratio within bounds; confirm the contract’s MAX\_BPS/limit and adjust ops tooling and keeper config accordingly.                       |
| `FeeTooHigh()`         | An attempt is made to set a fee parameter (`toll` for deposits or `tax` for withdrawals) above the allowed maximum.             | The transaction is reverted. Set the fee to a permitted value; update UI/fee disclosures and ensure governance or multisig inputs respect the cap.                                 |


## Events
| Name                                   | When it fires                                                      | Impact / Next Steps                                                                                                                                            |
| -------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SetAdmin(newAdmin)`                   | After the admin address is updated          | Control authority changes immediately. Update runbooks and multisig/EOA permissions; verify only the new admin can call admin-gated functions.                 |
| `SetSwapper(newSwapper)`               | After the swapper address is updated                               | Trading/swap permissions shift to `newSwapper`. Point keeper/off-chain services to the new swapper and revoke the old one if applicable.                       |
| `KeeperSet(keeper, isKeeper)`          | When an address is added or removed from the allow-listed keepers  | Keeper can/can’t execute keeper-only actions. Update keeper nodes’ credentials; ensure monitoring alerts reflect the new allowlist.                            |
| `Paused()`                             | When the contract’s pause flag is enabled by the admin             | State-changing actions gated by `paused` are blocked. Halt automations; investigate reason for pause; communicate status and prepare remediation/unpause plan. |
| `Unpaused()`                           | When the pause flag is disabled by the admin                       | Gated actions resume. Safely re-enable keeper runs and user flows; verify system health before full throughput.                                                |
| `DepositCapSet(newDepositCap)`         | After the global deposit cap is changed                            | Maximum total deposits change. Update UI/tooling, alert integrators; if cap lowered near current TVL, disable new deposits accordingly.                        |
| `BufferRatioSet(newBufferRatio)`       | After the target buffer ratio (bps) is changed                     | Keeper rebalancing and withdrawal liquidity target changes. Update keeper config; re-compute next moves to track the new ratio.                                |
| `TollSet(newToll)`                     | After the deposit fee (bps) is changed                             | New deposits charged at `newToll`. Update frontends, docs, and fee disclosures; verify accounting reflects the new toll.                                       |
| `TaxSet(newTax)`                       | After the withdrawal fee (bps) is changed                          | Withdrawals charged at `newTax`. Update UI/estimates and user messaging; confirm vault accounting and reports use the new rate.                                |
| `MinBucketIndexSet(newMinBucketIndex)` | After the minimum allowed bucket index for keeper moves is changed | Keeper movement is restricted to indices ≥ `newMinBucketIndex`. Update keeper policy/config; validate that planned moves comply.                               |


## Modifiers

- `onlyAdmin()`

## Functions

### `function isAdmin(address account) external view returns (bool)`
* Purpose: Checks whether a given address holds the admin role for the vault.
* Inputs:
    * `address account` - the address to verify.
* Outputs:
    * `bool` - `true` if the account is the current admin, `false` otherwise.
* Notes:
    * Used by other contracts, modifiers, and off-chain tooling to confirm admin permissions.
    * Does not change state; read-only query

### `function isSwapper(address account) external view returns (bool)`
* Purpose: Checks whether a given address is designated as the swapper for the vault.
* Inputs:
    * `address account` - the address to verify.
* Outputs:
    * `bool` - `true` if the account is the current swapper, `false` otherwise.
* Notes:
    * Swapper role is used for functions requiring token swaps or rebalancing authority.
    * Does not change state; read-only query

### `function isKeeper(address account) external view returns (bool)`
* Purpose: Checks whether a given address is authorized as a keeper for the vault.
* Inputs:
    * `address account` - the address to verify.
* Outputs:
    * `bool` - `true` if the account is an active keeper, `false` otherwise.
* Notes:
    * Keeper addresses are allowed to perform maintenance actions such as moving liquidity between buffer and buckets.
    * Read-only query; does not alter state.

### `function isAdminOrKeeper(address account) external view returns (bool)`
* Purpose: Checks whether a given address is either the admin or an authorized keeper.
* Inputs:
    * `address account` - the address to verify.
* Outputs:
    * `bool` - `true` if the account is the admin or a keeper, `false` otherwise.
* Notes:
    * Useful for restricting certain operations to both admin and keeper roles without duplicating checks.
    * Read-only query; does not modify state.

### `function isAdminOrSwapper(address account) external view returns (bool)`
* Purpose: Checks whether a given address is either the admin or the designated swapper.
* Inputs:
    * `address account` - the address to verify.
* Outputs:
    * `bool` - `true` if the account is the admin or the swapper, `false` otherwise.
* Notes:
    * Used for functions where both admin and swapper roles are permitted to act.
    * Read-only query; does not alter state.

### `function setAdmin(address _admin) external onlyAdmin`
* Purpose: Assigns a new admin address for the vault.
* Inputs:
    * `address _admin` - the address to set as the new admin.
* Outputs:
    * Emits a `SetAdmin` event upon success.
* Notes:
    * Callable only by the current admin (enforced via `onlyAdmin` modifier).
    * Transfers full administrative authority, including the ability to update roles, parameters, and pause/unpause the vault.

### `function setSwapper(address _swapper) external onlyAdmin`
* Purpose: Assigns a new swapper address for the vault.
* Inputs:
    * `address _swapper` - the address to set as the swapper.
* Outputs:
    * Emits a `SetSwapper` event upon success.
* Notes:
    * Callable only by the admin.
    * Grants the swapper role authority to execute swap-related or liquidity movement functions where `isAdminOrSwapper` checks are enforced.

### `function setKeeper(address _keeper, bool _isKeeper) external onlyAdmin`
* Purpose: Adds or removes a keeper address for the vault.
* Inputs:
    * `address _keeper` - the address whose keeper status is being updated.
    * `bool _isKeeper` - true to grant keeper rights, false to revoke them.
* Outputs:
    * Emits a `KeeperSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Keeper role controls maintenance operations such as moving liquidity between buffer and buckets.

### `function pause() external onlyAdmin`
* Purpose: Puts the vault into a paused state, disabling deposits, withdrawals, and other state-changing operations.
* Inputs:
    * None.
* Outputs:
    * Emits a `Paused` event upon success.
* Notes:
    * Callable only by the admin.
    * Used as an emergency safeguard against unexpected conditions or exploits.

### `function unpause() external onlyAdmin`
* Purpose: Reactivates the vault after being paused, restoring normal operations such as deposits, withdrawals, and rebalancing.
* Inputs:
    * None.
* Outputs:
    * Emits an `Unpaused` event upon success.
* Notes:
    * Callable only by the admin.
    * Should only be used once the issue that triggered the pause has been resolved.

### `function setDepositCap(uint256 _depositCap) external onlyAdmin`
* Purpose: Updates the maximum amount of assets that can be deposited into the vault.
* Inputs:
    * `uint256 _depositCap` - new deposit cap, expressed in the underlying asset's native decimals (`0` disables the cap).
* Outputs:
    * Emits a `DepositCapSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Enforced in functions like `maxDeposit` to prevent deposits that exceed the cap.
    * Useful for risk management and staged growth control.

### `function setBufferRatio(uint256 _bufferRatio) external onlyAdmin`
* Purpose: Updates the buffer ratio, defining what percentage of total assets must be held in the vault’s buffer instead of being deployed into buckets.
* Inputs:
    * `uint256 _bufferRatio` - new ratio expressed in basis points.
* Outputs:
    * Emits a `BufferRatioSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Enforced in keeper/admin move functions through `_checkBufferRatio`.
    * Balances liquidity for withdrawals (higher buffer) versus yield from deployment (lower buffer).

### `function setToll(uint256 _toll) external onlyAdmin`
* Purpose: Updates the deposit fee (toll) applied when users deposit assets into the vault.
* Inputs:
    * `uint256 _toll` - new toll expressed in basis points.
* Outputs:
    * Emits `TollSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Fee is deducted from deposits and sent to the fee receiver via `_sendFee`.
    * Affects deposit and mint flows by reducing the net assets converted into shares.

### `function setTax(uint256 _tax) external onlyAdmin`
* Purpose: Updates the withdrawal fee (tax) applied when users withdraw assets from the vault.
* Inputs:
    * `uint256 _tax` - new tax expressed in basis points.
* Outputs:
    * Emits `TaxSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Fee is deducted from withdrawals and routed to the fee receiver.
    * Affects `withdraw` and `redeem` flows by reducing the net assets users receive.

### `function setMinBucketIndex(uint256 _minBucketIndex) external onlyAdmin`
* Purpose: Updates the minimum bucket index into which liquidity can be deployed.
* Inputs:
    * `uint256 _minBucketIndex` - new minimum bucket index (`0` disables the restriction).
* Outputs:
    * Emits `MinBucketIndexSet` event upon success.
* Notes:
    * Callable only by the admin.
    * Enforced in keeper/admin rebalancing through `_validDestination`, which reverts if liquidity is directed below this threshold.
    * Used to prevent riskier allocations to very low-priced (risky) buckets.

### `function retrieveFees(address token, uint256 amount) external onlyAdmin`
* Purpose: Allows the admin to withdraw accrued fees from the vault.
* Inputs:
    * `address token` - the ERC-20 token address of the fee asset to retrieve.
    * `uint256 amount` - the amount of tokens to withdraw, in the token’s native decimals.
* Outputs:
    * None.
* Notes:
    * Callable only by the admin.
    * Transfers the specified fee amount to the admin/fee receiver.
    * Does not impact user deposits or shares; only moves fees accrued from tolls and taxes.
