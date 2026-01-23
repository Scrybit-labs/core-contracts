# Active Implementation Plan

## Phase 0: Prep
- [x] Archive prior plan to `final_checklist.md`.

## Phase 1: outcomeId -> outcomeIndex (uint8)
- [x] Update interfaces: `IEventPod`, `IOrderBookPod`, `IFundingPod`, `IOrderBookManager`, `IOracle`/`IOracleConsumer` (params, events, errors).
- [x] Update storage: Event/OrderBook/Funding/Oracle storage structs, mappings, and results to use `uint8` outcome indices.
- [x] Update pods and oracle logic: `EventPod`, `OrderBookPod`, `FundingPod`, `OracleAdapter` (params, locals, validations, events, mapping access).
- [x] Update managers: `OrderBookManager`, `FundingManager` outcome parameters and pod calls.
- [x] Repo-wide search to ensure no `outcomeId` or `uint256` outcome index remains in `src`.

## Phase 2: simplify outcome storage in OrderBookPod
- [x] Replace `EventOrderBook.supportedOutcomes` array with `outcomeCount` (`uint8`) in `OrderBookPodStorage`.
- [x] Update `OrderBookPod.addEvent` to set `outcomeCount` and stop pushing indices.
- [x] Replace iterations over `supportedOutcomes` with loops over `outcomeCount`.
- [x] Ensure outcome validation uses `outcomeCount` or `outcomes.length`.

## Phase 3: move all user-facing actions to pods; remove from managers
- [x] Add direct user functions in `FundingPod`: `depositEth`, `depositErc20`, `withdrawDirect`, `mintCompleteSetDirect`, `burnCompleteSetDirect`.
- [x] Ensure OrderBookPod already supports direct user access (place/cancel). If not, add direct variants.
- [x] Remove user-facing functions from managers (no deprecation): `FundingManager` (deposit/withdraw/mint/burn), `OrderBookManager` (place/cancel), and any others discovered.
- [x] Update/remove interfaces for manager user-facing functions as needed.

## Tests and validation
- [ ] Run `forge clean`.
- [ ] Run `forge build --via-ir` after Phase 1 and after Phase 2/3.
- [ ] Run `forge test` after Phase 3.
- [x] Grep validation: no `outcomeId` and no `uint256` outcome index in `src`.

## Review
- [x] Add a review section with change summary, issues, and test results.

### Changes Summary
- Standardized outcome identifiers to `uint8 outcomeIndex` across interfaces, storage, pods, and oracle logic.
- Simplified OrderBook outcome storage by replacing `supportedOutcomes` array with `outcomeCount`.
- Removed user-facing manager functions and added direct user entrypoints in `FundingPod`.

### Issues Encountered
- `forge` is not available in this environment, so build/test commands could not be executed.

### Test Results
- `forge clean`: not run (command not found).
- `forge build --via-ir`: not run (command not found).
- `forge test`: not run (command not found).
- `grep -R "outcomeId" src`: no matches.
- `grep -R "outcomeIndex.*uint256" src`: no matches.
