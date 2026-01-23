# Implementation Plan: OutcomeIndex Refactoring & Architecture Cleanup

## Overview
This plan covers three major refactoring tasks for the vendor-based pod prediction market architecture:

1. **Phase 1**: Rename `outcomeId` → `outcomeIndex` and change type to `uint8` throughout entire codebase
2. **Phase 2**: Simplify event outcome storage (remove redundant data structures)
3. **Phase 3**: Extract user-facing functions from Managers to Pods (proper separation of concerns)

## 🔴 CRITICAL REQUIREMENTS

### Phase 1 Non-Negotiables
- ✅ **EVERY** occurrence of outcome identifier MUST be `uint8` (NO exceptions)
- ✅ This includes: function parameters, return values, storage fields, mapping keys, event parameters, local variables, loop counters
- ✅ Search thoroughly - missing even ONE will cause compilation failures
- ✅ Zero tolerance: If ANY outcome-related item remains as `uint256`, the refactoring is incomplete

### General Requirements
- ✅ Test after each phase before proceeding to next phase
- ✅ Maintain backward compatibility where possible (Phase 3 uses deprecation, not removal)
- ✅ This is a breaking change requiring redeployment (storage layout changes)

---

## PHASE 1: Rename outcomeId → outcomeIndex, Change to uint8

**Goal:** Standardize naming and improve gas efficiency by using uint8 for all outcome identifiers.

**Context:** Currently the codebase uses `outcomeId` (uint256) inconsistently. Since max outcomes is 32, uint8 is sufficient (max 255). This improves semantics (it's an array index) and reduces gas costs.

---

### Step 1.1: Update Interface Files

#### 📄 File: `src/interfaces/event/IEventPod.sol`

**Changes needed:**
- [ ] Line 34: Event struct - Change `uint256 winningOutcomeIndex` → `uint8 winningOutcomeIndex`
- [ ] Line 46: EventSettled event - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Line 52: OracleResultReceived event - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Line 93: settleEvent() function - Change parameter: `settleEvent(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof)`
- [ ] Line 124: getOutcome() function - Change parameter: `getOutcome(uint256 eventId, uint8 outcomeIndex)`

---

#### 📄 File: `src/interfaces/event/IOrderBookPod.sol`

**Changes needed:**
- [ ] Line 21: Order struct - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 36: OrderPlaced event - Change parameter to `uint8 outcomeIndex`
- [ ] Line 46: OrderMatched event - Change parameter to `uint8 outcomeIndex`
- [ ] Line 53: EventSettled event - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Line 58: OutcomeNotSupported error - Change to: `OutcomeNotSupported(uint256 eventId, uint8 outcomeIndex)`
- [ ] Line 66: OutcomeMismatch error - Change to: `OutcomeMismatch(uint8 outcomeIndex1, uint8 outcomeIndex2)`
- [ ] Line 80: placeOrder() function - Change parameter: `uint8 outcomeIndex` (rename from outcomeId)
- [ ] Line 89: settleEvent() function - Change parameter: `settleEvent(uint256 eventId, uint8 winningOutcomeIndex)`
- [ ] Line 93: getBestBid() function - Change parameter: `getBestBid(uint256 eventId, uint8 outcomeIndex)`
- [ ] Line 95: getBestAsk() function - Change parameter: `getBestAsk(uint256 eventId, uint8 outcomeIndex)`
- [ ] Line 111: getPosition() function - Change parameter: `getPosition(uint256 eventId, uint8 outcomeIndex, address user)`

---

#### 📄 File: `src/interfaces/event/IFundingPod.sol`

**Changes needed:**
- [ ] Line 28: FundsLocked event - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 33: FundsUnlocked event - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 42: EventSettled event - Change `uint256 winningOutcomeId` → `uint8 winningOutcomeIndex`
- [ ] Line 59: LongTransferred event - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 71: InvalidWinningOutcome error - Change to: `InvalidWinningOutcome(uint256 eventId, uint8 outcomeIndex)`
- [ ] Line 72: InsufficientLongPosition error - Change to: `InsufficientLongPosition(..., uint8 outcomeIndex)`
- [ ] Line 144: lockForOrder() function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 162: unlockForOrder() function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 186: settleMatchedOrder() function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 199: settleEvent() function - Change `uint256 winningOutcomeId` → `uint8 winningOutcomeIndex`
- [ ] Line 230: getLongPosition() function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Line 249: getOrderLockedLong() function - Change `uint256 outcomeId` → `uint8 outcomeIndex`

---

#### 📄 File: `src/interfaces/event/IFeeVaultPod.sol`

- [ ] **Verify:** No outcome-related parameters (confirmed from read - no changes needed)

---

### Step 1.2: Update Storage Contract Files

#### 📄 File: `src/event/pod/EventPodStorage.sol`

**Changes needed:**
- [ ] Find Event struct definition
- [ ] Change `winningOutcomeIndex` field type: `uint256` → `uint8`
- [ ] Search entire file for any other outcome references - verify all are uint8

---

#### 📄 File: `src/event/pod/OrderBookPodStorage.sol`

**🔴 CRITICAL: ALL mappings with outcome dimension must be uint8**

**Changes needed:**
- [ ] Find `supportedOutcomes` mapping - Change to: `mapping(uint256 => mapping(uint8 => bool)) public supportedOutcomes;`
- [ ] Find `positions` mapping - Change to: `mapping(uint256 => mapping(uint8 => mapping(address => uint256))) public positions;`
- [ ] Find `positionHolders` mapping - Change to: `mapping(uint256 => mapping(uint8 => address[])) internal positionHolders;`
- [ ] Find `isPositionHolder` mapping - Change to: `mapping(uint256 => mapping(uint8 => mapping(address => bool))) internal isPositionHolder;`
- [ ] Find `eventResults` mapping - Change to: `mapping(uint256 => uint8) public eventResults;`
- [ ] Find Order struct - Change field: `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Find OutcomeOrderBook struct - Verify all outcome fields are uint8
- [ ] Find EventOrderBook struct - Check for any outcome references, ensure uint8
- [ ] **Search entire file for "outcomeId"** - should find ZERO after renaming
- [ ] **Search entire file for "uint256"** - verify none are outcome-related (all should be uint8)

---

#### 📄 File: `src/event/pod/FundingPodStorage.sol`

**🔴 CRITICAL: ALL mappings with outcome dimension must be uint8**

**Changes needed:**
- [ ] Find `longPositions` mapping - Change to:
  ```solidity
  mapping(address => mapping(address => mapping(uint256 => mapping(uint8 => uint256)))) public longPositions;
  // user → token → eventId → outcomeIndex → amount
  ```
- [ ] Find `orderLockedLong` mapping - Change to:
  ```solidity
  mapping(uint256 => mapping(uint256 => mapping(uint8 => uint256))) public orderLockedLong;
  // orderId → eventId → outcomeIndex → amount
  ```
- [ ] **Search entire file for "outcomeId"** - should find ZERO after renaming
- [ ] Search for any other outcome references - all must be uint8

---

### Step 1.3: Update Implementation Files (Pods)

#### 📄 File: `src/event/pod/EventPod.sol`

**Changes needed:**
- [ ] Find `fulfillResult()` function - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Find `settleEvent()` function - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Find `_settleEvent()` internal function - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Find outcome validation logic - Update to:
  ```solidity
  require(winningOutcomeIndex < uint8(evt.outcomes.length), "Invalid winningOutcomeIndex");
  ```
- [ ] Find call to `OrderBookPod.settleEvent()` - Pass `uint8 winningOutcomeIndex`
- [ ] Find `getOutcome()` function - Change parameter to `uint8 outcomeIndex`
- [ ] **Search for ALL local variables with "outcome"** - verify all are uint8
- [ ] **Search for ALL function parameters with "outcome"** - verify all are uint8

---

#### 📄 File: `src/event/pod/OrderBookPod.sol`

**🔴 CRITICAL: This is the most complex file - be extremely thorough**

**Changes needed:**
- [ ] Find `placeOrder()` function - Change parameter: `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Find `settleEvent()` function - Change parameter to `uint8 winningOutcomeIndex`
- [ ] Find ALL mapping accesses with outcomes - ensure uint8:
  - `supportedOutcomes[eventId][outcomeIndex]` where outcomeIndex is uint8
  - `positions[eventId][outcomeIndex][user]` where outcomeIndex is uint8
  - `positionHolders[eventId][outcomeIndex]` where outcomeIndex is uint8
  - `isPositionHolder[eventId][outcomeIndex][user]` where outcomeIndex is uint8
- [ ] Find `addEvent()` function - Change loop counter:
  ```solidity
  for (uint8 i = 0; i < outcomeCount; i++) {
      supportedOutcomes[eventId][i] = true;
      // ...
  }
  ```
- [ ] Find Order struct instantiation - Use: `outcomeIndex: outcomeIndex` where outcomeIndex is uint8
- [ ] Find ALL event emissions - ensure outcome parameters are uint8:
  - `emit OrderPlaced(..., outcomeIndex, ...)` where outcomeIndex is uint8
  - `emit OrderMatched(..., outcomeIndex, ...)` where outcomeIndex is uint8
  - `emit EventSettled(..., winningOutcomeIndex)` where winningOutcomeIndex is uint8
- [ ] Find ALL internal functions (_matchOrder, _addToOrderBook, _executeMatch, etc.)
  - Change ALL outcome parameters to uint8
- [ ] **Search entire file for "outcomeId"** - should find ZERO after renaming
- [ ] **Search entire file for "uint256"** - verify NONE are outcome-related

---

#### 📄 File: `src/event/pod/FundingPod.sol`

**Changes needed:**
- [ ] Find `lockForOrder()` function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Find `unlockForOrder()` function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Find `settleMatchedOrder()` function - Change `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Find `mintCompleteSet()` function - Verify outcome loop uses uint8:
  ```solidity
  for (uint8 i = 0; i < outcomeCount; i++) {
      longPositions[user][token][eventId][i] += amount;
  }
  ```
- [ ] Find `burnCompleteSet()` function - Verify outcome loop uses uint8
- [ ] Find `registerEvent()` function - Verify outcome setup uses uint8
- [ ] Find `settleEvent()` function - Change `uint256 winningOutcomeId` → `uint8 winningOutcomeIndex`
- [ ] Find ALL mapping accesses:
  - `longPositions[user][token][eventId][outcomeIndex]` where outcomeIndex is uint8
  - `orderLockedLong[orderId][eventId][outcomeIndex]` where outcomeIndex is uint8
- [ ] Find ALL event emissions - ensure outcome parameters are uint8
- [ ] Find ALL internal functions - change outcome parameters to uint8
- [ ] **Search entire file for "outcomeId"** - should find ZERO after renaming

---

#### 📄 File: `src/event/pod/FeeVaultPod.sol`

- [ ] **Verify:** No outcome-related code (confirmed - no changes needed)

---

### Step 1.4: Update Manager Files

#### 📄 File: `src/event/core/EventManager.sol`

- [ ] Find any functions that pass outcomes to EventPod
- [ ] Change all outcome parameters to `uint8 outcomeIndex`
- [ ] Verify no direct outcome storage in manager (should only route to pods)

---

#### 📄 File: `src/event/core/OrderBookManager.sol`

- [ ] Find `placeOrder()` function - Change parameter: `uint256 outcomeId` → `uint8 outcomeIndex`
- [ ] Update call to pod: `pod.placeOrder(..., outcomeIndex, ...)` where outcomeIndex is uint8
- [ ] Find any other functions passing outcomes to pods - change to uint8

---

#### 📄 File: `src/event/core/FundingManager.sol`

- [ ] Find any functions that pass outcomes to FundingPod
- [ ] Change all outcome parameters to `uint8 outcomeIndex`
- [ ] Verify no direct outcome storage in manager

---

#### 📄 File: `src/event/core/FeeVaultManager.sol`

- [ ] **Verify:** No outcome-related code (likely none)

---

### Step 1.5: Update Test Files

#### 📁 Directory: `test/`

**For EVERY test file:**
- [ ] Search for "outcomeId" in all test files
- [ ] Rename ALL to "outcomeIndex"
- [ ] Change types to `uint8` for all outcome variables
- [ ] Update test assertions for uint8 types
- [ ] Update mock data to use uint8 for outcomes
- [ ] Verify test edge cases:
  - outcomeIndex = 0 (should be valid)
  - outcomeIndex = 31 (should be valid - max)
  - outcomeIndex = 32 (should fail validation)
  - outcomeIndex = 255 (uint8 max, should fail - over limit)

---

### Step 1.6: Phase 1 Validation

**Before proceeding to Phase 2, verify:**

#### Search Validation
- [ ] Run: `grep -r "outcomeId" src/` - should find **ZERO** occurrences
- [ ] Run: `grep -r "outcomeIndex.*uint256" src/` - should find ZERO
- [ ] Run: `grep -r "uint256.*outcome" src/` - should find ZERO (all should be uint8)
- [ ] Manual review: Open each modified file and verify all outcome types are uint8

#### Build Validation
- [ ] Run: `forge clean` to clear artifacts
- [ ] Run: `forge build --via-ir` to compile
- [ ] Verify: NO compilation errors
- [ ] Verify: NO compiler warnings about type mismatches

#### Test Validation
- [ ] Run: `forge test` to run all tests
- [ ] Verify: ALL tests pass
- [ ] Optional: `forge test --gas-report` to check gas improvements

---

## PHASE 2: Simplify Event Outcome Storage

**Goal:** Remove redundant outcome storage. Outcomes are just array indices 0..N-1, so storing a list is unnecessary.

**Context:** Currently `EventOrderBook` stores `uint8[] supportedOutcomes` which just contains [0,1,2,...,N-1]. This is redundant - we only need the count.

---

### Step 2.1: Review Current Storage

#### 📄 File: `src/event/pod/EventPodStorage.sol`

- [ ] Verify Event struct contains: `Outcome[] outcomes` array (the actual outcome data)
- [ ] Confirm no redundant outcome ID storage exists
- [ ] Optional: Consider adding `uint8 outcomeCount` field to Event struct for quick validation (not required)

---

#### 📄 File: `src/event/pod/OrderBookPodStorage.sol`

- [ ] Review EventOrderBook struct - should currently have:
  ```solidity
  struct EventOrderBook {
      mapping(uint8 => OutcomeOrderBook) outcomeOrderBooks;
      uint8[] supportedOutcomes;  // ← This is redundant
  }
  ```

---

### Step 2.2: Optimize EventOrderBook Struct

#### 📄 File: `src/event/pod/OrderBookPodStorage.sol`

**Changes needed:**
- [ ] Find EventOrderBook struct definition
- [ ] Remove field: `uint8[] supportedOutcomes;`
- [ ] Add field: `uint8 outcomeCount;`

**Target structure:**
```solidity
struct EventOrderBook {
    mapping(uint8 => OutcomeOrderBook) outcomeOrderBooks;
    uint8 outcomeCount;  // Just store count, indices are 0..outcomeCount-1
}
```

**Note:** This is a storage layout change requiring redeployment.

---

### Step 2.3: Update OrderBookPod.addEvent()

#### 📄 File: `src/event/pod/OrderBookPod.sol`

**Find the `addEvent()` function (around lines 190-199):**

**Current implementation:**
```solidity
function addEvent(uint256 eventId, uint8 outcomeCount) external {
    require(!supportedEvents[eventId], "OrderBookPod: event exists");
    require(outcomeCount > 0 && outcomeCount <= 32, "OrderBookPod: invalid outcomeCount");
    supportedEvents[eventId] = true;

    EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];

    for (uint8 i = 0; i < outcomeCount; i++) {
        supportedOutcomes[eventId][i] = true;
        eventOrderBook.supportedOutcomes.push(i);  // ← Remove this line
    }

    IFundingPod(fundingPod).registerEvent(eventId, outcomeCount);
}
```

**Changes needed:**
- [ ] Remove line: `eventOrderBook.supportedOutcomes.push(i);`
- [ ] Add line: `eventOrderBook.outcomeCount = outcomeCount;` (before loop or after require)
- [ ] Keep the `supportedOutcomes[eventId][i] = true;` mapping (used for O(1) validation)

**Target implementation:**
```solidity
function addEvent(uint256 eventId, uint8 outcomeCount) external {
    require(!supportedEvents[eventId], "OrderBookPod: event exists");
    require(outcomeCount > 0 && outcomeCount <= 32, "OrderBookPod: invalid outcomeCount");
    supportedEvents[eventId] = true;

    EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
    eventOrderBook.outcomeCount = outcomeCount;  // ← Add this

    for (uint8 i = 0; i < outcomeCount; i++) {
        supportedOutcomes[eventId][i] = true;
    }

    IFundingPod(fundingPod).registerEvent(eventId, outcomeCount);
}
```

---

### Step 2.4: Update Validation Logic

#### 📄 File: `src/event/pod/OrderBookPod.sol`

**Changes needed:**
- [ ] Find outcome validation in `placeOrder()` - Ensure it checks:
  ```solidity
  require(outcomeIndex < eventOrderBooks[eventId].outcomeCount, "Invalid outcomeIndex");
  ```
- [ ] Find any code iterating over `supportedOutcomes` array - Replace with `outcomeCount`-based iteration
- [ ] Example: If iterating outcomes, use: `for (uint8 i = 0; i < eventOrderBooks[eventId].outcomeCount; i++)`

---

#### 📄 File: `src/event/pod/EventPod.sol`

- [ ] Find outcome validation in `_settleEvent()` - Ensure:
  ```solidity
  require(winningOutcomeIndex < uint8(evt.outcomes.length), "Invalid winningOutcomeIndex");
  ```

---

### Step 2.5: Phase 2 Validation

**Before proceeding to Phase 3, verify:**

#### Code Review
- [ ] EventOrderBook struct has `uint8 outcomeCount` field (not array)
- [ ] No references to `eventOrderBook.supportedOutcomes.push()`
- [ ] Validation logic uses `outcomeCount` or `outcomes.length`
- [ ] No redundant outcome storage remains

#### Build & Test
- [ ] Run: `forge build` - should compile successfully
- [ ] Run: `forge test` - all tests should pass
- [ ] Optional: Check gas costs (may be slightly improved)

---

## PHASE 3: Extract User-Facing Logic to Pods

**Goal:** Move all user-facing functions from Managers to Pods for proper separation of concerns.

**Context:** Currently users call `FundingManager.depositEthIntoVendorPod(vendorId)` which looks up the pod. This is wrong - Managers should only maintain registries. Users should call pods directly: `FundingPod.depositEth()`.

---

### Step 3.1: Architectural Analysis

**Current (Incorrect) User Flow:**
```
User → FundingManager.depositEthIntoVendorPod(vendorId)
     → Manager looks up pod address
     → Manager calls pod.deposit()
```

**Target (Correct) User Flow:**
```
User → FundingPod.depositEth()
     → Pod handles directly (vendorId is implicit from pod identity)
```

**Manager Responsibilities (Correct):**
- ✅ Maintain vendor → pod address mappings
- ✅ Coordinate pod deployment
- ✅ Provide view functions that query pods
- ❌ NO user-facing transaction functions
- ❌ NO user-level data storage

---

### Step 3.2: Add Direct User Functions to FundingPod

#### 📄 File: `src/event/pod/FundingPod.sol`

**Add these new functions:**

```solidity
/**
 * @notice Direct ETH deposit by user
 */
function depositEth() external payable whenNotPaused nonReentrant {
    require(msg.value > 0, "FundingPod: deposit amount must be greater than 0");

    address user = msg.sender;
    address ethToken = ETHAddress;

    userTokenBalances[user][ethToken] += msg.value;
    tokenBalances[ethToken] += msg.value;

    emit Deposit(user, ethToken, msg.value);
}

/**
 * @notice Direct ERC20 deposit by user
 * @param tokenAddress Token address
 * @param amount Amount to deposit
 */
function depositErc20(IERC20 tokenAddress, uint256 amount) external whenNotPaused nonReentrant {
    require(amount > 0, "FundingPod: deposit amount must be greater than 0");

    address user = msg.sender;

    // Transfer from user to pod
    tokenAddress.safeTransferFrom(user, address(this), amount);

    // Update balances
    userTokenBalances[user][address(tokenAddress)] += amount;
    tokenBalances[address(tokenAddress)] += amount;

    emit Deposit(user, address(tokenAddress), amount);
}

/**
 * @notice Direct withdrawal by user
 * @param tokenAddress Token address
 * @param amount Amount to withdraw
 */
function withdrawDirect(address tokenAddress, uint256 amount) external whenNotPaused nonReentrant {
    address user = msg.sender;

    require(amount > 0, "FundingPod: withdraw amount must be greater than 0");
    require(userTokenBalances[user][tokenAddress] >= amount, "FundingPod: insufficient balance");

    // Update balances
    userTokenBalances[user][tokenAddress] -= amount;
    tokenBalances[tokenAddress] -= amount;

    // Transfer
    if (tokenAddress == ETHAddress) {
        (bool sent, ) = payable(user).call{value: amount}("");
        require(sent, "FundingPod: failed to send ETH");
    } else {
        IERC20(tokenAddress).safeTransfer(user, amount);
    }

    emit Withdrawal(user, tokenAddress, amount);
}

/**
 * @notice Direct mint complete set by user
 * @param eventId Event ID
 * @param tokenAddress Token address
 * @param amount Amount to mint
 */
function mintCompleteSetDirect(uint256 eventId, address tokenAddress, uint256 amount)
    external whenNotPaused nonReentrant
{
    address user = msg.sender;
    // Call existing internal logic
    mintCompleteSet(user, eventId, tokenAddress, amount);
}

/**
 * @notice Direct burn complete set by user
 * @param eventId Event ID
 * @param tokenAddress Token address
 * @param amount Amount to burn
 */
function burnCompleteSetDirect(uint256 eventId, address tokenAddress, uint256 amount)
    external whenNotPaused nonReentrant
{
    address user = msg.sender;
    // Call existing internal logic
    burnCompleteSet(user, eventId, tokenAddress, amount);
}
```

**Changes needed:**
- [ ] Add `depositEth()` function (uses msg.sender directly)
- [ ] Add `depositErc20()` function (uses msg.sender directly)
- [ ] Add `withdrawDirect()` function (uses msg.sender directly)
- [ ] Add `mintCompleteSetDirect()` function (wraps existing internal function)
- [ ] Add `burnCompleteSetDirect()` function (wraps existing internal function)
- [ ] Keep existing internal functions for backward compatibility during transition

---

### Step 3.3: Verify OrderBookPod (Already Correct)

#### 📄 File: `src/event/pod/OrderBookPod.sol`

**Good news:** OrderBookPod ALREADY supports direct user access!

- [ ] Verify `placeOrder()` is public/external and uses `msg.sender` directly
- [ ] Verify `cancelOrder()` is public/external and user-callable
- [ ] **No changes needed** - architecture is already correct

---

### Step 3.4: Add Deprecation Notices to FundingManager

#### 📄 File: `src/event/core/FundingManager.sol`

**Strategy:** Keep functions for backward compatibility but mark as deprecated.

**Add new event (at top of contract):**
```solidity
event DeprecatedFunctionUsed(string functionName, string recommendation);
```

**Update each user-facing function:**

1. **depositEthIntoVendorPod():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use FundingPod.depositEth() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("depositEthIntoVendorPod", "Use FundingPod.depositEth() directly");`

2. **depositErc20IntoVendorPod():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use FundingPod.depositErc20() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("depositErc20IntoVendorPod", "Use FundingPod.depositErc20() directly");`

3. **withdrawFromVendorPod():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use FundingPod.withdrawDirect() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("withdrawFromVendorPod", "Use FundingPod.withdrawDirect() directly");`

4. **mintCompleteSet():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use FundingPod.mintCompleteSetDirect() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("mintCompleteSet", "Use FundingPod.mintCompleteSetDirect() directly");`

5. **burnCompleteSet():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use FundingPod.burnCompleteSetDirect() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("burnCompleteSet", "Use FundingPod.burnCompleteSetDirect() directly");`

**Keep all implementation logic** - just add deprecation markers.

---

### Step 3.5: Add Deprecation Notices to OrderBookManager

#### 📄 File: `src/event/core/OrderBookManager.sol`

**Add new event (at top of contract):**
```solidity
event DeprecatedFunctionUsed(string functionName, string recommendation);
```

**Update each user-facing function:**

1. **placeOrder():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use OrderBookPod.placeOrder() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("placeOrder", "Use OrderBookPod.placeOrder() directly");`

2. **cancelOrder():**
   - [ ] Add NatSpec comment: `@notice [DEPRECATED] Use OrderBookPod.cancelOrder() directly`
   - [ ] Add emit: `emit DeprecatedFunctionUsed("cancelOrder", "Use OrderBookPod.cancelOrder() directly");`

**Keep all implementation logic** - just add deprecation markers.

---

### Step 3.6: Verify Manager Responsibility Boundaries

**Check each manager has NO user-level data storage:**

#### 📄 File: `src/event/core/EventManager.sol`

- [ ] ✅ Has vendor → EventPod mapping (correct)
- [ ] ✅ Has oracle authorization logic (correct)
- [ ] ✅ Coordinates pod deployment (correct)
- [ ] ❌ Search for user balances/positions - should find NONE
- [ ] ✅ View functions only query pods (correct)

---

#### 📄 File: `src/event/core/OrderBookManager.sol`

- [ ] ✅ Has vendor → OrderBookPod mapping (correct)
- [ ] ✅ Coordinates pod deployment (correct)
- [ ] ⚠️ User functions: placeOrder, cancelOrder (should now be deprecated)
- [ ] ❌ Search for user order storage - should find NONE (orders stored in pods)
- [ ] ✅ View functions query pods (correct)

---

#### 📄 File: `src/event/core/FundingManager.sol`

- [ ] ✅ Has vendor → FundingPod mapping (correct)
- [ ] ✅ Coordinates pod deployment (correct)
- [ ] ⚠️ User functions: deposit, withdraw, mint, burn (should now be deprecated)
- [ ] ❌ Search for user balance storage - should find NONE (balances stored in pods)
- [ ] ✅ View functions query pods (correct)

---

#### 📄 File: `src/event/core/FeeVaultManager.sol`

- [ ] ✅ Has vendor → FeeVaultPod mapping (correct)
- [ ] ✅ Coordinates pod deployment (correct)
- [ ] ✅ Admin fee collection (correct - not user-facing)
- [ ] ❌ No user-facing transaction functions (correct)

---

### Step 3.7: Phase 3 Validation

**Before completing, verify:**

#### Functionality
- [ ] FundingPod has 5 new direct user functions (depositEth, depositErc20, withdrawDirect, mintCompleteSetDirect, burnCompleteSetDirect)
- [ ] OrderBookPod already allows direct access (verified - no changes needed)
- [ ] Manager user functions marked deprecated (not removed)
- [ ] Manager user functions still work (backward compatibility maintained)

#### Architecture
- [ ] Managers only store vendor→pod mappings (no user data)
- [ ] Pods contain all user-level data and business logic
- [ ] View functions in managers just query pods (acceptable)

#### Build & Test
- [ ] Run: `forge build` - should compile successfully
- [ ] Run: `forge test` - all tests should pass
- [ ] Test direct pod access: deposit, withdraw, placeOrder
- [ ] Test deprecated manager functions still work

---

## FINAL VALIDATION CHECKLIST

**Before considering work complete:**

### Phase 1 Verification
- [ ] Search: `grep -r "outcomeId" src/` returns ZERO
- [ ] Search: `grep -r "outcomeIndex.*uint256" src/` returns ZERO
- [ ] Search: `grep -r "uint256.*outcome" src/` returns ZERO
- [ ] Manual check: ALL outcome types are uint8 in all files

### Phase 2 Verification
- [ ] EventOrderBook has `uint8 outcomeCount` field (not array)
- [ ] No `supportedOutcomes.push()` calls remain
- [ ] Validation uses outcomeCount or outcomes.length

### Phase 3 Verification
- [ ] FundingPod has direct user functions
- [ ] Manager functions marked deprecated
- [ ] Managers have no user-level storage

### Build & Test
- [ ] `forge clean` completes
- [ ] `forge build --via-ir` compiles with no errors
- [ ] `forge test` passes all tests
- [ ] `forge test --gas-report` shows gas improvements (optional)

### Edge Case Testing
- [ ] Test outcomeIndex = 0 (valid)
- [ ] Test outcomeIndex = 31 (valid - max)
- [ ] Test outcomeIndex = 32 (fails validation)
- [ ] Test outcomeIndex = 255 (fails - over limit)
- [ ] Test event with 2 outcomes (minimum)
- [ ] Test event with 32 outcomes (maximum)
- [ ] Test direct pod access (deposit, withdraw, placeOrder)
- [ ] Test deprecated manager functions (backward compatibility)

---

## COMMON PITFALLS & WARNINGS

### ⚠️ Type Conversion Issues

**Watch for:**
- Loop counters: MUST be `uint8` for outcome loops
- Implicit uint256: Comparisons with `array.length` auto-promote (usually OK)
- Missing parameters: Easy to miss outcome params in internal functions

**Best practice:**
- Make EVERY outcome-related item uint8 from the start
- Use explicit casts only when needed: `uint8(outcomes.length)`
- Test boundary conditions (0, 31, 32, 255)

---

### ⚠️ Storage Layout Changes

**CRITICAL:**
- Changing struct field types affects storage layout
- Changing mapping key types requires redeployment
- This refactoring is NOT upgrade-safe without migration
- Requires clean deployment or data migration script

**Impact:**
- All pods must be redeployed
- Cannot upgrade existing deployed pods
- Test data will be lost

---

### ⚠️ Function Signature Changes

**Breaking changes:**
- Changing parameter types changes function selectors
- External integrations will break
- Front-end code must be updated

**Mitigation:**
- Keep deprecated versions for compatibility (Phase 3)
- Update all interfaces before implementations
- Document breaking changes clearly

---

### ⚠️ Testing Gaps

**Don't forget:**
- Test uint8 overflow scenarios (wrapping at 255)
- Test with maximum outcomes (32)
- Test edge case: outcome index 0
- Test cross-pod calls with new types
- Test direct pod access vs manager routing
- Test that deprecated functions still work

---

## SUCCESS CRITERIA

### Functional Requirements
✅ All outcome references use `outcomeIndex` naming
✅ All outcome types are `uint8` (no exceptions)
✅ Events store outcome array without redundant storage
✅ Users can interact directly with pods
✅ Managers only maintain vendor registries
✅ Backward compatibility maintained (deprecated functions work)

### Non-Functional Requirements
✅ Gas costs reduced from uint8 usage
✅ Code semantics improved (index vs id clarity)
✅ Architecture cleaner (manager-pod separation)
✅ All tests passing
✅ No compiler warnings

### Documentation
✅ CLAUDE.md updated with changes
✅ Deprecation warnings in code comments
✅ Direct pod access patterns documented

---

## ESTIMATED EFFORT

### Phase 1: outcomeId → outcomeIndex (uint8)
- **Complexity:** High (touches many files)
- **Risk:** High (missing one instance breaks compilation)
- **Estimated changes:** 50-80 across 15+ files
- **Time:** 3-5 hours

### Phase 2: Storage simplification
- **Complexity:** Medium (focused changes)
- **Risk:** Low (limited scope)
- **Estimated changes:** 5-10 across 2-3 files
- **Time:** 1-2 hours

### Phase 3: Manager-Pod separation
- **Complexity:** Medium (architectural)
- **Risk:** Low (maintains compatibility)
- **Estimated changes:** 15-20 across 3-4 files
- **Time:** 2-3 hours

### Testing & Validation
- **Time:** 1-2 hours

### **Total estimated effort:** 7-12 hours

---

## IMPLEMENTATION STRATEGY

### Recommended Order

1. **Phase 1 First** (foundational - affects everything)
   - Work through: interfaces → storage → implementations → managers → tests
   - Test thoroughly before proceeding
   - This is the most critical phase

2. **Phase 2 Second** (depends on Phase 1 uint8 changes)
   - Simpler changes, focused scope
   - Can be done incrementally
   - Test after completion

3. **Phase 3 Last** (independent of Phases 1 & 2)
   - Architectural changes
   - Safe deprecation approach
   - Can be done in parallel with Phase 2 if desired

### Work Methodology

**For each phase:**
1. Complete ALL changes for that phase
2. Run `forge build` to check compilation
3. Fix any errors before proceeding
4. Run `forge test` to verify functionality
5. Only move to next phase after current phase is validated

**Search and verification:**
- Use `grep` extensively to find all occurrences
- Check EVERY file even if you think it's not affected
- Be thorough - missing one instance causes hours of debugging

---

## REVIEW SECTION

*(To be filled in after implementation)*

### Changes Summary
- List all files modified
- Count of changes per phase
- Any deviations from plan

### Issues Encountered
- Problems found during implementation
- Solutions applied
- Lessons learned

### Test Results
- Compilation status
- Test pass/fail counts
- Gas optimization results

### Follow-up Items
- Any remaining TODOs
- Future improvements
- Technical debt notes

### Documentation Updates
- CLAUDE.md changes
- API documentation updates
- Migration guide (if needed)

---

## NOTES FOR IMPLEMENTER

1. **Be thorough:** Missing even ONE outcomeId reference will cause compilation failures
2. **Test frequently:** Run `forge build` after each major file change
3. **Use search tools:** `grep`, `rg`, IDE search - find ALL occurrences
4. **Follow the order:** Interfaces → Storage → Implementation → Managers → Tests
5. **Don't skip validation:** Complete checklist after each phase before moving forward
6. **Ask questions:** If anything is unclear, stop and clarify before proceeding

**Good luck! This is a significant refactoring but following this plan methodically will ensure success.**
