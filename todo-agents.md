# Todo
- [x] Review current FundingManager, IFundingManager, and OrderBookManager to map existing settle flow
- [x] Implement REDEEM_PLAN.md changes in FundingManager and IFundingManager
- [x] Update OrderBookManager to call markEventSettled
- [x] Run build/tests as appropriate
- [x] Add review notes

# Review
- Built with `/home/node/.foundry/bin/forge build` (forge not in PATH). Build succeeded; existing lint warnings remain.

# Todo (ETH disable)
- [x] Review FundingManager deposit/withdraw paths for ETH handling
- [x] Add minimal, easy-to-remove entry guards to block ETH deposit/withdraw while keeping ERC20 flow intact
- [x] Run build/tests as appropriate
- [x] Add review notes

# Review (ETH disable)
- Built with `/home/node/.foundry/bin/forge build` after ETH entry guards; build succeeded with existing lint warnings.

# Todo (Fee system alignment)
- [x] Read `FEE_SYSTEM_PLAN.md` and extract requirements and assumptions
- [x] Locate current fee-related code paths (OrderBookPod, FundingPod, FeeVaultPod, EventPod if relevant) and summarize fee flow
- [x] Compare plan vs. implementation; list gaps or mismatches
- [x] Draft a concrete implementation plan (smallest-change steps) and check in for approval
- [x] Summarize findings and open questions for you

# Review (Fee system alignment)
- Reviewed `FEE_SYSTEM_PLAN.md`, fee flow in `OrderBookManager`, fee storage/withdraw in `FeeVaultManager`, USD balance + liquidity flow in `FundingManager`, and deployment wiring in `script/SimpleDeploy.s.sol`.
- Identified plan vs. code gaps: fee storage is per-token in `FeeVaultManager`, withdrawal transfers from `FeeVaultManager` (but liquidity sits in `FundingManager`), fee types are all `"trade"`, and no FeeVault↔Funding wiring or normalization helpers exist.

# Todo (Fee system implementation)
- [x] Add FundingManager fee vault hooks (normalize/denormalize, collect fee, withdraw liquidity, setter)
- [x] Migrate FeeVaultManager to protocol USD fee balance and FundingManager-backed withdrawals
- [x] Split fee types to placement/execution and compute fees in USD
- [x] Update interfaces and deployment wiring

# Review (Fee system implementation)
- Implemented protocol USD fee accounting in `FeeVaultManager`, added FundingManager fee-vault hooks, split placement/execution fee handling in `OrderBookManager`, and wired FeeVault↔Funding in `script/SimpleDeploy.s.sol`.
- Not run: tests/builds (not requested).
