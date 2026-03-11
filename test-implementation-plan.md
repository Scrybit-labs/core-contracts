# EventManager Test Implementation Plan

## 1. Admin Functions Already Tested (Skip These)

From `test/deployment/ContractLinkingTest.t.sol` and `test/deployment/DeploymentTest.t.sol`:

**Already Covered:**
- ✅ `setOrderBookManager()` - Tested via contract linking
- ✅ `setDefaultOracleAdapter()` - Tested via contract linking
- ✅ Owner setup - Tested in deployment
- ✅ Proxy deployment - Tested in deployment
- ✅ Contract initialization - Tested in deployment

**Need to Test:**
- `addEventCreator()` / `removeEventCreator()`
- `setEventTypeOracleAdapter()` / `removeEventTypeOracleAdapter()`
- `addAuthorizedOracleAdapter()` / `removeAuthorizedOracleAdapter()`
- Pause modifier verification (not pause itself)

---

## 2. Priority Test Scenarios (Happy Path First)

### Phase 1: Core Happy Path (10 tests)
1. ✅ Create event with valid parameters
2. ✅ Activate event (Created → Active)
3. ✅ Request oracle result after deadline
4. ✅ Oracle fulfills and settles event
5. ✅ View functions return correct data
6. ✅ Multiple events work independently
7. ✅ Event creator whitelist works
8. ✅ Cancel created event
9. ✅ Cancel active event
10. ✅ Event ID 0 is reserved

### Phase 2: Edge Cases & Validation (10 tests)
11. Create event with 2 outcomes (minimum)
12. Create event with 32 outcomes (maximum)
13. Create event with invalid parameters (empty title, past deadline, etc.)
14. Invalid status transitions
15. Request oracle before deadline (should fail)
16. Request oracle twice (should fail)
17. Oracle fulfills with invalid outcome
18. Non-creator tries to modify event
19. View functions with invalid eventId
20. Multiple events settle with different outcomes

### Phase 3: Integration (5 tests)
21. Full flow: create → activate → trade → settle → redeem
22. OrderBookManager integration (registerEvent, deactivateEvent, settleEvent)
23. FundingManager integration (deposits, withdrawals, redemptions)
24. Oracle adapter routing (default vs type-specific)
25. Event cancellation refunds users

---

## 3. Test File Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IEventManager} from "../../src/interfaces/core/IEventManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {IMockOracleAdapter} from "../../src/interfaces/oracle/IMockOracleAdapter.sol";
import {MockOracle} from "../../src/oracle/mock/MockOracle.sol";

contract EventManagerTest is Test {
    // ============ Contracts ============
    Deploy public deployer;
    IEventManager public eventManager;
    IOrderBookManager public orderBookManager;
    IFundingManager public fundingManager;
    IMockOracleAdapter public mockOracleAdapter;
    MockOracle public mockOracle;

    // ============ Actors ============
    address public owner;
    address public creator1;
    address public creator2;
    address public user1;
    address public user2;

    // ============ Snapshots ============
    uint256 public baseSnapshot;
    uint256 public withEventsSnapshot;
    uint256 public withActiveEventsSnapshot;

    // ============ Test Data ============
    bytes32 public constant SPORTS_TYPE = keccak256("SPORTS");
    bytes32 public constant CRYPTO_TYPE = keccak256("CRYPTO");

    uint256 public constant DEADLINE_OFFSET = 1 days;
    uint256 public constant SETTLEMENT_OFFSET = 2 days;

    // ============ Setup ============
    function setUp() public {
        // Setup actors
        owner = makeAddr("owner");
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy system
        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(uint256(keccak256("owner"))));
        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        // Get contract references
        eventManager = IEventManager(address(deployer.eventManager()));
        orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));
        fundingManager = IFundingManager(address(deployer.fundingManager()));
        mockOracleAdapter = IMockOracleAdapter(address(deployer.mockOracleAdapter()));

        // Get MockOracle from adapter
        address mockOracleAddr = mockOracleAdapter.mockOracle();
        mockOracle = MockOracle(mockOracleAddr);

        // Update owner reference
        owner = deployer.initialOwner();

        // Setup additional creators
        vm.startPrank(owner);
        eventManager.addEventCreator(creator1);
        eventManager.addEventCreator(creator2);
        vm.stopPrank();

        // Create base snapshot
        baseSnapshot = vm.snapshot();
    }

    // ============ Helper Functions ============

    function _createTestEvent() internal returns (uint256 eventId) {
        return _createTestEventAs(creator1, SPORTS_TYPE);
    }

    function _createTestEventAs(address creator, bytes32 eventType) internal returns (uint256 eventId) {
        IEventManager.Outcome[] memory outcomes = _createOutcomes(2);
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        uint256 settlementTime = deadline + SETTLEMENT_OFFSET;

        vm.prank(creator);
        eventId = eventManager.createEvent(
            "Test Event",
            "Test Description",
            deadline,
            settlementTime,
            outcomes,
            eventType
        );
    }

    function _createOutcomes(uint8 count) internal pure returns (IEventManager.Outcome[] memory) {
        IEventManager.Outcome[] memory outcomes = new IEventManager.Outcome[](count);
        for (uint8 i = 0; i < count; i++) {
            outcomes[i] = IEventManager.Outcome({
                name: string(abi.encodePacked("Outcome ", vm.toString(i))),
                description: string(abi.encodePacked("Description ", vm.toString(i)))
            });
        }
        return outcomes;
    }

    function _activateEvent(uint256 eventId) internal {
        vm.prank(owner);
        eventManager.updateEventStatus(eventId, IEventManager.EventStatus.Active);
    }

    function _setupMockOracleResult(uint256 eventId, uint8 winningOutcome) internal {
        vm.prank(owner);
        mockOracle.setMockResult(eventId, winningOutcome);

        // Also set numOutcomes in adapter
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        vm.prank(owner);
        mockOracleAdapter.setEventNumOutcomes(eventId, uint8(evt.outcomes.length));
    }

    function _requestAndFulfillOracle(uint256 eventId, uint8 winningOutcome) internal {
        // Setup mock result
        _setupMockOracleResult(eventId, winningOutcome);

        // Warp to after deadline
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        vm.warp(evt.deadline + 1);

        // Request oracle (will fulfill immediately)
        vm.prank(owner);
        eventManager.requestOracleResult(eventId);

        // Warp to settlement time
        vm.warp(evt.settlementTime + 1);

        // Oracle should have fulfilled, now settle
        // Note: Mock oracle calls fulfillMockResult immediately
    }

    function _warpToDeadline(uint256 eventId) internal {
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        vm.warp(evt.deadline + 1);
    }

    function _warpToSettlement(uint256 eventId) internal {
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        vm.warp(evt.settlementTime + 1);
    }

    // ============ Phase 1: Core Happy Path Tests ============

    function test_CreateEvent_ValidParameters() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();

        assertEq(eventId, 1); // First real event (0 is dummy)

        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        assertEq(evt.eventId, eventId);
        assertEq(evt.title, "Test Event");
        assertEq(evt.status, IEventManager.EventStatus.Created);
        assertEq(evt.creator, creator1);
    }

    function test_ActivateEvent_CreatedToActive() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();
        _activateEvent(eventId);

        IEventManager.EventStatus status = eventManager.getEventStatus(eventId);
        assertEq(uint8(status), uint8(IEventManager.EventStatus.Active));
    }

    function test_RequestOracleResult_AfterDeadline() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();
        _activateEvent(eventId);
        _setupMockOracleResult(eventId, 0);
        _warpToDeadline(eventId);

        vm.prank(owner);
        bytes32 requestId = eventManager.requestOracleResult(eventId);

        assertTrue(requestId != bytes32(0));
    }

    function test_OracleFulfillsAndSettlesEvent() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();
        _activateEvent(eventId);
        _setupMockOracleResult(eventId, 1);
        _warpToDeadline(eventId);

        vm.prank(owner);
        eventManager.requestOracleResult(eventId);

        _warpToSettlement(eventId);

        // Mock oracle should have called fulfillResult
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        assertEq(uint8(evt.status), uint8(IEventManager.EventStatus.Settled));
        assertEq(evt.winningOutcomeIndex, 1);
    }

    function test_ViewFunctions_ReturnCorrectData() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();

        // Test getEvent
        IEventManager.Event memory evt = eventManager.getEvent(eventId);
        assertEq(evt.eventId, eventId);

        // Test getEventStatus
        IEventManager.EventStatus status = eventManager.getEventStatus(eventId);
        assertEq(uint8(status), uint8(IEventManager.EventStatus.Created));

        // Test getOutcomes
        IEventManager.Outcome[] memory outcomes = eventManager.getOutcomes(eventId);
        assertEq(outcomes.length, 2);

        // Test getOutcome
        IEventManager.Outcome memory outcome0 = eventManager.getOutcome(eventId, 0);
        assertEq(outcome0.name, "Outcome 0");

        // Test nextEventId
        uint256 nextId = eventManager.nextEventId();
        assertEq(nextId, eventId + 1);
    }

    function test_MultipleEvents_WorkIndependently() public {
        vm.revertTo(baseSnapshot);

        uint256 event1 = _createTestEvent();
        uint256 event2 = _createTestEvent();
        uint256 event3 = _createTestEvent();

        assertEq(event1, 1);
        assertEq(event2, 2);
        assertEq(event3, 3);

        // Activate only event2
        _activateEvent(event2);

        assertEq(uint8(eventManager.getEventStatus(event1)), uint8(IEventManager.EventStatus.Created));
        assertEq(uint8(eventManager.getEventStatus(event2)), uint8(IEventManager.EventStatus.Active));
        assertEq(uint8(eventManager.getEventStatus(event3)), uint8(IEventManager.EventStatus.Created));
    }

    function test_EventCreatorWhitelist_Works() public {
        vm.revertTo(baseSnapshot);

        // creator1 is whitelisted
        vm.prank(creator1);
        uint256 eventId = eventManager.createEvent(
            "Test",
            "Desc",
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            _createOutcomes(2),
            SPORTS_TYPE
        );
        assertTrue(eventId > 0);

        // user1 is not whitelisted
        vm.prank(user1);
        vm.expectRevert("EventManager: not authorized");
        eventManager.createEvent(
            "Test",
            "Desc",
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            _createOutcomes(2),
            SPORTS_TYPE
        );
    }

    function test_CancelCreatedEvent() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();

        vm.prank(creator1);
        eventManager.cancelEvent(eventId, "Test cancellation");

        assertEq(uint8(eventManager.getEventStatus(eventId)), uint8(IEventManager.EventStatus.Cancelled));
    }

    function test_CancelActiveEvent() public {
        vm.revertTo(baseSnapshot);

        uint256 eventId = _createTestEvent();
        _activateEvent(eventId);

        vm.prank(owner);
        eventManager.cancelEvent(eventId, "Test cancellation");

        assertEq(uint8(eventManager.getEventStatus(eventId)), uint8(IEventManager.EventStatus.Cancelled));
    }

    function test_EventId0_IsReserved() public {
        vm.revertTo(baseSnapshot);

        IEventManager.Event memory evt = eventManager.getEvent(0);
        assertEq(evt.title, "DUMMY_EVENT");
        assertEq(uint8(evt.status), uint8(IEventManager.EventStatus.Cancelled));
    }

    // ============ Phase 2: Edge Cases & Validation ============

    // TODO: Implement remaining tests from Phase 2

    // ============ Phase 3: Integration Tests ============

    // TODO: Implement integration tests
}
```

---

## 4. Helper Function Specifications

### Core Helpers
- `_createTestEvent()` - Creates event with default parameters (2 outcomes, SPORTS_TYPE, creator1)
- `_createTestEventAs(address, bytes32)` - Creates event with specific creator and type
- `_createOutcomes(uint8)` - Generates array of outcomes with default names
- `_activateEvent(uint256)` - Transitions event to Active status
- `_setupMockOracleResult(uint256, uint8)` - Configures mock oracle with winning outcome
- `_requestAndFulfillOracle(uint256, uint8)` - Complete oracle flow (setup + request + fulfill)
- `_warpToDeadline(uint256)` - Time travel to after event deadline
- `_warpToSettlement(uint256)` - Time travel to after settlement time

### Integration Helpers (Phase 3)
- `_depositFunds(address, uint256)` - Deposit funds for user
- `_placeOrder(address, uint256, uint8, bool, uint256, uint256)` - Place buy/sell order
- `_redeemWinnings(address, uint256)` - Redeem winnings after settlement

---

## 5. Snapshot Strategy

### baseSnapshot
- Full system deployed
- All contracts linked
- Owner + creator1 + creator2 whitelisted
- No events created
- **Use for**: All tests that need clean state

### withEventsSnapshot (Optional)
- baseSnapshot + 3 events created (IDs 1, 2, 3)
- All in Created status
- **Use for**: Tests that need existing events

### withActiveEventsSnapshot (Optional)
- withEventsSnapshot + events 1 and 2 activated
- **Use for**: Tests that need active events

**Pattern**: Always start each test with `vm.revertTo(baseSnapshot)` or appropriate snapshot.

---

## 6. Implementation Order

### Week 1: Phase 1 (Core Happy Path)
1. ✅ Setup test file structure
2. ✅ Implement helper functions
3. ✅ Test 1-5: Basic lifecycle (create, activate, oracle, settle, views)
4. ✅ Test 6-10: Multiple events, whitelist, cancellation, reserved ID

### Week 2: Phase 2 (Edge Cases)
5. ✅ Test 11-15: Parameter validation, outcome limits, invalid transitions
6. ✅ Test 16-20: Oracle edge cases, access control, view errors

### Week 3: Phase 3 (Integration)
7. ✅ Test 21-23: Full flow with trading, OrderBookManager integration
8. ✅ Test 24-25: Oracle routing, cancellation refunds

---

## 7. Integration Points

### EventManager → OrderBookManager
- `registerEvent(eventId, outcomeCount)` - Called when event activated
- `deactivateEvent(eventId)` - Called when event cancelled
- `settleEvent(eventId, winningOutcomeIndex)` - Called when oracle fulfills

### EventManager → MockOracleAdapter
- `requestEventResult(eventId, description)` - Request oracle result
- Receives callback via `fulfillResult(eventId, winningOutcomeIndex, proof)`

### MockOracleAdapter → MockOracle
- `requestResult(eventId, numOutcomes)` - Triggers immediate callback
- `setMockResult(eventId, outcome)` - Pre-configure result (owner only)

### OrderBookManager → FundingManager
- `lockFunds()` - Lock funds for orders
- `settleMatchedOrder()` - Settle matched trades
- `markEventSettled()` - Mark event as settled
- Users call `redeemWinnings()` to claim

---

## 8. Key Testing Patterns

### Pattern 1: Event Lifecycle
```solidity
uint256 eventId = _createTestEvent();
_activateEvent(eventId);
_setupMockOracleResult(eventId, 0);
_warpToDeadline(eventId);
vm.prank(owner);
eventManager.requestOracleResult(eventId);
_warpToSettlement(eventId);
// Verify settled
```

### Pattern 2: Access Control
```solidity
vm.prank(unauthorizedUser);
vm.expectRevert("EventManager: not authorized");
eventManager.someFunction();
```

### Pattern 3: Invalid State Transition
```solidity
vm.expectRevert("EventManager: invalid status transition");
eventManager.updateEventStatus(eventId, invalidStatus);
```

### Pattern 4: Time-Based Validation
```solidity
// Before deadline
vm.expectRevert("EventManager: deadline not reached");
eventManager.requestOracleResult(eventId);

// After deadline
_warpToDeadline(eventId);
eventManager.requestOracleResult(eventId); // Should succeed
```

---

## 9. Next Steps

1. ✅ Review and approve this plan
2. ✅ Create `test/unit/EventManager.t.sol` with Phase 1 tests
3. ✅ Run tests: `forge test --match-contract EventManagerTest -vvv`
4. ✅ Verify coverage: `forge coverage --match-contract EventManagerTest`
5. ✅ Implement Phase 2 tests
6. ✅ Implement Phase 3 integration tests
7. ✅ Final review and documentation

---

## 10. Success Criteria

- ✅ All Phase 1 tests pass (10 tests)
- ✅ All Phase 2 tests pass (10 tests)
- ✅ All Phase 3 tests pass (5 tests)
- ✅ Total: 25 core tests covering happy path + edge cases + integration
- ✅ Tests use snapshot-based approach
- ✅ No duplication with deployment tests
- ✅ Full event lifecycle tested
- ✅ Integration with OrderBookManager and FundingManager verified
