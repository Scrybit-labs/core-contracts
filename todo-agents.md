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

# Todo (Update CORE_FLOW.md with newest structure)
- [x] Clean up file structure: Remove chat messages from beginning (lines 1-121)
- [x] Update contract naming throughout: Pod → Manager (EventPod→EventManager, OrderBookPod→OrderBookManager, FundingPod→FundingManager, FeeVaultPod→FeeVaultManager)
- [x] Update balance model: Per-token tracking → Unified USD balance system (userTokenBalances→userUsdBalances, add normalizeToUsd/denormalizeFromUsd)
- [x] Update fee system: Single 0.3% → Split fees (0.1% placement + 0.2% execution, per-token feeBalances→protocolUsdFeeBalance)
- [x] Update settlement flow: One-step → Two-step (markEventSettled + redeemWinnings pull pattern, add canRedeemWinnings docs)
- [x] Update storage: Remove separate storage contract references, add note about integrated storage with __gap arrays
- [x] Add upgradeability section: Document UUPS proxy pattern for all Manager contracts
- [x] Keep document in Chinese, preserve structure and examples

# Review (Update CORE_FLOW.md)
- Completely rewrote CORE_FLOW.md to reflect current architecture
- Changes made:
  - Removed all chat messages at the beginning
  - Updated all "Pod" references to "Manager" (EventManager, OrderBookManager, FundingManager, FeeVaultManager)
  - Updated balance model documentation to unified USD system with normalizeToUsd/denormalizeFromUsd functions
  - Updated fee system to split model (0.1% placement + 0.2% execution) with protocolUsdFeeBalance
  - Updated settlement flow to two-step pull pattern (markEventSettled → redeemWinnings)
  - Added 1:1 redemption documentation (1 Winning Long Token = 1 USD)
  - Removed separate storage contract references, documented integrated storage with __gap arrays
  - Added comprehensive UUPS upgradeability section with upgrade commands
  - Preserved Chinese language, flow structure, and all code examples
  - Added new sections: canRedeemWinnings, fee storage invariants, upgrade mechanisms
- Document now accurately reflects the direct-to-consumer architecture with all breaking changes from ToB elimination

# Todo (Update CORE_FLOW.md - Additional Requirements)
- [x] Add eventType field to Event struct (in createEvent flow and data structures section)
- [x] Add minimum balance requirements documentation (10 USD minimum for USDC/USDT)
- [x] Add frontend balance query documentation (getUserBalance for all supported tokens)
- [x] Update deposit flow to include minimum balance validation

# Review (Additional Requirements)
- Added eventType field to Event struct in both createEvent flow and data structures section
- Updated createEvent code example to include eventType parameter ("政治", "体育", "娱乐" etc)
- Added minimum deposit validation (10 USD) to deposit flow with require check
- Added MIN_DEPOSIT_USD constant documentation
- Added comprehensive frontend integration guide:
  - Contract exposes getSupportedTokens() to return protocol token list
  - Frontend calls balanceOf(user) directly on ERC20 contracts for wallet balances
  - Added getTokenPrice() and getMinDepositUsd() helper functions
  - Provided multi-chain support example with SUPPORTED_CHAINS mapping
  - JavaScript/ethers.js code examples for balance display
- Design principles documented:
  - Contract only provides supportedTokens list
  - Frontend queries ERC20 contracts directly (gas efficient)
  - Multi-chain ready with independent supportedTokens per chain
  - Frontend aggregates cross-chain balances
