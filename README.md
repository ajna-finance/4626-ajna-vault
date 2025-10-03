# ERC-4626 Ajna Vault - Overview

The ERC-4626 tokenized vault allocates quote token deposits into an Ajna pool while maintaining a configurable liquidity Buffer for fast exits. The system exposes a standard 4626 interface for integrators (frontends, SDKs, and protocols), plus admin/keeper controls for bucket and buffer management.

* Users interact via standard 4626 flows: deposit/mint (converting assets to shares) and withdraw/redeem (converting shares to assets).
* A Buffer contract holds an admin-specified quantity of quote tokens to improve liquidity.
* Keepers can move liquidity between the buffer and between Ajna buckets to optimize yield/liquidity.
* An Admin manages parameters like fees, caps, roles, and the pause/unpause state for user safety.

## Why it exists
* Provide a standard ERC-4626 interface for integrators.
* Maintain a configurable Buffer ratio so users can withdraw quickly.
* Allow controlled rebalancing of liquidity between buckets for yield/liquidity targeting.

## What it does
* Deposit / Mint - Checks the vault is not paused & the deposit is within the cap, transfers assets in, applies a deposit fee if selected, then deposits net assets into the Buffer and mints shares to the receiver.
* Rebalance - Checks Buffer and enables the keeper to move liquidity between Ajna buckets or to target the configured buffer ratio and optimize for liquidity/yield. 
* Withdraw / Redeem - Checks the vault is not paused and any withdrawal amount is within user limits, computes a withdraw fee if selected, burns the seleted shares, and pays the user from the Buffer only. If the Buffer cannot cover the request, the call reverts as keepers must maintain the Buffer through further rebalancing to satisfy redemption requests.

## Components
- Vault (`Vault.sol`): Main 4626 vault entry point. Mints/burns shares, reports total assets, enforces caps/fees, and orchestrates bucket/buffer moves.
- VaultAuth (`VaultAuth.sol`): Role & policy hub (admin, swapper, keepers) and configuration (deposit cap, buffer ratio, toll/tax fees, min bucket index, pause).
- Buffer (`Buffer.sol`): Simple reserve that holds a portion of the quote token to satisfy withdrawals and speed up user exits.
- AjnaVaultLibrary (`AjnaVaultLibrary.sol`): Utilities that implement the low-level mechanics of moving funds between Ajna buckets and the Buffer and doing safety/math checks.
- Interfaces: `IVault`, `IVaultAuth`, `IBuffer` define the canonical events, errors, and function surfaces used across the system.

## Install and Testing
Requirements: [Foundry](https://getfoundry.sh/forge/overview/)
```bash
forge install
make build
```

Testing can be done either locally or against a forked version of mainnet.

Local Tests:
```bash
make test [v=3] [mt=...] [mc=...]
```

Fork Testing is done the same way but with first setting:
```bash
ETH_RPC_URL=...
```

## Deployment

Deployments require a deployed instance of Ajna with:
- An ERC-20 Pool
- A PoolInfoUtils contract

First set the config you want to deploy using the `./config/vault-config.example.json` as an example, then deployment can be run:

```bash
export CONFIG_PATH=<path-to-your-config-file>
export ETH_RPC_URL=<your-rpc-url>
export PRIVATE_KEY=<your_private_key>
forge script script/Vault.s.sol --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

The script will output all deployed contract addresses and configuration details.

And then verification:
```bash
forge verify-contract <VAULT_ADDRESS> Vault --etherscan-api-key $ETHERSCAN_API_KEY
forge verify-contract <VAULTAUTH_ADDRESS> VaultAuth --etherscan-api-key $ETHERSCAN_API_KEY
```
