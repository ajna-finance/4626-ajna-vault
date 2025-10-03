# Buffer & IBuffer API Reference
The Buffer contract manages idle liquidity for the vault by holding quote tokens in reserve, minting and burning internal accounting units (`Mana`), and keeping balances updated with accrued interest. It serves as the liquidity bridge between user deposits and Ajna bucket deployment, with access strictly controlled through the Vault contract. 

`IBuffer` provides the contract surface that the Vault relies on, with the actual logic implemented in `Buffer.sol`. The interface also specifies buffer-specific errors (`BufferPoolMaxedOut`, `ReentrancyGuardActive`, `Unauthorized`) that safeguard against misuse or unsafe conditions.

## Errors

`BufferPoolMaxedOut()`
* Purpose: Raised when an `addQuoteToken` call would push the buffer's total size above its hard-coded maximum limit (`100 * TRILLION`).
* Notes:
    * Prevents uncontrolled growth of the buffer.
    * Ensures system parameters remain within safe, predefined limits.

`ReentrancyGuardActive()`
* Purpose: Raised when a `lock`-protected function is called while another such call is already in progress, indicating an attempted reentrant execution.
* Notes:
    * Enforces single-threaded execution of sensitive buffer operations.
    * Prevents potential exploits that rely on reentrancy into state-changing functions.

`Unauthorized()`
* Purpose: Raised when a restricted function (e.g., `onlyVault`-protected) is called by an address that is not authorized.
* Notes:
    * Ensures that only the vault contract can perform buffer operations like adding or removing quote tokens.
    * Provides a clear failure mode for unauthorized access attempts.  

## Events

_None declared here._

## Modifiers
* `lock` - Reentrancy guard: uses a `bolt` mutex (sets to 1 during execution, back to 0 after) and reverts with `ReentrancyGuardActive` if already entered.
* `onlyVault()` - Restricts function execution to calls made by the configured `vault` contract, otherwise reverts with `unauthorized`.

## Functions

### `function addQuoteToken(uint256 _wad, uint256 _bucket, uint256 _expiry) external onlyVault lock returns (uint256, uint256)`
* Purpose: Increases the buffer’s quote token balance by transferring tokens in from the vault contract and issuing the corresponding amount of internal accounting units (“Mana”).
* Inputs:
    * `uint256 _wad` - amount of quote tokens to add, expressed in WAD (18 decimals).
    * `uint256 /* _bucket */` - unused placeholder parameter for interface compatibility.
    * `uint256 /* _expiry */` - unused placeholder parameter for interface compatibility.
* Outputs:
    * `uint256` - amount of Mana units minted (internal accounting).
    * `uint256` - WAD amount of quote tokens credited.
* Notes:
    * Inherited from IBuffer
    * Callable only by the Vault contract (`onlyVault`).
    * Protected by a reentrancy lock.
    * Scales Mana proportionally to existing supply; if none exists, Mana is 1:1 with `_wad`.
    * Reverts with `BufferPoolMaxedOut` if total buffer size exceeds the hard cap (`100 * TRILLION`).
    * Transfers the underlying ERC-20 tokens from the vault to the buffer contract.

### `function removeQuoteToken(uint256 _wad, uint256 _bucket) external onlyVault lock returns (uint256, uint256)`
* Purpose: Decreases the buffer's quote token balance by redeeming Mana for the corresponding amount of quote tokens, which are then sent back to the vault contract.
* Inputs:
    * `uint256 _wad` - amount of quote tokens to remove, expressed in WAD (18 decimals).
    * `uint256 _bucket` - unused placeholder parameter for interface compatibility.
* Outputs:
    * `uint256` - amount of shares (Mana) units burned.
    * `uint256` - WAD amount of quote tokens debited.
* Notes:
    * Inherited from IBuffer
    * Callable only by the Vault contract (`onlyVault`).
    * Protected by a reentrancy lock.
    * Ensures proportional burning of Mana relative to total supply and buffer size.
    * Transfers the corresponding ERC-20 quote tokens from the buffer back to Vault.
    * Complements `addQuoteToken` as the withdrawal side of buffer management.

### `function updateInterest() external`
* Purpose: Placeholder / no-op for interface compatibility. It is included to maintain a consistent contract surface across implementations.
* Inputs:
    * None.
* Outputs:
    * None.

## Public View Functions

### `function lpToValue(uint256 _lps) public view returns (uint256)`
* Purpose: Converts a given number of buffer LP tokens into their equivalent value in quote tokens.
* Inputs:
    * `uint256 _lps` - the number of LP tokens to evaluate.
* Outputs:
    * `uint256` - the equivalent value in quote tokens, expressed in WAD (18 decimals).
* Notes:
    * Inherited from IBuffer
    * Read-only helper for translating buffer LP balances into quote token value.
    * Used by other contracts and external queries to assess buffer liquidity.

### `function quo() external view returns (address);`
* Purpose: Returns the address of the quote token managed by the buffer.
* Inputs:
    * None.
* Outputs:
    * `address` - the ERC-20 token contract address of the buffer's quote token.
* Notes:
    * in IBuffer
    * Read-only query for integrations and vault logic to confirm which asset the buffer is holding.

### `function assetDecimals() external view returns (uint8) ;`
* Purpose: Returns the number of decimals used by the buffer's underlying quote token.
* Inputs:
    * None.
* Outputs:
    * `uint8` - the decimal precision of the quote token (e.g., 6 for USDC, 18 for DAI).
* Notes:
    * Read-only query to ensure correct scaling between token units and WAD (18-decimal) math in the vault system.

### `function vault() external view returns (address) ;`
* Purpose: Returns the address of the Vault contract authorized to interact with the buffer.
* Inputs:
    * None.
* Outputs:
    * `address` - the Vault contract address.
* Notes:
    * in IBuffer

### `function total() external view returns (uint256) ;`
* Purpose: Returns the total quote token balance managed by the buffer, expressed in WAD (18 decimals).
* Inputs:
    * None.
* Outputs:
    * `uint256` - the total buffer balance in WAD.
* Notes:
    * in IBuffer
    * Read-only query for integrations and vault logic to track overall buffer liquidity.
    * May include both principal and accrued interest since the last updateInterest call.

### `function Mana() external view returns (uint256) ;`
* Purpose: Returns the total supply of shares in the buffer (Mana).
* Inputs:
    * None.
* Outputs:
    * `uint256` - the current Mana supply, expressed in WAD (18 decimals).
* Notes:
    * in IBuffer
    * Serves as the buffer's share-like unit, ensuring proportional ownership of quote tokens across time.
    * Read-only query; used by vault and accounting logic to keep buffer balances consistent.

### `function bolt() external view returns (uint8) ;`
* Purpose: Returns the current reentrancy guard status of the buffer.
* Inputs:
    * None.
* Outputs:
    * `uint8` - the current state of the reentrancy guard.
* Notes:
    * in IBuffer
    * Used internally to track whether a lock-protected function is active.
    * Exposed externally for transparency and potential monitoring of contract safety.
