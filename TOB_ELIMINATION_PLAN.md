# Plan: Eliminate ToB Structure - Direct to Consumer Architecture

> **NOTE:** This is a comprehensive planning document only. No implementation or code changes have been made yet. This plan outlines the architecture transformation and provides a detailed roadmap for future implementation.

## Executive Summary

Transform the platform from a B2B multi-tenant system to a B2C direct-to-consumer model. Remove vendor isolation infrastructure and deploy single instances of Pod contracts that serve all end users directly.

**Status:** Planning Complete ✅ - Ready for implementation approval

## Current Architecture Analysis

### ToB Multi-Tenant System
```
PodFactory (Vendor Registry)
├── EventManager (routes vendorId → EventPod)
├── OrderBookManager (routes vendorId → OrderBookPod)
├── FundingManager (routes vendorId → FundingPod)
├── FeeVaultManager (routes vendorId → FeeVaultPod)
└── PodDeployer (CREATE2 cloning per vendor)

For each vendor:
├── EventPod (isolated events)
├── OrderBookPod (isolated order book)
├── FundingPod (isolated funds)
└── FeeVaultPod (isolated fees)
```

### Key Findings from Codebase Analysis

**VendorId Usage:**
- Used as primary key in all Manager mappings (vendorId → Pod address)
- Used in CREATE2 salt generation: `keccak256(abi.encodePacked(vendorId, podType))`
- Stored in EventPod only (`vendorId` and `vendorAddress` fields)
- NOT used in OrderBookPod, FundingPod, or FeeVaultPod storage structures
- Isolation achieved through separate pod instances, not internal vendor checks

**Manager Layer Purpose:**
- Router/registry: Maps vendorId to correct Pod address
- Query interface: Provides read-only views for external consumers
- Deployment coordination: Calls PodDeployer with vendor context
- **For single instance: Managers become unnecessary overhead**

**Pod Independence:**
- Pods already store data globally (no vendorId in most mappings)
- EventPod has `nextEventId` counter (per-pod, already unique)
- OrderBookPod has `nextOrderId` counter (per-pod, already unique)
- Inter-pod references are address-based, not vendorId-based
- Access control uses `onlyOwner`, `onlyEventPod`, etc. - not vendor-based

## Target Architecture

### Direct-to-Consumer System
```
Platform Admin (Owner)
├── EventPod (single instance, all events)
│   └── Event Creators (whitelisted addresses can create events)
├── OrderBookPod (single instance, all orders)
├── FundingPod (single instance, all funds)
├── FeeVaultPod (single instance, fees → owner directly)
└── OracleAdapter (event settlement)
```

**Key Simplifications:**
- Remove: PodFactory, PodDeployer, all 4 Managers, AdminFeeVault (5 major contract deletions)
- Keep: 4 Pod contracts (EventPod, OrderBookPod, FundingPod, FeeVaultPod), OracleManager, OracleAdapter
- Deploy: Single instance of each Pod (no cloning, direct deployment)
- Access: Whitelisted creators make events, users trade directly, fees go directly to owner

## Critical Design Decisions

### Decision 1: Event Creation Permissions ✅ DECIDED

**Selected: Whitelist-Based Event Creation**

Implementation:
- Add `mapping(address => bool) public isEventCreator` to EventPodStorage
- Add `onlyEventCreator` modifier to EventPod
- Platform owner can add/remove approved creators via `addEventCreator()` / `removeEventCreator()`
- More flexible than admin-only while maintaining quality control
- Owner is automatically an event creator

```solidity
modifier onlyEventCreator() {
    require(isEventCreator[msg.sender] || msg.sender == owner(), "EventPod: not authorized");
    _;
}

function addEventCreator(address creator) external onlyOwner {
    isEventCreator[creator] = true;
    emit EventCreatorAdded(creator);
}

function removeEventCreator(address creator) external onlyOwner {
    isEventCreator[creator] = false;
    emit EventCreatorRemoved(creator);
}
```

### Decision 2: Contract Structure

**Recommended Approach: Keep 4 Separate Pods**

Benefits:
- ✅ Preserves modularity and separation of concerns
- ✅ Easier testing (can test each Pod independently)
- ✅ Clear boundaries between event, trading, funding, fee logic
- ✅ Minimal code changes (just remove vendor infrastructure)
- ✅ Can still upgrade individual Pods independently

Changes Required:
- Remove vendor-related fields from EventPod
- Deploy Pods directly (no factory/cloning)
- Wire Pods together at initialization
- Update deployment script

### Decision 3: AdminFeeVault Configuration ✅ DECIDED

**Selected: Simplify to Single Beneficiary**

Implementation:
- Remove AdminFeeVault contract entirely
- Remove auto-transfer logic from FeeVaultPod (no more `_autoTransferIfNeeded()`)
- Admin withdraws fees directly from FeeVaultPod to platform wallet
- Simplify `initialize()` to not require AdminFeeVault address
- Keep `feeRecipient` for tracking purposes or remove if not needed

```solidity
// FeeVaultPod - simplified withdrawal
function withdrawFee(address token, uint256 amount) external onlyOwner nonReentrant {
    require(amount <= feeBalances[token], "Insufficient fee balance");
    feeBalances[token] -= amount;
    totalFeesWithdrawn[token] += amount;

    if (token == ETHAddress) {
        payable(owner()).transfer(amount);
    } else {
        IERC20(token).transfer(owner(), amount);
    }

    emit FeeWithdrawn(token, owner(), amount);
}
```

This simplifies the fee flow to: **User trades → FeeVaultPod → Platform owner**

### Decision 4: Upgradeability

**Current: All Managers and Factory use UUPS proxies**

**Recommended: Keep UUPS Proxies for Pods**
- Deploy Pods behind ERC1967Proxy with UUPS
- Enables future upgrades without migration
- Small gas overhead but worth it for production safety

## Implementation Plan

### Phase 1: Remove Vendor Infrastructure

#### Task 1.1: Delete Factory Contracts
**Files to DELETE:**
- `/workspace/src/event/factory/PodFactory.sol`
- `/workspace/src/event/factory/PodFactoryStorage.sol`
- `/workspace/src/event/factory/PodDeployer.sol`
- `/workspace/src/event/factory/PodDeployerStorage.sol`

**Impact:** Removes ~1000+ lines of multi-tenant coordination code

#### Task 1.2: Delete Manager Contracts
**Files to DELETE:**
- `/workspace/src/event/core/EventManager.sol`
- `/workspace/src/event/core/EventManagerStorage.sol`
- `/workspace/src/event/core/OrderBookManager.sol`
- `/workspace/src/event/core/OrderBookManagerStorage.sol`
- `/workspace/src/event/core/FundingManager.sol`
- `/workspace/src/event/core/FundingManagerStorage.sol`
- `/workspace/src/event/core/FeeVaultManager.sol`
- `/workspace/src/event/core/FeeVaultManagerStorage.sol`

**Impact:** Removes routing/registry layer (~800+ lines)

#### Task 1.3: Clean Up Interfaces
**Files to UPDATE:**
- `/workspace/src/interfaces/event/IEventManager.sol` - DELETE or simplify
- `/workspace/src/interfaces/event/IOrderBookManager.sol` - DELETE or simplify
- `/workspace/src/interfaces/event/IFundingManager.sol` - DELETE or simplify
- `/workspace/src/interfaces/event/IFeeVaultManager.sol` - DELETE or simplify
- `/workspace/src/interfaces/event/IPodFactory.sol` - DELETE
- `/workspace/src/interfaces/event/IPodDeployer.sol` - DELETE

### Phase 2: Simplify Pod Contracts

#### Task 2.1: Simplify EventPod
**File:** `/workspace/src/event/pod/EventPod.sol`
**File:** `/workspace/src/event/pod/EventPodStorage.sol`

**Changes:**
1. Remove `vendorId` field (Line 39 in EventPodStorage.sol)
2. Remove `vendorAddress` field
3. Add `mapping(address => bool) public isEventCreator` storage
4. Replace `onlyVendor` modifier with `onlyEventCreator` modifier
5. Add `addEventCreator()` and `removeEventCreator()` functions
6. Update `initialize()` signature:
   ```solidity
   // OLD:
   function initialize(
       address initialOwner,
       uint256 _vendorId,
       address _eventManager,
       address _orderBookManager
   )

   // NEW:
   function initialize(
       address initialOwner,
       address _orderBookPod,
       address _oracleAdapter
   )
   ```
5. Remove `eventManager` and `orderBookManager` references (use direct pod addresses)
6. Update `createEvent()` to use `onlyEventCreator` modifier
7. Update `updateEventStatus()` to use `onlyEventCreator` modifier
8. Change `orderBookManager.getVendorOrderBookPod(vendorId)` to direct `orderBookPod` reference

**Lines Affected:** ~30 lines changed (includes new whitelist functions)

#### Task 2.2: Simplify OrderBookPod
**File:** `/workspace/src/event/pod/OrderBookPod.sol`

**Changes:**
1. Remove `orderBookManager` field
2. Update `initialize()` signature:
   ```solidity
   // OLD:
   function initialize(
       address initialOwner,
       address _eventPod,
       address _fundingPod,
       address _feeVaultPod,
       address _orderBookManager
   )

   // NEW:
   function initialize(
       address initialOwner,
       address _eventPod,
       address _fundingPod,
       address _feeVaultPod
   )
   ```
3. Remove setter for `orderBookManager`

**Lines Affected:** ~10 lines changed

#### Task 2.3: Simplify FundingPod
**File:** `/workspace/src/event/pod/FundingPod.sol`

**Changes:**
1. Remove `fundingManager` field
2. Remove `onlyFundingManager` modifier (if not used elsewhere)
3. Update `initialize()` signature:
   ```solidity
   // OLD:
   function initialize(
       address initialOwner,
       address _fundingManager,
       address _orderBookPod,
       address _eventPod
   )

   // NEW:
   function initialize(
       address initialOwner,
       address _orderBookPod,
       address _eventPod
   )
   ```
4. Remove `withdraw()` function if only manager-controlled (keep `withdrawDirect()`)

**Lines Affected:** ~15 lines changed

#### Task 2.4: Simplify FeeVaultPod
**File:** `/workspace/src/event/pod/FeeVaultPod.sol`

**Changes:**
1. Remove `feeVaultManager` field
2. Remove `onlyFeeVaultManager` modifier
3. Remove `adminFeeVault` field (not needed anymore)
4. Remove `feeRecipient` field (not needed anymore)
5. Remove auto-transfer logic entirely (`_autoTransferIfNeeded()` function)
6. Simplify `withdrawFee()` to transfer directly to owner
7. Update `initialize()` signature:
   ```solidity
   // OLD:
   function initialize(
       address initialOwner,
       address _feeVaultManager,
       address _orderBookPod,
       address _feeRecipient
   )

   // NEW:
   function initialize(
       address initialOwner,
       address _orderBookPod
   )
   ```

**Lines Affected:** ~40 lines changed (includes removing auto-transfer logic)

### Phase 3: Create New Deployment Script

#### Task 3.1: Create SimpleDeploy.s.sol
**New File:** `/workspace/script/SimpleDeploy.s.sol`

**Structure:**
```solidity
contract SimpleDeploy is Script {
    function run() external {
        vm.startBroadcast();

        // Phase 1: Deploy Pod Implementations
        EventPod eventPodImpl = new EventPod();
        OrderBookPod orderBookPodImpl = new OrderBookPod();
        FundingPod fundingPodImpl = new FundingPod();
        FeeVaultPod feeVaultPodImpl = new FeeVaultPod();

        // Phase 2: Deploy Oracle System (AdminFeeVault removed)

        OracleManager oracleManagerImpl = new OracleManager();
        initData = abi.encodeCall(OracleManager.initialize, (msg.sender));
        OracleManager oracleManager = OracleManager(
            address(new ERC1967Proxy(address(oracleManagerImpl), initData))
        );

        OracleAdapter oracleAdapterImpl = new OracleAdapter();
        // Initialize with placeholder, update after pod deployment

        // Phase 4: Deploy Pods Behind Proxies
        // Pre-calculate addresses for circular dependencies
        address eventPodProxy;
        address orderBookPodProxy;
        address fundingPodProxy;
        address feeVaultPodProxy;

        // Calculate CREATE2 addresses or deploy and wire manually

        // Initialize EventPod
        initData = abi.encodeCall(
            EventPod.initialize,
            (
                msg.sender,           // owner
                orderBookPodProxy,    // will be calculated
                address(oracleAdapter)
            )
        );
        eventPodProxy = address(
            new ERC1967Proxy(address(eventPodImpl), initData)
        );

        // Initialize OrderBookPod
        initData = abi.encodeCall(
            OrderBookPod.initialize,
            (
                msg.sender,
                eventPodProxy,
                fundingPodProxy,
                feeVaultPodProxy
            )
        );
        orderBookPodProxy = address(
            new ERC1967Proxy(address(orderBookPodImpl), initData)
        );

        // Initialize FundingPod
        initData = abi.encodeCall(
            FundingPod.initialize,
            (
                msg.sender,
                orderBookPodProxy,
                eventPodProxy
            )
        );
        fundingPodProxy = address(
            new ERC1967Proxy(address(fundingPodImpl), initData)
        );

        // Initialize FeeVaultPod
        initData = abi.encodeCall(
            FeeVaultPod.initialize,
            (
                msg.sender,
                orderBookPodProxy
            )
        );
        feeVaultPodProxy = address(
            new ERC1967Proxy(address(feeVaultPodImpl), initData)
        );

        // Phase 5: Configure Oracle
        OracleAdapter(oracleAdapter).setEventPod(eventPodProxy);
        oracleManager.addOracleAdapter(address(oracleAdapter), "DefaultAdapter");

        vm.stopBroadcast();

        // Print addresses
        console.log("EventPod:", eventPodProxy);
        console.log("OrderBookPod:", orderBookPodProxy);
        console.log("FundingPod:", fundingPodProxy);
        console.log("FeeVaultPod:", feeVaultPodProxy);
        console.log("OracleManager:", address(oracleManager));
        console.log("OracleAdapter:", address(oracleAdapter));
    }
}
```

**Challenge:** Circular dependencies between pods during initialization
**Solution:**
- Option A: Use CREATE2 to pre-calculate addresses (like current system but simpler)
- Option B: Deploy all proxies first with dummy init, then call setup functions
- Option C: Two-phase initialization (deploy, then wire)

#### Task 3.2: Update Makefile
**File:** `/workspace/Makefile`

**Changes:**
```makefile
# Replace deploy-prediction-* targets
deploy-local:
	@forge script script/SimpleDeploy.s.sol:SimpleDeploy $(NETWORK_ARGS)

deploy-base-sepolia:
	@forge script script/SimpleDeploy.s.sol:SimpleDeploy $(NETWORK_BASE_SEPOLIA)

# ... update all deployment targets
```

### Phase 4: Update Tests

#### Task 4.1: Remove Factory/Manager Tests
**Files to DELETE:**
- Tests for PodFactory
- Tests for PodDeployer
- Tests for all 4 Managers
- Vendor registration tests

#### Task 4.2: Update Pod Tests
**Files to UPDATE:**
- All `*.t.sol` test files in `/workspace/test/`

**Changes:**
1. Remove vendor registration setup from test fixtures
2. Deploy single instances directly in `setUp()`
3. Remove vendorId parameters from test calls
4. Update initialization calls to match new signatures
5. Remove multi-vendor test scenarios

**Example setUp() Pattern:**
```solidity
function setUp() public {
    // Deploy implementations
    EventPod eventPodImpl = new EventPod();
    OrderBookPod orderBookPodImpl = new OrderBookPod();
    FundingPod fundingPodImpl = new FundingPod();
    FeeVaultPod feeVaultPodImpl = new FeeVaultPod();

    // Deploy proxies (solve circular deps with CREATE2 or two-phase)
    eventPod = EventPod(address(new ERC1967Proxy(...)));
    orderBookPod = OrderBookPod(address(new ERC1967Proxy(...)));
    fundingPod = FundingPod(payable(address(new ERC1967Proxy(...))));
    feeVaultPod = FeeVaultPod(address(new ERC1967Proxy(...)));

    // Wire together
    // ... initialization calls
}
```

#### Task 4.3: Create New Integration Tests
**New File:** `/workspace/test/integration/SimpleFlow.t.sol`

**Test Scenarios:**
1. Admin adds event creators to whitelist
2. Approved creator creates event
3. Users deposit funds
3. Users mint complete sets
4. Users place buy/sell orders
5. Orders match automatically
7. Oracle submits result
8. Event settles
9. Winners withdraw funds
10. Admin withdraws fees directly from FeeVaultPod

### Phase 5: Documentation Updates

#### Task 5.1: Update CLAUDE.md
**File:** `/workspace/CLAUDE.md`

**Changes:**
- Remove ToB model explanation
- Update architecture diagram (remove factory/managers)
- Update deployment commands
- Simplify "Core Architecture" section
- Update "Deployment Flow" to 4 phases instead of 6
- Remove vendor registration examples
- Update environment variables (remove vendor-related configs)

#### Task 5.2: Update README.md
**File:** `/workspace/README.md`

**Changes:**
- Section 2 "系统架构": Remove vendor isolation, simplify diagram
- Section 3.2 "Manager 合约": Remove entire section (no managers)
- Section 3.3 "工厂合约": Remove entire section (no factory)
- Section 4 "业务逻辑流程": Update to show direct user interaction
- Section 7 "开发与测试": Update deployment commands
- Section 8 "部署": Update to use SimpleDeploy.s.sol
- Section 9 "使用指南": Remove 9.1 (platform admin) and 9.2 (vendor), expand 9.3 (end users)

#### Task 5.3: Update Other Documentation
- `L2_DEPLOYMENT_GUIDE.md`: Update deployment commands
- `VIRTUAL_LONG_TOKEN_GUIDE.md`: Update if needed (likely unchanged)
- `MVP设计方案.md`: Mark as outdated or update for new model

### Phase 6: Address Resolution Strategy

**Problem:** Pods reference each other during initialization (circular dependency)

**Current Solution in ToB:** CREATE2 pre-calculation using `keccak256(abi.encodePacked(vendorId, podType))`

**New Solution Options:**

**Option A (Recommended): Simplified CREATE2**
```solidity
// Use fixed salts instead of vendorId-based
bytes32 salt = keccak256(abi.encodePacked("EventPod", "v1"));
address predictedAddress = Clones.predictDeterministicAddress(impl, salt, deployer);
```

**Option B: Two-Phase Initialization**
1. Deploy all 4 proxies with minimal init (no cross-references)
2. Call `setPodReferences()` on each pod after all deployed

**Option C: Manual Wiring (Simplest)**
1. Deploy EventPod (no dependencies)
2. Deploy FeeVaultPod (depends on nothing or AdminFeeVault)
3. Deploy FundingPod (needs EventPod address)
4. Deploy OrderBookPod (needs all 3 addresses)
5. Wire EventPod.setOrderBookPod(orderBookPod)

**Recommended: Option C for simplicity (no CREATE2 needed)**

## File Change Summary

### Files to DELETE (14 files)
```
src/event/factory/PodFactory.sol
src/event/factory/PodFactoryStorage.sol
src/event/factory/PodDeployer.sol
src/event/factory/PodDeployerStorage.sol
src/event/core/EventManager.sol
src/event/core/EventManagerStorage.sol
src/event/core/OrderBookManager.sol
src/event/core/OrderBookManagerStorage.sol
src/event/core/FundingManager.sol
src/event/core/FundingManagerStorage.sol
src/event/core/FeeVaultManager.sol
src/event/core/FeeVaultManagerStorage.sol
src/admin/AdminFeeVault.sol
src/interfaces/event/IPodFactory.sol (if exists)
```

### Files to MODIFY (12+ files)
```
src/event/pod/EventPod.sol - Remove vendorId, add whitelist, simplify init
src/event/pod/EventPodStorage.sol - Remove vendor fields, add isEventCreator
src/event/pod/OrderBookPod.sol - Remove manager reference
src/event/pod/FundingPod.sol - Remove manager reference
src/event/pod/FeeVaultPod.sol - Remove manager, AdminFeeVault, auto-transfer logic
src/event/pod/FeeVaultPodStorage.sol - Remove adminFeeVault field
script/SimpleDeploy.s.sol - NEW FILE (replaces Deploy.s.sol)
script/config/DeploymentConfig.sol - Simplify (remove AdminFeeVault config)
Makefile - Update deployment targets
CLAUDE.md - Remove ToB model docs, add whitelist docs
README.md - Major rewrite for B2C model
test/**/*.t.sol - Update all test files
```

### Net Code Reduction
- **Deleted:** ~2200+ lines (factory, managers, AdminFeeVault, storage)
- **Modified:** ~130 lines (pod simplifications + whitelist logic)
- **New:** ~200 lines (simplified deployment)
- **Net Reduction:** ~1800 lines (~32% of contract code)

## Risk Assessment

### High Priority Risks

1. **Circular Dependency Resolution**
   - Risk: Pods need each other's addresses during init
   - Mitigation: Use two-phase init or CREATE2 pre-calculation
   - Test: Verify all pod references are correct post-deployment

2. **Access Control Changes**
   - Risk: Removing vendor isolation might expose unintended functions
   - Mitigation: Audit all public/external functions for new access patterns
   - Test: Ensure only authorized addresses can perform critical operations

3. **Storage Layout Changes**
   - Risk: Removing vendorId from EventPodStorage affects storage slots
   - Mitigation: NOT upgrading existing contracts - fresh deployment only
   - Test: This is not a concern for fresh deployments

### Medium Priority Risks

1. **Event ID Uniqueness**
   - Risk: Single EventPod must ensure globally unique event IDs
   - Current: `nextEventId` is already a per-pod counter (works as-is)
   - Test: Create many events, verify no ID collisions

2. **Test Coverage Gaps**
   - Risk: Removing multi-vendor tests might miss edge cases
   - Mitigation: Create comprehensive single-instance integration tests
   - Test: Achieve >80% coverage on pod contracts

3. **Fee Distribution**
   - Risk: Simplifying AdminFeeVault might break fee flow
   - Mitigation: Test fee collection and withdrawal thoroughly
   - Test: Verify fees accumulate and can be withdrawn correctly

## Verification Plan

### Unit Tests
```bash
forge test --match-contract EventPodTest -vvv
forge test --match-contract OrderBookPodTest -vvv
forge test --match-contract FundingPodTest -vvv
forge test --match-contract FeeVaultPodTest -vvv
```

### Integration Tests
```bash
forge test --match-contract SimpleFlowTest -vvv
```

### Deployment Verification (Local)
```bash
# 1. Start local Anvil
make anvil

# 2. Deploy to local
make deploy-local

# 3. Verify addresses printed
# Expected output:
# EventPod: 0x...
# OrderBookPod: 0x...
# FundingPod: 0x...
# FeeVaultPod: 0x...

# 4. Test complete flow manually or via script
forge script script/TestFlow.s.sol --rpc-url http://localhost:8545
```

### L2 Testnet Verification
```bash
# Deploy to Base Sepolia
make deploy-base-sepolia

# Verify contracts on explorer
# Test with real users/funds
```

## Implementation Decisions Summary ✅

All critical decisions have been made:

1. **Event Creation:** Whitelist-based (approved creators with `isEventCreator` mapping)
2. **Fee Distribution:** Simplified to single beneficiary (remove AdminFeeVault)
3. **Event Approval:** No approval process - events are active immediately after creation
4. **Oracle Service:** Keep existing OracleManager/OracleAdapter design (no change needed)

## Success Criteria

✅ **Contract Changes Complete**
- PodFactory, PodDeployer, all Managers removed
- EventPod simplified (no vendorId)
- All 3 other Pods updated to remove manager references

✅ **Deployment Works**
- SimpleDeploy.s.sol successfully deploys all contracts
- All pod references wire correctly
- No initialization errors

✅ **Tests Pass**
- All unit tests updated and passing
- New integration tests cover complete user flow
- Test coverage >80% on core pod contracts

✅ **Documentation Updated**
- CLAUDE.md reflects new architecture
- README.md updated for B2C model
- Deployment guides simplified

✅ **Functional Verification**
- Admin can create events
- Users can deposit funds
- Users can place orders
- Orders match correctly
- Events settle via oracle
- Winners can withdraw funds

## Estimated Effort

- **Contract Refactoring**: 2-3 days
  - Delete factory/managers: 1 day
  - Update Pods: 1 day
  - New deployment script: 1 day

- **Testing**: 2-3 days
  - Update unit tests: 1 day
  - Write integration tests: 1 day
  - Fix issues: 1 day

- **Documentation**: 1 day
  - Update CLAUDE.md, README.md
  - Update deployment guides

**Total: 5-7 days for complete implementation**

## Next Steps

1. **User Decision:** Answer open questions (event permissions, fee model, etc.)
2. **Phase 1:** Delete factory and manager contracts
3. **Phase 2:** Simplify Pod contracts
4. **Phase 3:** Create new deployment script
5. **Phase 4:** Update all tests
6. **Phase 5:** Update documentation
7. **Deploy & Test:** Deploy to local, testnet, verify functionality
