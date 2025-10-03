## Risks
The ERC-4626 vault introduces several operational, economic and configuration risks that operators, integrators and users should be aware of.

**Keeper Risk:**
The system relies on permissioned keepers to perform rebalancing and collateral recovery. If these keepers experience outage or misconfiguration, rebalancing may be delayed or halted, leading to reduced liquidity availability, longer withdrawal times, and wider pricing gaps during volatile markets. Key considerations also include:
* Price Selection: Keepers choose which bucket prices to target when moving liquidity. Although the keeper is bounded by admin-configured parameters, there is discretion within those bounds. Poor price selection can expose the vault to suboptimal yield or increased risk if liquidity is concentrated too high or too low in the curve.
* Admin Bounds: Admins set parameters that restrict where keepers can move liquidity. If bounds are too loose, keepers may exercise broad discretion leading to misaligned allocations. If bounds are too tight, keeper rebalancing may be blocked when conditions change, leaving the vault unable to adapt in stressed markets. It is therefore important that operators manage the admin settings in line with the volatility of the target market.
* Movement Costs: Keeper moves will likely result in fees paid to the Ajna system.  As a result, frequent rebalancing or poorly sized moves create unnecessary churn which increases the overhead and could reduce net yield for vault participants through loss of principle to fees.

**Admin Risk:**
The system relies on a central admin role to set parameters, and manage authorizations. If the admin role is compromised, user funds could be lost or mismanaged. Aside from being compromised, the Admin can change permissions, pause contracts, or collude with keepers to drain liquidity from the vault.

**Liquidity Risk:**
Vault users share the same fundamental risks as participants in the underlying Ajna protocol. While the vault introduces a buffer to improve withdrawal availability, it cannot mitigate risks arising from the underlying pool - including bad debt that may accumulate from unfavorable liquidations or collateral swaps, or issues arising from thin liquidity. To maintain usability, the operator should calibrate buffer limits carefully, knowing that over-allocating to buckets increases withdrawal risk, while over-allocating to the buffer reduces yield.

**Asset Type Risk:**
For non-like assets (e.g. USDC:wBTC) that are prone to experiencing higher volatility, there is a risk that prices could move too fast thereby forcing the admin to carry out more collateral management than would be necessary on like-assets (e.g. USDC:USDT). As mentioned in the Keeper section, a more active vault would also result in higher operational gas costs and could introduce Ajna costs for bucket management, impacting the depositor.

**Economic/Market Risk:**
In volatile markets the keeper risks not being responsive enough to update vault positions. If it reacts too slowly, asset pricing can fall out of sync with broader market conditions, leading to reduced yields, potential arbitrage, or less favorable withdrawal outcomes. The keeper therefore should be sufficiently responsive relative to the market or assets held. This also holds true for mispositioned buckets or delayed moves that could trap liquidity away from the yield-optimal bucket, lowering returns and impairing withdrawals.
