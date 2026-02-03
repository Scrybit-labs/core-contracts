# TODO Plan — GitHub Issue #1 Bug Verification & Fix Execution

Context
- Source plan: `GITHUB_ISSUE_1_BUG_VERIFICATION_AND_FIX_PLAN.md` (updated 2026-02-03)
- Goal: apply confirmed fixes + implement new FundingManager interface and deposit-limit requirements.
- Key files: `src/core/EventManager.sol`, `src/core/FundingManager.sol`, `src/interfaces/core/IFundingManager.sol`, `src/oracle/mock/MockOracleAdapter.sol`, `src/oracle/simple/SimpleOracleAdapter.sol`, tests under `test/`.

Planned tasks (check off as completed)
- [x] Re-verify current behavior in code for Bug #2, #1, #4, #5, #9 to align plan with actual implementation (EventManager/FundingManager/Oracle adapters).
- [x] Fix Bug #2 (critical): remove `Settled` transition from `_isValidStatusTransition` so `updateEventStatus` cannot bypass settlement flow.
- [x] Fix Bug #1: add dummy event in `EventManager.initialize` so real event IDs start at 1; confirm `eventMustExist` + `nextEventId()` implications.
- [x] Fix Bug #1: update `MockOracleAdapter` to remove `+1/-1` workaround; ensure request IDs still start at 1 and mapping uses `0` as sentinel.
- [x] Bug #1 sanity check: confirm `SimpleOracleAdapter` doesn’t rely on eventId 0; adjust only if validation or tests require it.
- [x] Fix Bug #4: change `requestOracleResult` time check from `settlementTime` to `deadline`.
- [x] Fix Bug #5: block `_mintCompleteSet` if `eventSettled[eventId]` is true.
- [x] Implement Bug #9 interfaces and behavior (per updated deposit limits):
  - add state vars: `minDepositPerTxnUsd` (1 USD), `minTokenBalanceUsd` (5 USD), `userTokenBalancesUsd` mapping
  - add events: `MinDepositPerTxnUsdUpdated`, `MinTokenBalanceUsdUpdated`
  - add interface getters/setters + `getTokenPrice` + `getAllTokenBalances`
  - enforce per-transaction min (>= 1 USD) in deposit flow
  - enforce per-token min balance (>= 5 USD) after deposit, and ensure a helper exists to read per-token balances
  - update deposit/withdraw logic to track per-token USD balances
  - keep TODO comments for oracle price integration; return `1e18` for now
- [x] Update/extend tests for:
  - eventId starting at 1
  - `updateEventStatus` cannot set `Settled`
  - oracle request after deadline but before settlementTime
  - mint complete set after settlement reverts
  - min deposit per txn + per-token balance enforcement + new getters
- [x] Update docs where needed (bugs #6/#8/#10 notes) to reflect current code behavior.
- [x] Run targeted tests (and full suite if time):
  - `forge test --match-test <relevant>`
  - `forge test -vvv`

Notes/assumptions
- Current deposit APIs are `deposit`, `depositErc20`, and internal `_deposit` (no `depositDirect`/`depositTokenAmount`), so minimum checks should likely live in `_deposit`.
- Dummy event at index 0 must be non-usable (cancelled) and should not break `eventMustExist` or any indexing logic.
- Per-token balance tracking is required to enforce `minTokenBalanceUsd` and should be kept in USD (1e18).
- `getAllTokenBalances` needs a list of enabled tokens; if none exists, either add minimal tracking or return empty arrays with a TODO (confirm which approach is acceptable before coding if unclear).

## Review
- Implemented EventManager fixes (dummy eventId 0, deadline-based oracle request, disallowed Active→Settled via updateEventStatus).
- Added FundingManager deposit limits, per-token USD tracking, new getters, and settlement mint guard; wired interface updates.
- Updated MockOracleAdapter request mapping and added/adjusted tests to use proxies for upgradeable contracts; added new unit tests.
- Updated withdrawal docs to reflect `withdrawDirect(tokenAddress, usdAmount)` and mention `withdrawTokenAmount`.

Tests run
- `forge test --match-contract EventManagerStatusTest`
- `forge test --match-contract FundingManagerLimitsTest`
- `forge test --match-contract SimpleOracleAdapterTest`
- `forge test --match-contract MockOracleAdapterTest`
- `forge test --match-contract EventManagerOracleAuthTest`
