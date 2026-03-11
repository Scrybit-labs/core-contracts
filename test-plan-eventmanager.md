# EventManager Comprehensive Test Plan

## Overview
Test all possible user operations with EventManager.sol focusing on complete interaction cycles with correct behavior and results.

**Testing Philosophy:**
- Focus: Full user interaction cycles, correct behavior, correct results
- Not concerned: Security, gas efficiency
- Oracle: Use Mock oracle system (MockOracle + MockOracleAdapter)
- Approach: Snapshot-based testing with `baseSnapshot` as foundation

---

## 1. EventManager Operations Analysis

### User-Facing Operations
1. **createEvent()** - Create new prediction market event
2. **updateEventStatus()** - Transition event status (Created → Active, Active → Cancelled)
3. **requestOracleResult()** - Request oracle to provide winning outcome
4. **cancelEvent()** - Cancel event with reason

### Admin Operations
1. **addEventCreator()** - Whitelist event creator
2. **removeEventCreator()** - Remove event creator from whitelist
3. **setOrderBookManager()** - Link OrderBookManager (one-time)
4. **setDefaultOracleAdapter()** - Set default oracle adapter
5. **setEventTypeOracleAdapter()** - Set type-specific oracle adapter
6. **removeEventTypeOracleAdapter()** - Remove type-specific oracle
7. **addAuthorizedOracleAdapter()** - Authorize oracle adapter for callbacks
8. **removeAuthorizedOracleAdapter()** - Deauthorize oracle adapter
9. **pause()** / **unpause()** - Emergency controls

### View Functions
1. **getEvent()** - Get event details
2. **getEvents()** - Get all events
3. **getEventStatus()** - Get event status
4. **getOutcomes()** - Get all outcomes for event
5. **getOutcome()** - Get specific outcome
6. **nextEventId()** - Get next event ID
7. **getOracleAdapterForEvent()** - Get oracle adapter that will be used
8. **getEventOracleAdapter()** - Get oracle adapter that was used
9. **getEventTypeOracleAdapter()** - Get type-specific oracle
10. **isEventCreator()** - Check if address is whitelisted
11. **authorizedOracleAdapters()** - Check if oracle is authorized
12. **eventOracleRequests()** - Get request ID for event

---

## 2. Event Lifecycle State Machine

```
┌─────────┐
│ Created │ (Initial state after createEvent)
└────┬────┘
     │ updateEventStatus(Active)
     ├──────────────────────────────────┐
     │                                  │
     ▼                                  ▼
┌────────┐                        ┌───────────┐
│ Active │                        │ Cancelled │ (Terminal)
└────┬───┘                        └───────────┘
     │ requestOracleResult()
     │ (after deadline)
     │
     │ Oracle fulfills
     │ (after settlementTime)
     ▼
┌─────────┐
│ Settled │ (Terminal)
└─────────┘
```

**Valid Transitions:**
- Created → Active (via updateEventStatus)
- Created → Cancelled (via cancelEvent)
- Active → Cancelled (via cancelEvent)
- Active → Settled (via oracle fulfillResult, automatic)

**Invalid Transitions:**
- Settled → any (terminal state)
- Cancelled → any (terminal state)
- Created → Settled (must go through Active)

---

## 3. Test Scenarios Matrix

### A. Event Creation
| # | Scenario | Expected Result |
|---|----------|----------------|
| 1 | Create event with valid parameters | Success, eventId returned, EventCreated emitted |
| 2 | Create event with 2 outcomes (minimum) | Success |
| 3 | Create event with 32 outcomes (maximum) | Success |
| 4 | Create event with empty title | Revert: "empty title" |
| 5 | Create event with deadline in past | Revert: "deadline must be in future" |
| 6 | Create event with settlementTime before deadline | Revert: "settlementTime must be after deadline" |
| 7 | Create event with 1 outcome | Revert: "at least 2 outcomes required" |
| 8 | Create event with 33 outcomes | Revert: "max 32 outcomes" |
| 9 | Create event with empty eventType | Revert: "event type cannot be empty" |
| 10 | Create event by non-whitelisted creator | Revert: "not authorized" |
| 11 | Create multiple events sequentially | All succeed with incrementing IDs |

### B. Status Transitions
| # | Scenario | Expected Result |
|---|----------|----------------|
| 12 | Activate event (Created → Active) | Success, registers with OrderBookManager |
| 13 | Cancel created event | Success, status = Cancelled |
| 14 | Cancel active event | Success, deactivates in OrderBookManager |
| 15 | Try to activate already active event | Revert: "invalid status transition" |
| 16 | Try to activate settled event | Revert: "invalid status transition" |
| 17 | Try to activate cancelled event | Revert: "invalid status transition" |
| 18 | Try to cancel settled event | Revert: "cannot cancel settled event" |
| 19 | Non-creator tries to update status | Revert: "not event creator" |
| 20 | Owner updates status of any event | Success |

### C. Oracle Integration
| # | Scenario | Expected Result |
|---|----------|----------------|
| 21 | Request oracle result after deadline | Success, requestId returned |
| 22 | Request oracle result before deadline | Revert: "deadline not reached" |
| 23 | Request oracle for non-active event | Revert: "event not active" |
| 24 | Request oracle twice for same event | Revert: "oracle adapter already recorded" |
| 25 | Oracle fulfills with valid outcome | Event settled, OrderBookManager notified |
| 26 | Oracle fulfills before settlementTime | Revert: "settlement time not reached" |
| 27 | Oracle fulfills with invalid outcome index | Revert: "invalid winning outcome index" |
| 28 | Unauthorized oracle tries to fulfill | Revert: "not authorized oracle adapter" |
| 29 | Oracle fulfills for non-active event | Revert: "event not active" |

### D. Oracle Adapter Routing
| # | Scenario | Expected Result |
|---|----------|----------------|
| 30 | Request oracle with default adapter | Uses defaultOracleAdapter |
| 31 | Request oracle with type-specific adapter | Uses eventTypeToOracleAdapter[eventType] |
| 32 | Set type-specific oracle for event type | Success, mapping updated |
| 33 | Remove type-specific oracle | Falls back to default |
| 34 | Request oracle with no adapter configured | Revert: "no oracle adapter configured" |
| 35 | Check getOracleAdapterForEvent before request | Returns correct adapter (default or type-specific) |
| 36 | Check getEventOracleAdapter after request | Returns recorded adapter |
| 37 | Check getEventOracleAdapter before request | Returns address(0) |

### E. Event Cancellation
| # | Scenario | Expected Result |
|---|----------|----------------|
| 38 | Cancel created event | Success, status = Cancelled |
| 39 | Cancel active event | Success, OrderBookManager deactivated |
| 40 | Try to cancel settled event | Revert: "cannot cancel settled event" |
| 41 | Try to cancel already cancelled event | Revert: "cannot cancel settled event" |
| 42 | Non-creator tries to cancel | Revert: "not event creator" |
| 43 | Owner cancels any event | Success |

### F. Event Creator Management
| # | Scenario | Expected Result |
|---|----------|----------------|
| 44 | Owner adds event creator | Success, isEventCreator[addr] = true |
| 45 | Owner removes event creator | Success, isEventCreator[addr] = false |
| 46 | Non-owner tries to add creator | Revert: "Ownable: caller is not the owner" |
| 47 | Add zero address as creator | Revert: "invalid address" |
| 48 | Remove non-existent creator | Revert: "not an event creator" |
| 49 | Owner is creator by default | isEventCreator[owner] = true |

### G. Oracle Adapter Management
| # | Scenario | Expected Result |
|---|----------|----------------|
| 50 | Set default oracle adapter | Success, authorized automatically |
| 51 | Set type-specific oracle adapter | Success, authorized automatically |
| 52 | Add authorized oracle adapter | Success, can fulfill results |
| 53 | Remove authorized oracle adapter | Success, cannot fulfill results |
| 54 | Set zero address as oracle | Revert: "invalid address" |

### H. View Functions
| # | Scenario | Expected Result |
|---|----------|----------------|
| 55 | getEvent() for valid eventId | Returns correct event data |
| 56 | getEvent() for invalid eventId | Revert: "event does not exist" |
| 57 | getEvents() returns all events | Array includes all created events |
| 58 | getEventStatus() returns correct status | Matches event.status |
| 59 | getOutcomes() returns all outcomes | Array matches event.outcomes |
| 60 | getOutcome() for valid index | Returns correct outcome |
| 61 | getOutcome() for invalid index | Revert: "outcome index out of bounds" |
| 62 | nextEventId() increments correctly | Returns events.length |

### I. Integration with OrderBookManager
| # | Scenario | Expected Result |
|---|----------|----------------|
| 63 | Activate event calls registerEvent() | OrderBookManager.registerEvent() called |
| 64 | Cancel active event calls deactivateEvent() | OrderBookManager.deactivateEvent() called |
| 65 | Settle event calls settleEvent() | OrderBookManager.settleEvent() called with winningOutcomeIndex |

### J. Edge Cases & Multiple Events
| # | Scenario | Expected Result |
|---|----------|----------------|
| 66 | Create 10 events, activate all | All succeed, IDs 1-10 |
| 67 | Settle multiple events with different outcomes | Each settles independently |
| 68 | Cancel some events, settle others | Independent state management |
| 69 | Event ID 0 is reserved dummy event | Cannot be used, status = Cancelled |
| 70 | Request oracle for multiple events | Each gets unique requestId |

---

## 4. Snapshot Strategy

### Base Snapshot (`baseSnapshot`)
Created in `setUp()` after full deployment:
- All Manager contracts deployed (EventManager, OrderBookManager, FundingManager, FeeVaultManager)
- MockOracle and MockOracleAdapter deployed and linked
- Owner is whitelisted event creator
- All contracts linked and initialized
- No events created yet

### Additional Snapshots (as needed)
- `withEventsSnapshot`: Base + 3 events created (Created status)
- `withActiveEventsSnapshot`: Base + 3 events in Active status
- `withOracleRequestSnapshot`: Base + 1 event with oracle requested

**Snapshot Usage Pattern:**
```solidity
function test_Something() public {
    vm.revertTo(baseSnapshot);  // Always start with clean state
    // Test logic here
}
```

---

## 5. Proposed Test File Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/deploy/local/V1/Deploy.s.sol";
import {IEventManager} from "../src/interfaces/core/IEventManager.sol";
import {IMockOracleAdapter} from "../src/interfaces/oracle/IMockOracleAdapter.sol";
import {MockOracle} from "../src/oracle/mock/MockOracle.sol";

contract EventManagerTest is Test {
    // Contracts
    Deploy public deployer;
    IEventManager public eventManager;
    IMockOracleAdapter public mockOracleAdapter;
    MockOracle public mockOracle;

    // Actors
    address public owner;
    address public creator1;
    address public creator2;
    address public user1;

    // Snapshots
    uint256 public baseSnapshot;
    uint256 public withEventsSnapshot;
    uint256 public withActiveEventsSnapshot;

    // Test data
    bytes32 public constant SPORTS_TYPE = keccak256("SPORTS");
    bytes32 public constant CRYPTO_TYPE = keccak256("CRYPTO");

    function setUp() public {
        // Deploy full system
        // Setup actors
        // Create baseSnapshot
    }

    // Helper functions
    function _createTestEvent() internal returns (uint256 eventId) { }
    function _activateEvent(uint256 eventId) internal { }
    function _setupMockOracleResult(uint256 eventId, uint8 outcome) internal { }

    // Test groups
    // A. Event Creation Tests (test_Create_*)
    // B. Status Transition Tests (test_Status_*)
    // C. Oracle Integration Tests (test_Oracle_*)
    // D. Oracle Routing Tests (test_OracleRouting_*)
    // E. Cancellation Tests (test_Cancel_*)
    // F. Creator Management Tests (test_Creator_*)
    // G. Oracle Adapter Management Tests (test_Adapter_*)
    // H. View Function Tests (test_View_*)
    // I. Integration Tests (test_Integration_*)
    // J. Edge Case Tests (test_Edge_*)
}
```

---

## 6. Clarifying Questions

### Q1: OrderBookManager Integration
When EventManager calls `OrderBookManager.registerEvent()` or `settleEvent()`, should we:
- Mock the OrderBookManager responses?
- Use the real OrderBookManager from deployment?
- Test only that the calls are made correctly?

**Recommendation**: Use real OrderBookManager from deployment to test full integration.

### Q2: Fee Handling
Does EventManager handle any fees directly, or are all fees managed by OrderBookManager/FundingManager?

**Current understanding**: EventManager doesn't handle fees, only manages event lifecycle.

### Q3: Oracle Result Timing
Can oracle fulfill result immediately after `requestOracleResult()`, or must we wait until `settlementTime`?

**Current understanding**: Must wait until `settlementTime` (line 306 in EventManager.sol checks this).

### Q4: Multiple Oracle Adapters
Can multiple oracle adapters be authorized and fulfill results for different events simultaneously?

**Current understanding**: Yes, each event records which adapter it used, and multiple adapters can be authorized.

### Q5: Event Type Routing Priority
If both `eventTypeToOracleAdapter[type]` and `defaultOracleAdapter` are set, which takes priority?

**Current understanding**: Type-specific takes priority, falls back to default (lines 212-218).

### Q6: Pause Functionality
When EventManager is paused, which functions should be blocked?

**Current understanding**: All state-changing functions (createEvent, updateEventStatus, etc.) should be blocked.

### Q7: Event ID 0
Event ID 0 is reserved as dummy. Should tests verify it cannot be used?

**Current understanding**: Yes, should test that operations on eventId=0 behave correctly (it's Cancelled status).

### Q8: Mock Oracle Setup
For each test, should we:
- Pre-configure mock results before requesting?
- Or set results dynamically during test?

**Recommendation**: Pre-configure in test setup for predictability.

### Q9: Test Priorities
Which scenarios are highest priority to test first?

**Recommendation**:
1. Happy path (create → activate → request oracle → settle)
2. Status transitions
3. Oracle integration
4. Edge cases

### Q10: Integration with FundingManager
EventManager doesn't directly interact with FundingManager, but OrderBookManager does. Should we test the full flow including user deposits and withdrawals?

**Recommendation**: Focus on EventManager operations only. Full integration can be separate test file.

---

## 7. Next Steps

1. **Confirm test approach** with user
2. **Answer clarifying questions**
3. **Implement test file** with snapshot-based structure
4. **Run tests** and verify coverage
5. **Iterate** based on findings

---

## Notes

- EventManager uses `nonReentrant` modifier on all state-changing functions
- EventManager uses `onlyEventCreator` and `onlyEventCreatorOrOwner` modifiers for access control
- EventManager emits events for all state changes (good for testing)
- Mock oracle provides immediate callbacks (good for testing)
- All Manager contracts use UUPS proxy pattern (test against proxies)
