# Manager and Pod Refactoring - Implementation Plan

## Overview
Transform from shared pool architecture to multi-tenant vendor-based architecture where each vendor gets dedicated pod sets (EventPod, OrderBookPod, FeeVaultPod, FundingPod).

---

## Phase 1: Factory System

### 1.1 Create Factory Interfaces
- [ ] Create `IPodFactory.sol` interface
  - Define vendor registration functions
  - Define vendor pod set query functions
  - Define VendorPodSet struct
  - Define events and errors

- [ ] Create `IPodDeployer.sol` interface
  - Define pod deployment functions
  - Define pod implementation management
  - Define events and errors

### 1.2 Create PodFactory Contract
- [ ] Create `PodFactoryStorage.sol`
  - Add vendor registry mappings
  - Add vendor pod set struct
  - Add nextVendorId counter
  - Add podFactory reference
  - Add storage gap for upgrades

- [ ] Create `PodFactory.sol`
  - Implement vendor registration
  - Implement vendor pod set queries
  - Implement vendor activation/deactivation
  - Add access control (onlyOwner)
  - Add events

### 1.3 Create PodDeployer Contract
- [ ] Create `PodDeployerStorage.sol`
  - Add pod implementation addresses
  - Add deployment tracking
  - Add storage gap

- [ ] Create `PodDeployer.sol`
  - Implement CREATE2 deployment with minimal proxy pattern
  - Implement pod set deployment function
  - Implement pod implementation management
  - Add deterministic address calculation
  - Add initialization logic for deployed pods

---

## Phase 2: Refactor EventManager

### 2.1 Update EventManagerStorage
- [ ] Add `podFactory` address variable
- [ ] Add `vendorEvents` mapping (vendorId => eventId[])
- [ ] Mark deprecated variables with comments
  - `whitelistedPods` array
  - `podIndex` mapping
  - `currentPodIndex`
- [ ] Verify storage gap adjustment

### 2.2 Update EventManager Logic
- [ ] Add `setPodFactory(address)` function
- [ ] Modify `createEvent()` to accept `vendorId` as first parameter
- [ ] Replace `_selectPodForEvent()` with factory lookup
- [ ] Add vendor event tracking in `vendorEvents` mapping
- [ ] Update `_registerEventToOrderBook()` to work with vendor pods
- [ ] Add `getVendorEvents(uint256 vendorId)` view function
- [ ] Mark deprecated functions with comments (keep for backwards compatibility)
  - `addPodToWhitelist`
  - `removePodFromWhitelist`
  - `getWhitelistedPodCount`
  - `getWhitelistedPodAt`

---

## Phase 3: Refactor FundingManager

### 3.1 Update FundingManagerStorage
- [ ] Add `podFactory` address variable
- [ ] Mark deprecated variables with comments
  - `whitelistedPods` array
  - `podIndex` mapping
- [ ] Verify storage gap adjustment

### 3.2 Update FundingManager Logic
- [ ] Add `setPodFactory(address)` function
- [ ] Add `depositEthIntoVendorPod(uint256 vendorId)` function
- [ ] Add `depositErc20IntoVendorPod(uint256 vendorId, IERC20 token, uint256 amount)` function
- [ ] Add `withdrawFromVendorPod(uint256 vendorId, address tokenAddress, uint256 amount)` function
- [ ] Add vendor validation (check vendor exists and is active)
- [ ] Keep existing deposit functions for backwards compatibility

---

## Phase 4: Update Other Managers

### 4.1 Update OrderBookManager
- [ ] Add `podFactory` address variable to OrderBookManagerStorage
- [ ] Add `setPodFactory(address)` function
- [ ] Verify storage gap adjustment
- [ ] (Minimal changes - already uses event-to-pod mapping)

### 4.2 Update FeeVaultManager
- [ ] Add `podFactory` address variable to FeeVaultManagerStorage
- [ ] Add `setPodFactory(address)` function
- [ ] Verify storage gap adjustment
- [ ] (Minimal changes - already uses event-to-pod mapping)

---

## Phase 5: Testing Infrastructure

### 5.1 Unit Tests
- [ ] Test PodFactory vendor registration
- [ ] Test PodFactory vendor queries
- [ ] Test PodFactory vendor activation/deactivation
- [ ] Test PodDeployer pod set deployment
- [ ] Test PodDeployer CREATE2 deterministic addresses
- [ ] Test EventManager with vendorId parameter
- [ ] Test FundingManager vendor-based deposits
- [ ] Test vendor isolation (separate pods, separate funds)

### 5.2 Integration Tests
- [ ] Test full vendor lifecycle (register → deploy pods → create event → deposit → order)
- [ ] Test multi-vendor isolation
- [ ] Test shared oracle across vendors
- [ ] Test event routing to correct vendor pods
- [ ] Test fund routing to correct vendor pods

### 5.3 Gas Analysis
- [ ] Measure pod deployment gas (minimal proxy vs direct)
- [ ] Measure event creation gas (old vs new)
- [ ] Document gas impact

---

## Phase 6: Deployment Scripts

### 6.1 Deployment Preparation
- [ ] Create deployment script for PodFactory
- [ ] Create deployment script for PodDeployer
- [ ] Create deployment script for pod implementations
- [ ] Create upgrade script for EventManager
- [ ] Create upgrade script for FundingManager
- [ ] Create upgrade script for OrderBookManager
- [ ] Create upgrade script for FeeVaultManager

### 6.2 Post-Deployment Configuration
- [ ] Set PodDeployer in PodFactory
- [ ] Set pod implementations in PodDeployer
- [ ] Set PodFactory reference in all managers
- [ ] Add EventManager as authorized caller in OrderBookManager
- [ ] Register first test vendor
- [ ] Create test event for vendor
- [ ] Test end-to-end flow

---

## Phase 7: Documentation

### 7.1 Code Documentation
- [ ] Add NatSpec comments to all new contracts
- [ ] Add inline comments for complex logic
- [ ] Document architecture changes
- [ ] Document migration path

### 7.2 User Documentation
- [ ] Document vendor registration process
- [ ] Document event creation with vendorId
- [ ] Document deposit/withdrawal with vendorId
- [ ] Document backwards compatibility notes

---

## Review Section

_This section will be filled out after implementation is complete._

### Summary of Changes
-

### Files Created
-

### Files Modified
-

### Testing Results
-

### Gas Impact
-

### Known Issues / TODOs
-

### Migration Notes
-
