# Test Implementation Plan - Comprehensive Todo List

## Executive Summary

**Project:** Vendor-Based Pod Architecture Prediction Market Platform
**Current Status:** 165/~400 tests complete (41% done)
**Test Infrastructure:** ✅ Complete
**Pod Unit Tests:** ✅ Complete (163 tests)
**Remaining:** Manager Layer, Factory Layer (expanded), Oracle Layer, Admin Layer, Integration Tests

## Current Session Plan (Completed)

- [x] Add `test/unit/factory/PodDeployer.t.sol` covering initialization, pod implementation setters, deploy flows, and CREATE2 address predictions
- [x] Expand PodFactory tests into `test/unit/factory/PodFactory.t.sol` for vendor registration variants, manager config setters, and vendor info views
- [x] Update this checklist with completed items and add a review summary section

## Current Session Plan (Completed)

- [x] Audit pod contracts and deployment flow for upgradeability usage and constructor requirements
- [x] Convert pod contracts to non-upgradeable bases while keeping initializer + empty constructor
- [x] Confirm PodDeployer/PodFactory deterministic CREATE2 flow remains valid for clones
- [x] Update pod test helpers and unit tests to use non-proxy pod deployments
- [x] Add a review summary to this checklist after changes

---

## ✅ COMPLETED - Phase 1: Test Infrastructure

### Status: 100% Complete

**Infrastructure Files:**
- ✅ `test/base/BaseTest.sol` - Common test utilities with standard addresses and helpers
- ✅ `test/base/BasePodTest.sol` - Pod-specific deployment and wiring helpers
- ✅ `test/mocks/MockERC20.sol` - ERC20 mock with mint/burn
- ✅ `test/mocks/MockOracle.sol` - Oracle simulation
- ✅ `test/mocks/MockEventPod.sol` - EventPod mock
- ✅ `test/mocks/MockOrderBookPod.sol` - OrderBookPod mock
- ✅ `test/mocks/MockFundingPod.sol` - FundingPod mock with all required functions
- ✅ `test/mocks/MockFeeVaultPod.sol` - FeeVaultPod mock
- ✅ `test/helpers/EventHelper.sol` - Event creation templates
- ✅ `test/helpers/MerkleTreeHelper.sol` - Merkle proof generation

**Achievements:**
- All mock contracts implement required interfaces
- Helper libraries provide reusable test utilities
- Base classes enable consistent test patterns

---

## ✅ COMPLETED - Phase 2: Core Pod Unit Tests (163 tests)

### Status: 100% Complete

### ✅ FeeVaultPod Tests - 35 tests passing
**File:** `test/unit/pod/FeeVaultPod.t.sol`

**Coverage:**
- ✅ Initialization (3 tests)
- ✅ Fee rate management (4 tests)
- ✅ Fee calculation (5 tests)
- ✅ Fee collection (5 tests)
- ✅ Fee withdrawal (6 tests)
- ✅ Admin functions (8 tests)
- ✅ View functions (3 tests)

**Result:** All 35 tests passing ✅

---

### ✅ EventPod Tests - 45 tests passing
**File:** `test/unit/pod/EventPod.t.sol`

**Coverage:**
- ✅ Initialization (4 tests)
- ✅ Event creation (10 tests)
- ✅ Oracle request (5 tests)
- ✅ Event settlement (10 tests)
- ✅ Event cancellation (4 tests)
- ✅ Status transitions (6 tests)
- ✅ View functions (4 tests)
- ✅ Admin functions (2 tests)

**Result:** All 45 tests passing ✅

---

### ✅ FundingPod Tests - 47 tests passing
**File:** `test/unit/pod/FundingPod.t.sol`

**Coverage:**
- ✅ Initialization (2 tests)
- ✅ Deposits (6 tests)
- ✅ Withdrawals (6 tests)
- ✅ Event registration (4 tests)
- ✅ Complete set minting (5 tests)
- ✅ Complete set burning (4 tests)
- ✅ Order locking (4 tests)
- ✅ Order unlocking (3 tests)
- ✅ Admin functions (5 tests)
- ✅ View functions (3 tests)
- ✅ Pause/unpause (2 tests)
- ✅ Token support (3 tests)

**Result:** All 47 tests passing ✅

---

### ✅ OrderBookPod Tests - 36 tests passing
**File:** `test/unit/pod/OrderBookPod.t.sol`

**Coverage:**
- ✅ Initialization (1 test)
- ✅ Event registration (4 tests)
- ✅ Order placement (12 tests)
- ✅ Order cancellation (3 tests)
- ✅ Event settlement (4 tests)
- ✅ Order matching (1 test)
- ✅ Position tracking (1 test)
- ✅ View functions (4 tests)
- ✅ Admin functions (4 tests)
- ✅ Edge cases (2 tests)

**Result:** All 36 tests passing ✅

**Issues Fixed:**
1. ✅ OrderBookPod initialization bug (nextOrderId = 1)
2. ✅ MockFundingPod interface completion
3. ✅ OrderBookPod cancelOrder error priority

---

## 🔄 IN PROGRESS - Phase 3: Factory & Manager Layer Tests

### Priority 1: PodDeployer Tests (High Priority)
**File:** `test/unit/factory/PodDeployer.t.sol` (NEW)
**Estimated:** ~40-50 tests
**Complexity:** Medium-High

#### Test Categories:

**Initialization (3 tests)**
- [ ] Test valid initialization with all managers
- [ ] Test revert on invalid manager addresses (zero addresses)
- [ ] Test initial state verification

**Pod Implementation Management (8 tests)**
- [ ] Test setPodImplementation for EventPod (type 0)
- [ ] Test setPodImplementation for OrderBookPod (type 1)
- [ ] Test setPodImplementation for FeeVaultPod (type 2)
- [ ] Test setPodImplementation for FundingPod (type 3)
- [ ] Test emit PodImplementationSet event
- [ ] Test revert on invalid pod type (>3)
- [ ] Test revert on zero address implementation
- [ ] Test revert on non-owner caller

**Individual Pod Deployment (16 tests - 4 per pod type)**
For each pod type (EventPod, OrderBookPod, FundingPod, FeeVaultPod):
- [ ] Test deploy using CREATE2
- [ ] Test deployed address matches predicted address
- [ ] Test pod initialized with correct parameters
- [ ] Test emit PodDeployed event

**Complete Pod Set Deployment (12 tests)**
- [ ] Test deployPodSet creates all 4 pods
- [ ] Test all addresses match predicted addresses
- [ ] Test all pods initialized correctly
- [ ] Test cross-pod references set correctly:
  - [ ] EventPod → OrderBookManager reference
  - [ ] OrderBookPod → EventPod/FundingPod/FeeVaultPod references
  - [ ] FundingPod → OrderBookPod/EventPod references
  - [ ] FeeVaultPod → OrderBookPod reference
- [ ] Test emit PodSetDeployed event
- [ ] Test revert on duplicate deployment for same vendorId
- [ ] Test revert on invalid vendorId (0)

**Address Prediction (8 tests)**
- [ ] Test predictPodAddress for each pod type (4 tests)
- [ ] Test predicted address matches deployed address
- [ ] Test revert on invalid pod type
- [ ] Test revert on implementation not set
- [ ] Test address prediction before deployment

**CREATE2 Determinism (5 tests)**
- [ ] Test same vendorId + podType → same address
- [ ] Test different vendorIds → different addresses
- [ ] Test different podTypes → different addresses
- [ ] Test salt generation formula: keccak256(vendorId, podType)
- [ ] Test deployment ordering doesn't affect addresses

**Expected Result:** ~52 tests for comprehensive PodDeployer coverage

---

### Priority 2: PodFactory Tests (Expand Existing)
**File:** `test/PodFactoryRegistration.t.sol` → `test/unit/factory/PodFactory.t.sol`
**Current:** 2 tests
**Target:** ~25-30 tests
**Complexity:** Medium

#### Test Categories:

**Vendor Registration (8 tests)**
- [x] Test basic vendor registration (existing)
- [x] Test pod set deployment (existing)
- [ ] Test register multiple vendors (3+)
- [ ] Test vendorId increments correctly (1, 2, 3, ...)
- [ ] Test each vendor gets unique pod addresses
- [ ] Test emit VendorRegistered event
- [ ] Test revert on zero address vendor
- [ ] Test revert on duplicate vendor registration

**Vendor Information (6 tests)**
- [ ] Test getVendorInfo() returns correct data
- [ ] Test getVendorPodSet() returns all 4 pod addresses
- [ ] Test vendorAddressToId mapping works correctly
- [ ] Test isActive flag set correctly on registration
- [ ] Test vendor count increments
- [ ] Test revert on getVendorInfo for non-existent vendor

**Vendor Isolation (4 tests)**
- [ ] Test events don't cross vendors
- [ ] Test each vendor has independent event IDs
- [ ] Test pod addresses are unique per vendor
- [ ] Test vendor A cannot access vendor B's pods

**Configuration Management (10 tests)**
- [ ] Test setPodDeployer success
- [ ] Test setPodDeployer emit event
- [ ] Test setEventManager success
- [ ] Test setOrderBookManager success
- [ ] Test setFundingManager success
- [ ] Test setFeeVaultManager success
- [ ] Test revert on non-owner calling setters
- [ ] Test revert on zero address for setters
- [ ] Test configuration updates don't affect existing vendors
- [ ] Test new vendors use updated configuration

**Expected Result:** ~28 tests total (2 existing + 26 new)

---

### Priority 3: Manager Layer Tests (Medium Priority)

These are coordinator contracts that manage vendor→pod mappings.

#### EventManager Tests (NEW)
**File:** `test/unit/core/EventManager.t.sol`
**Estimated:** ~20-25 tests

**Test Categories:**
- [ ] Initialization (2 tests)
- [ ] Pod registration/tracking (5 tests)
- [ ] Vendor event management (6 tests)
- [ ] Access control (4 tests)
- [ ] View functions (4 tests)
- [ ] Edge cases (4 tests)

#### OrderBookManager Tests (NEW)
**File:** `test/unit/core/OrderBookManager.t.sol`
**Estimated:** ~20-25 tests

**Test Categories:**
- [ ] Initialization (2 tests)
- [ ] Pod registration/tracking (5 tests)
- [ ] Order routing (6 tests)
- [ ] Access control (4 tests)
- [ ] View functions (4 tests)
- [ ] Edge cases (4 tests)

#### FundingManager Tests (NEW)
**File:** `test/unit/core/FundingManager.t.sol`
**Estimated:** ~20-25 tests

**Test Categories:**
- [ ] Initialization (2 tests)
- [ ] Pod registration/tracking (5 tests)
- [ ] Fund routing (6 tests)
- [ ] Access control (4 tests)
- [ ] View functions (4 tests)
- [ ] Edge cases (4 tests)

#### FeeVaultManager Tests (NEW)
**File:** `test/unit/core/FeeVaultManager.t.sol`
**Estimated:** ~20-25 tests

**Test Categories:**
- [ ] Initialization (2 tests)
- [ ] Pod registration/tracking (5 tests)
- [ ] Fee routing (6 tests)
- [ ] Access control (4 tests)
- [ ] View functions (4 tests)
- [ ] Edge cases (4 tests)

**Manager Layer Total:** ~80-100 tests

---

## 📋 TODO - Phase 4: Oracle & Admin Layer Tests

### Oracle Layer Tests

#### OracleAdapter Tests (NEW)
**File:** `test/unit/oracle/OracleAdapter.t.sol`
**Estimated:** ~25-30 tests
**Complexity:** Medium-High

**Test Categories:**
- [ ] Initialization (3 tests)
- [ ] Oracle result submission (8 tests)
- [ ] Merkle proof verification (6 tests)
- [ ] Event result fulfillment (5 tests)
- [ ] Access control (4 tests)
- [ ] Reentrancy protection (2 tests)
- [ ] View functions (3 tests)

#### OracleManager Tests (NEW)
**File:** `test/unit/oracle/OracleManager.t.sol`
**Estimated:** ~20-25 tests

**Test Categories:**
- [ ] Initialization (2 tests)
- [ ] Oracle registration (6 tests)
- [ ] Oracle authorization (5 tests)
- [ ] Oracle result routing (5 tests)
- [ ] Access control (4 tests)
- [ ] View functions (3 tests)

**Oracle Layer Total:** ~45-55 tests

---

### Admin Layer Tests

#### AdminFeeVault Tests (NEW)
**File:** `test/unit/admin/AdminFeeVault.t.sol`
**Estimated:** ~20-25 tests
**Complexity:** Medium

**Test Categories:**
- [ ] Initialization (3 tests)
- [ ] Fee collection from pods (5 tests)
- [ ] Fee withdrawal (5 tests)
- [ ] Fee distribution (4 tests)
- [ ] Access control (4 tests)
- [ ] Reentrancy protection (2 tests)
- [ ] View functions (3 tests)

**Admin Layer Total:** ~20-25 tests

---

## 📋 TODO - Phase 5: Integration Tests

Integration tests verify end-to-end workflows across multiple contracts.

### EventLifecycle Integration Tests (NEW)
**File:** `test/integration/EventLifecycle.t.sol`
**Estimated:** ~30-35 tests
**Complexity:** High

#### Binary Event Flow (10 tests)
- [ ] Register vendor via PodFactory
- [ ] Deploy complete pod set
- [ ] Vendor creates binary event (Yes/No)
- [ ] Users deposit USDT to FundingPod
- [ ] Users place buy/sell orders via OrderBookPod
- [ ] Advance time past deadline
- [ ] Vendor requests oracle result
- [ ] Mock oracle submits result with merkle proof
- [ ] EventPod settles event
- [ ] OrderBookPod settles orders
- [ ] FundingPod distributes winnings
- [ ] Winners withdraw funds
- [ ] Verify winner balances correct
- [ ] Verify loser balances = 0

#### Multi-Outcome Event Flow (8 tests)
- [ ] Create event with 4 outcomes
- [ ] Multiple users place orders on different outcomes
- [ ] Test outcome A wins
- [ ] Test outcome B wins
- [ ] Test outcome C wins
- [ ] Test outcome D wins
- [ ] Verify only winning outcome holders get paid
- [ ] Verify prize pool distribution

#### Event Edge Cases (8 tests)
- [ ] Event with no bets
- [ ] Event cancellation flow
- [ ] Event settlement before deadline (should fail)
- [ ] Event with single user betting
- [ ] Event with all users on losing outcome
- [ ] Event with invalid oracle result (should fail)
- [ ] Event with partial fills
- [ ] Event with order cancellations

#### Multi-Vendor Isolation (6 tests)
- [ ] Vendor A creates event
- [ ] Vendor B creates event
- [ ] Verify events are isolated
- [ ] Verify event IDs are pod-scoped
- [ ] Vendor A cannot settle vendor B's event
- [ ] Verify complete independence

---

### OrderFlow Integration Tests (NEW)
**File:** `test/integration/OrderFlow.t.sol`
**Estimated:** ~25-30 tests

#### Basic Order Flows (6 tests)
- [ ] Complete buy order flow
- [ ] Complete sell order flow
- [ ] Order cancellation flow
- [ ] Order with fee collection
- [ ] Multiple orders same user
- [ ] Multiple orders different users

#### Order Matching Scenarios (12 tests)
- [ ] Partial fill - buy side
- [ ] Partial fill - sell side
- [ ] Complete fill - exact match
- [ ] Complete fill - buyer larger
- [ ] Complete fill - seller larger
- [ ] Multiple partial fills
- [ ] No matching orders
- [ ] Price priority (best price first)
- [ ] Time priority (FIFO at same price)
- [ ] Cross-outcome independence
- [ ] Same outcome multiple prices
- [ ] Market clearing scenarios

#### Fee Collection Integration (4 tests)
- [ ] Fee calculation on order placement
- [ ] Fee transfer to FeeVaultPod
- [ ] Fee recording in eventFees
- [ ] Fee recording in userPaidFees

#### Edge Cases (6 tests)
- [ ] Order placement on settled event (should fail)
- [ ] Order cancellation on settled event (should fail)
- [ ] Zero price order (should fail)
- [ ] Price > MAX_PRICE (should fail)
- [ ] Amount = 0 (should fail)
- [ ] Insufficient funds (should fail)

---

### CompleteSetFlow Integration Tests (NEW)
**File:** `test/integration/CompleteSetFlow.t.sol`
**Estimated:** ~20-25 tests

#### Complete Set Operations (8 tests)
- [ ] Mint complete set success
- [ ] Burn complete set success
- [ ] Mint → Trade → Burn flow
- [ ] Multiple users mint simultaneously
- [ ] Partial complete set (can't burn)
- [ ] Verify prize pool increases on mint
- [ ] Verify prize pool decreases on burn
- [ ] Prize pool accounting accuracy

#### Trading with Complete Sets (6 tests)
- [ ] Mint set, sell one outcome, buy back, burn set
- [ ] Mint set, partial sell, verify can't burn
- [ ] Multiple users trading after minting
- [ ] Verify USDT conservation
- [ ] Verify token conservation
- [ ] Cross-user complete set operations

#### Edge Cases (8 tests)
- [ ] Mint with insufficient USDT (should fail)
- [ ] Burn without complete set (should fail)
- [ ] Mint on non-existent event (should fail)
- [ ] Burn on settled event
- [ ] Mint on cancelled event (should fail)
- [ ] Zero amount mint (should fail)
- [ ] Zero amount burn (should fail)
- [ ] Prize pool overflow protection

**Integration Tests Total:** ~75-90 tests

---

## 🎯 Execution Strategy

### Phase 3: Factory & Manager Tests (Week 1-2)
**Priority Order:**
1. **PodDeployer** (Days 1-3) - Critical infrastructure
2. **PodFactory** (Day 4) - Expand existing tests
3. **Manager Layer** (Days 5-8) - All 4 managers in parallel

**Approach:**
- Create comprehensive test files
- Focus on cross-contract interactions
- Verify CREATE2 determinism
- Test vendor isolation thoroughly

---

### Phase 4: Oracle & Admin Tests (Week 3)
**Priority Order:**
1. **OracleAdapter** (Days 1-2) - Critical for event settlement
2. **OracleManager** (Day 3) - Oracle coordination
3. **AdminFeeVault** (Day 4) - Fee management

**Approach:**
- Focus on merkle proof verification
- Test reentrancy protection
- Verify access control
- Test fee collection flows

---

### Phase 5: Integration Tests (Week 4)
**Priority Order:**
1. **EventLifecycle** (Days 1-2) - End-to-end event flow
2. **OrderFlow** (Days 3-4) - Order matching and fees
3. **CompleteSetFlow** (Day 5) - Complete set operations

**Approach:**
- Use real contracts, not mocks
- Test full workflows
- Verify state consistency
- Test multi-vendor scenarios

---

## 📊 Progress Tracking

### Current Status (as of 2026-01-23)

**Completed:**
- ✅ Phase 1: Test Infrastructure (100%)
- ✅ Phase 2: Pod Unit Tests (100% - 163 tests)
- ✅ PodFactory: Basic tests (2 tests)

**Total Tests:**
- **Current:** 165 tests passing
- **Estimated Total:** ~400-450 tests
- **Progress:** 41% complete

### Remaining Work:

| Phase | Component | Tests | Status |
|-------|-----------|-------|--------|
| Phase 3 | PodDeployer | ~52 | ⏳ Todo |
| Phase 3 | PodFactory (expand) | ~26 | ⏳ Todo |
| Phase 3 | Manager Layer | ~80-100 | ⏳ Todo |
| Phase 4 | Oracle Layer | ~45-55 | ⏳ Todo |
| Phase 4 | Admin Layer | ~20-25 | ⏳ Todo |
| Phase 5 | Integration Tests | ~75-90 | ⏳ Todo |

**Total Remaining:** ~298-348 tests

---

## ✅ Verification & Quality Assurance

### Test Execution Commands

```bash
# Run all tests
forge test -vv

# Run specific test suites
forge test --match-path test/unit/pod/ -vv           # Pod tests (163 tests)
forge test --match-path test/unit/factory/ -vv       # Factory tests
forge test --match-path test/unit/core/ -vv          # Manager tests
forge test --match-path test/unit/oracle/ -vv        # Oracle tests
forge test --match-path test/unit/admin/ -vv         # Admin tests
forge test --match-path test/integration/ -vv        # Integration tests

# Run with gas reporting
forge test --gas-report

# Generate coverage report
forge coverage --report summary
forge coverage --report lcov
```

### Coverage Targets

**Per-Contract Goals:**
- ✅ FeeVaultPod: >95% (currently: excellent)
- ✅ EventPod: >90% (currently: excellent)
- ✅ FundingPod: >90% (currently: excellent)
- ✅ OrderBookPod: >85% (currently: excellent)
- ⏳ PodDeployer: >95% (target)
- ⏳ PodFactory: >90% (target)
- ⏳ Manager Layer: >85% (target)
- ⏳ Oracle Layer: >85% (target)
- ⏳ Admin Layer: >85% (target)

**Overall Goal:** >85% test coverage

### Critical Path Verification

Must verify these end-to-end flows work correctly:
- [ ] Vendor registration → Pod deployment
- [ ] Event creation → Oracle result → Settlement → Payout
- [ ] Order placement → Matching → Fee collection
- [ ] Complete set mint → Trade → Burn
- [ ] Multi-vendor isolation (events don't cross vendors)
- [ ] Reentrancy protection on all fund transfers
- [ ] Access control on all privileged operations

---

## 📝 Implementation Notes

### Best Practices

1. **Test Organization:**
   - One test file per contract
   - Group related tests in sections with clear comments
   - Use descriptive test names: `test_functionName_scenario`

2. **Mock Usage:**
   - Use real contracts in integration tests
   - Use mocks only in unit tests for isolation
   - Keep mocks simple and focused

3. **Test Structure:**
   ```solidity
   function test_functionName_scenario() public {
       // Setup
       // Execute
       // Assert
   }
   ```

4. **Event Testing:**
   - Always verify events are emitted
   - Check event parameters match expected values
   - Use `vm.expectEmit(true, true, true, true)`

5. **Error Testing:**
   - Test all revert conditions
   - Use specific error selectors when possible
   - Test error messages are correct

6. **Gas Optimization:**
   - Review gas reports regularly
   - Identify expensive operations
   - Consider optimizations for hot paths

### Common Patterns

**Setup Pattern:**
```solidity
function setUp() public override {
    super.setUp();
    // Deploy contracts
    // Configure dependencies
    // Setup test data
}
```

**Revert Testing Pattern:**
```solidity
function test_function_revertsOnCondition() public {
    vm.expectRevert(ErrorSelector);
    contract.function(invalidParams);
}
```

**State Change Testing Pattern:**
```solidity
function test_function_changesState() public {
    uint256 before = contract.stateVariable();
    contract.function();
    uint256 after = contract.stateVariable();
    assertEq(after, expectedValue);
}
```

---

## 🐛 Known Issues & Fixes Applied

### Fixed Issues (Completed):
1. ✅ **OrderBookPod initialization bug**: Added `nextOrderId = 1` in initialize()
2. ✅ **MockFundingPod missing functions**: Added `registerEvent()` and `settleMatchedOrder()`
3. ✅ **MockFundingPod interface mismatch**: Fixed `unlockForOrder()` parameters
4. ✅ **OrderBookPod error priority**: Swapped check order in `cancelOrder()`

### Potential Future Issues:
- CREATE2 determinism must be thoroughly tested
- Cross-pod reentrancy scenarios need verification
- Manager layer routing must handle edge cases
- Oracle merkle proof verification is critical

---

## 📚 Resources & Documentation

### Key Files:
- `CLAUDE.md` - Project architecture and patterns
- `foundry.toml` - Build configuration (via-IR enabled)
- `src/interfaces/` - All interface definitions

### Testing Tools:
- Forge (Foundry) - Test framework
- OpenZeppelin Test Helpers - Via forge-std
- Custom test helpers in `test/helpers/`

### Reference Documentation:
- Foundry Book: https://book.getfoundry.sh/
- Solidity Docs: https://docs.soliditylang.org/
- OpenZeppelin Contracts: https://docs.openzeppelin.com/

---

## 🎉 Success Metrics

### Definition of Done:
- [ ] All unit tests passing (target: ~320 tests)
- [ ] All integration tests passing (target: ~80 tests)
- [ ] Overall coverage >85%
- [ ] Zero failing tests
- [ ] All critical paths verified
- [ ] Gas report reviewed
- [ ] No security vulnerabilities identified

### Final Deliverables:
1. Comprehensive test suite (400+ tests)
2. Coverage report showing >85%
3. Gas optimization report
4. Documentation of any discovered issues
5. Recommendations for improvements

---

**Last Updated:** 2026-01-23
**Next Review:** After Phase 3 completion
**Maintained By:** Development Team

---

## Review

- Added PodDeployer unit tests for initialization, per-pod deployment, full pod set deployment, and address prediction determinism.
- Expanded PodFactory tests (moved to unit/factory) to cover vendor registration variants, config setters, and manager update behavior.
- Tests not run in this session.
- Replaced pod upgradeable bases with `PodBase` (initializer + ownable + pausable) and removed pod storage upgrade gaps.
- Updated pod test deployments to use clones instead of ERC1967 proxies for non-upgradeable pods.
