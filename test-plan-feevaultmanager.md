# FeeVaultManager Test Plan

## Baseline

> "Focus on usability and completeness of interaction cycle, ignore security, ignore gas usage"

- Test the full happy-path interaction cycle thoroughly
- Cover admin/management flows completely
- Verify state tracking is accurate across the entire lifecycle
- Do **not** write security-focused tests (access control attacks, reentrancy)
- Do **not** write gas benchmarks

---

## Key Files

| Purpose | Path |
|---------|------|
| Contract under test | `/workspace/src/core/FeeVaultManager.sol` |
| Interface | `/workspace/src/interfaces/core/IFeeVaultManager.sol` |
| Deploy script | `/workspace/script/deploy/local/V1/Deploy.s.sol` |
| FundingManager (dependency) | `/workspace/src/core/FundingManager.sol` |
| Reference test pattern | `/workspace/test/unit/EventManager.t.sol` |
| **Test file to create** | `/workspace/test/unit/FeeVaultManager.t.sol` |

---

## Contract Behaviour Summary

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `protocolUsdFeeBalance` | `uint256` | Accumulated protocol fees in USD (1e18) |
| `totalFeesCollected[token]` | `mapping(address => uint256)` | USD collected per token label |
| `totalFeesWithdrawn[token]` | `mapping(address => uint256)` | USD withdrawn per token label |
| `eventFees[eventId][token]` | nested mapping | USD fees per event per token label |
| `userPaidFees[user][token]` | nested mapping | USD fees paid per user per token label |
| `FEE_PRECISION` | constant `10000` | Basis-point denominator |
| `MAX_FEE_RATE` | constant `1000` | Maximum allowed fee rate (10%) |

### Functions

| Function | Modifier(s) | Description |
|----------|-------------|-------------|
| `initialize(owner)` | `initializer` | Sets default rates: placement=10, execution=20 |
| `collectFee(token, payer, amount, eventId, feeType)` | `onlyOrderBookManager whenNotPaused nonReentrant` | Calls `FundingManager.collectProtocolFee(payer, amount)`, updates all counters |
| `withdrawFee(token, amount)` | `onlyOwner nonReentrant` | Checks balance, calls `FundingManager.denormalizeFromUsd` then `withdrawLiquidity` |
| `setFeeRate(feeType, rate)` | `onlyOwner nonReentrant` | Rate must be ≤ MAX_FEE_RATE |
| `getFeeBalance(token)` | view | Returns `protocolUsdFeeBalance` (token param ignored) |
| `getProtocolUsdFeeBalance()` | view | Returns `protocolUsdFeeBalance` |
| `getFeeRate(feeType)` | view | Returns rate for fee type key |
| `calculateFee(amount, feeType)` | view | Returns `(amount * rate) / 10000` |
| `setOrderBookManager(address)` | `onlyOwner nonReentrant` | One-time set (reverts if already set) |
| `setFundingManager(address)` | `onlyOwner nonReentrant` | One-time set (reverts if already set) |
| `pause()` / `unpause()` | `onlyOwner` | Emergency controls; `withdrawFee` is NOT paused by pause |

### Fee Collection Flow

```
OrderBookManager → feeVaultManager.collectFee(token, payer, amount, eventId, feeType)
  ├─ FundingManager.collectProtocolFee(payer, amount)  [deducts from userUsdBalances[payer]]
  ├─ protocolUsdFeeBalance += amount
  ├─ totalFeesCollected[token] += amount
  ├─ eventFees[eventId][token] += amount
  ├─ userPaidFees[payer][token] += amount
  └─ emit FeeCollected(token, payer, amount, eventId, feeType)
```

### Fee Withdrawal Flow

```
Owner → feeVaultManager.withdrawFee(token, amount)
  ├─ require protocolUsdFeeBalance >= amount
  ├─ protocolUsdFeeBalance -= amount
  ├─ totalFeesWithdrawn[token] += amount
  ├─ tokenAmount = FundingManager.denormalizeFromUsd(token, amount)
  ├─ FundingManager.withdrawLiquidity(token, tokenAmount, owner())  [transfers tokens to owner]
  └─ emit FeeWithdrawn(token, owner(), amount)
```

---

## Token Pricing Note

`MockOracleAdapter.getTokenPrice(token)` always returns `1e18` for **any** token. This means:
- `normalizeToUsd(token, amount)` ≡ `amount` for 18-decimal tokens
- `denormalizeFromUsd(token, usdAmount)` ≡ `usdAmount` for 18-decimal tokens
- `1 MockUSD token = 1 USD` (1:1 identity mapping)

The `ContractsLinker` already wires `mockOracleAdapter` as the `FundingManager.priceOracleAdapter`.

---

## FundingManager Deposit Constraints

| Constraint | Value |
|-----------|-------|
| `minDepositPerTxnUsd` | `1e18` (min 1 USD per deposit tx) |
| `minTokenBalanceUsd` | `5e18` (user must keep ≥ 5 USD in wallet after deposit) |

The `_depositForUser` helper must account for this by minting `amount + 6e18` so the wallet balance constraint is satisfied.

---

## Test File Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal ERC20 for testing (18 decimals, unlimited mint)
contract MockUSD is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeVaultManagerTest is Test {
    // Contracts
    Deploy public deployer;
    IFeeVaultManager public feeVaultManager;
    IFundingManager public fundingManager;
    IOrderBookManager public orderBookManager;
    MockUSD public mockUSD;

    // Actors
    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // Snapshot
    uint256 public baseSnapshot;

    function setUp() public {
        // 1. Create test actors
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // 2. Deploy full system
        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(uint256(keccak256("owner"))));
        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        // 3. Extract contract references
        feeVaultManager = IFeeVaultManager(address(deployer.feeVaultManager()));
        fundingManager  = IFundingManager(address(deployer.fundingManager()));
        orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));
        owner = deployer.initialOwner();

        // 4. Deploy MockUSD and configure it in FundingManager (owner-only)
        mockUSD = new MockUSD();
        vm.prank(owner);
        fundingManager.configureToken(address(mockUSD), 18, true);

        // 5. Take base snapshot — every test calls vm.revertTo(baseSnapshot) first
        baseSnapshot = vm.snapshot();
    }
```

### Helper Functions

```solidity
    // ============ Helpers ============

    /// @notice Deposit ERC20 for a user into FundingManager to give them USD balance.
    /// @dev Mints amount + 6e18 to user (extra covers minTokenBalanceUsd = 5e18 wallet requirement).
    ///      Result: userUsdBalances[user] increases by `amount` (1:1 ratio, $1 price, 18 decimals).
    function _depositForUser(address user, uint256 amount) internal {
        uint256 totalMint = amount + 6e18;
        mockUSD.mint(user, totalMint);
        vm.startPrank(user);
        IERC20(address(mockUSD)).approve(address(fundingManager), amount);
        fundingManager.depositErc20(IERC20(address(mockUSD)), amount);
        vm.stopPrank();
    }

    /// @notice Collect a fee by impersonating the OrderBookManager.
    function _collectFee(
        address token,
        address payer,
        uint256 amount,
        uint256 eventId,
        string memory feeType
    ) internal {
        vm.prank(address(orderBookManager));
        feeVaultManager.collectFee(token, payer, amount, eventId, feeType);
    }

    /// @notice Convenience: deposit then collect fee in one step.
    function _depositAndCollectFee(
        address user,
        uint256 depositAmount,
        uint256 feeAmount,
        uint256 eventId,
        string memory feeType
    ) internal {
        _depositForUser(user, depositAmount);
        _collectFee(address(mockUSD), user, feeAmount, eventId, feeType);
    }
```

---

## Test Groups Overview

| Group | Name | Test Count |
|-------|------|-----------|
| A | Initialization & Default State | 5 |
| B | Fee Rate Management | 13 |
| C | Fee Collection Interaction Cycle | 10 |
| D | Fee Withdrawal Interaction Cycle | 9 |
| E | State Tracking & View Functions | 7 |
| F | Pause / Unpause Lifecycle | 5 |
| G | Multi-Event / Multi-User Aggregation | 4 |
| H | Edge Cases | 8 |
| **Total** | | **61** |

---

## Group A — Initialization & Default State (5 tests)

**test_A01_InitializeDefaultFeeRates**
```
assertEq(feeVaultManager.getFeeRate("placement"), 10)
assertEq(feeVaultManager.getFeeRate("execution"), 20)
```

**test_A02_InitializeZeroBalances**
```
assertEq(feeVaultManager.protocolUsdFeeBalance(), 0)
assertEq(feeVaultManager.getProtocolUsdFeeBalance(), 0)
assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 0)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 0)
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 0)
```

**test_A03_InitializeConstants**
```
assertEq(feeVaultManager.FEE_PRECISION(), 10000)
assertEq(feeVaultManager.MAX_FEE_RATE(), 1000)
```

**test_A04_InitializeLinkedContracts**
```
assertEq(feeVaultManager.orderBookManager(), address(orderBookManager))
assertEq(feeVaultManager.fundingManager(), address(fundingManager))
```

**test_A05_InitializeOwner**
```
// Cast to OwnableUpgradeable or use low-level call to read owner()
// Assert result == deployer.initialOwner()
```

---

## Group B — Fee Rate Management (13 tests)

**test_B01_SetFeeRateUpdatesRate**
```
vm.prank(owner); feeVaultManager.setFeeRate("placement", 50)
assertEq(feeVaultManager.getFeeRate("placement"), 50)
```

**test_B02_SetFeeRateEmitsEvent**
```
vm.prank(owner)
vm.expectEmit(true, false, false, true)
emit IFeeVaultManager.FeeRateUpdated("placement", 10, 50)
feeVaultManager.setFeeRate("placement", 50)
```
Note: `feeType` is `string indexed` — it is hashed in the topic, use `expectEmit(true, false, false, true)`.

**test_B03_SetFeeRateToZero**
```
vm.prank(owner); feeVaultManager.setFeeRate("placement", 0)
assertEq(feeVaultManager.getFeeRate("placement"), 0)
```

**test_B04_SetFeeRateToMaximum**
```
vm.prank(owner); feeVaultManager.setFeeRate("custom", 1000)  // 10% max allowed
assertEq(feeVaultManager.getFeeRate("custom"), 1000)
```

**test_B05_SetFeeRateAboveMaxReverts**
```
vm.prank(owner)
vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidFeeRate.selector, 1001))
feeVaultManager.setFeeRate("custom", 1001)
```

**test_B06_SetNewFeeType**
```
assertEq(feeVaultManager.getFeeRate("settlement"), 0)  // not yet set
vm.prank(owner); feeVaultManager.setFeeRate("settlement", 5)
assertEq(feeVaultManager.getFeeRate("settlement"), 5)
```

**test_B07_GetFeeRateUnknownType**
```
assertEq(feeVaultManager.getFeeRate("nonexistent"), 0)
```

**test_B08_CalculateFeeWithPlacement**
```
// placement rate = 10 (default)
uint256 fee = feeVaultManager.calculateFee(1000e18, "placement")
assertEq(fee, 1e18)  // 1000 * 10 / 10000 = 1
```

**test_B09_CalculateFeeWithExecution**
```
// execution rate = 20 (default)
uint256 fee = feeVaultManager.calculateFee(1000e18, "execution")
assertEq(fee, 2e18)  // 1000 * 20 / 10000 = 2
```

**test_B10_CalculateFeeWithZeroRate**
```
uint256 fee = feeVaultManager.calculateFee(1000e18, "nonexistent")
assertEq(fee, 0)
```

**test_B11_CalculateFeeWithZeroAmount**
```
uint256 fee = feeVaultManager.calculateFee(0, "placement")
assertEq(fee, 0)
```

**test_B12_CalculateFeeAfterRateChange**
```
assertEq(feeVaultManager.calculateFee(1000e18, "placement"), 1e18)
vm.prank(owner); feeVaultManager.setFeeRate("placement", 100)
assertEq(feeVaultManager.calculateFee(1000e18, "placement"), 10e18)  // 1000 * 100 / 10000 = 10
```

**test_B13_SetFeeRateMultipleTypes**
```
vm.startPrank(owner)
feeVaultManager.setFeeRate("placement", 15)
feeVaultManager.setFeeRate("execution", 25)
feeVaultManager.setFeeRate("settlement", 30)
vm.stopPrank()
assertEq(feeVaultManager.getFeeRate("placement"), 15)
assertEq(feeVaultManager.getFeeRate("execution"), 25)
assertEq(feeVaultManager.getFeeRate("settlement"), 30)
```

---

## Group C — Fee Collection Interaction Cycle (10 tests)

**test_C01_CollectFeeBasicFlow**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1e18)
```

**test_C02_CollectFeeUpdatesAllCounters**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 2e18, 42, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 2e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 2e18)
assertEq(feeVaultManager.eventFees(42, address(mockUSD)), 2e18)
assertEq(feeVaultManager.userPaidFees(user1, address(mockUSD)), 2e18)
```

**test_C03_CollectFeeEmitsEvent**
```
_depositForUser(user1, 100e18)
vm.expectEmit(true, true, false, true)
emit IFeeVaultManager.FeeCollected(address(mockUSD), user1, 1e18, 1, "placement")
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
```

**test_C04_CollectFeeDeductsUserBalance**
```
_depositForUser(user1, 100e18)
uint256 balBefore = fundingManager.getUserUsdBalance(user1)
_collectFee(address(mockUSD), user1, 3e18, 1, "placement")
uint256 balAfter = fundingManager.getUserUsdBalance(user1)
assertEq(balBefore - balAfter, 3e18)
```

**test_C05_CollectFeeZeroAmountReverts**
```
_depositForUser(user1, 100e18)
vm.prank(address(orderBookManager))
vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidAmount.selector, 0))
feeVaultManager.collectFee(address(mockUSD), user1, 0, 1, "placement")
```

**test_C06_CollectFeeInsufficientUserBalance**
```
_depositForUser(user1, 5e18)  // deposits 5e18
vm.prank(address(orderBookManager))
vm.expectRevert()  // InsufficientUsdBalance from FundingManager
feeVaultManager.collectFee(address(mockUSD), user1, 10e18, 1, "placement")
```

**test_C07_CollectFeeMultipleTimes**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
_collectFee(address(mockUSD), user1, 2e18, 1, "execution")
_collectFee(address(mockUSD), user1, 3e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 6e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 6e18)
assertEq(feeVaultManager.userPaidFees(user1, address(mockUSD)), 6e18)
```

**test_C08_CollectFeeMultipleEvents**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 2e18, 1, "placement")
_collectFee(address(mockUSD), user1, 3e18, 2, "placement")
assertEq(feeVaultManager.eventFees(1, address(mockUSD)), 2e18)
assertEq(feeVaultManager.eventFees(2, address(mockUSD)), 3e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 5e18)
```

**test_C09_CollectFeeMultipleUsers**
```
_depositForUser(user1, 100e18)
_depositForUser(user2, 100e18)
_collectFee(address(mockUSD), user1, 2e18, 1, "placement")
_collectFee(address(mockUSD), user2, 3e18, 1, "placement")
assertEq(feeVaultManager.userPaidFees(user1, address(mockUSD)), 2e18)
assertEq(feeVaultManager.userPaidFees(user2, address(mockUSD)), 3e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 5e18)
```

**test_C10_CollectFeeDifferentFeeTypes**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
_collectFee(address(mockUSD), user1, 2e18, 1, "execution")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 3e18)
// Both fee types contribute to the same shared protocolUsdFeeBalance
```

---

## Group D — Fee Withdrawal Interaction Cycle (9 tests)

**test_D01_WithdrawFeeBasicFlow**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
uint256 ownerBalBefore = mockUSD.balanceOf(owner)
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 5e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 5e18)
assertEq(mockUSD.balanceOf(owner) - ownerBalBefore, 5e18)  // 1:1 at $1 price, 18 decimals
```

**test_D02_WithdrawFeeFullAmount**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 10e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 0)
```

**test_D03_WithdrawFeeEmitsEvent**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner)
vm.expectEmit(true, true, false, true)
emit IFeeVaultManager.FeeWithdrawn(address(mockUSD), owner, 5e18)
feeVaultManager.withdrawFee(address(mockUSD), 5e18)
```

**test_D04_WithdrawFeeUpdatesTotalWithdrawn**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 5e18)
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 5e18)
```

**test_D05_WithdrawFeeOwnerReceivesTokens**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
uint256 balBefore = mockUSD.balanceOf(owner)
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 7e18)
assertEq(mockUSD.balanceOf(owner) - balBefore, 7e18)
```

**test_D06_WithdrawFeeZeroAmountReverts**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner)
vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidAmount.selector, 0))
feeVaultManager.withdrawFee(address(mockUSD), 0)
```

**test_D07_WithdrawFeeExceedsBalanceReverts**
```
_depositAndCollectFee(user1, 100e18, 5e18, 1, "placement")
vm.prank(owner)
vm.expectRevert(
    abi.encodeWithSelector(IFeeVaultManager.InsufficientFeeBalance.selector, address(mockUSD), 10e18, 5e18)
)
feeVaultManager.withdrawFee(address(mockUSD), 10e18)
```

**test_D08_WithdrawFeeMultipleTimes**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 3e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 7e18)
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 4e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 3e18)
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 7e18)
```

**test_D09_WithdrawFeeReducesFundingManagerLiquidity**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
uint256 liqBefore = fundingManager.getTokenLiquidity(address(mockUSD))
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 5e18)
uint256 liqAfter = fundingManager.getTokenLiquidity(address(mockUSD))
assertEq(liqBefore - liqAfter, 5e18)
```

---

## Group E — State Tracking & View Functions (7 tests)

**test_E01_GetFeeBalanceReturnsProtocolBalance**
```
_depositAndCollectFee(user1, 100e18, 7e18, 1, "placement")
// token param is ignored — both calls return the same protocolUsdFeeBalance
assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 7e18)
assertEq(feeVaultManager.getFeeBalance(address(0x1234)), 7e18)
assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), feeVaultManager.protocolUsdFeeBalance())
```

**test_E02_GetProtocolUsdFeeBalanceMatchesPublicVar**
```
_depositAndCollectFee(user1, 100e18, 4e18, 1, "placement")
assertEq(feeVaultManager.getProtocolUsdFeeBalance(), feeVaultManager.protocolUsdFeeBalance())
```

**test_E03_TotalFeesCollectedPerToken**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 3e18, 1, "placement")
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 3e18)
// If using a different token label for the second call, they are tracked independently:
_collectFee(address(0xDEAD), user1, 2e18, 2, "execution")  // note: FundingManager still uses user's USD balance
assertEq(feeVaultManager.totalFeesCollected(address(0xDEAD)), 2e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 3e18)  // unchanged
```

**test_E04_TotalFeesWithdrawnPerToken**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 4e18)
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 4e18)
```

**test_E05_EventFeesPerEventPerToken**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 10, "placement")
_collectFee(address(mockUSD), user1, 2e18, 20, "placement")
_collectFee(address(mockUSD), user1, 3e18, 30, "placement")
assertEq(feeVaultManager.eventFees(10, address(mockUSD)), 1e18)
assertEq(feeVaultManager.eventFees(20, address(mockUSD)), 2e18)
assertEq(feeVaultManager.eventFees(30, address(mockUSD)), 3e18)
```

**test_E06_UserPaidFeesPerUserPerToken**
```
_depositForUser(user1, 100e18)
_depositForUser(user2, 100e18)
_depositForUser(user3, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
_collectFee(address(mockUSD), user2, 2e18, 1, "placement")
_collectFee(address(mockUSD), user3, 3e18, 1, "placement")
assertEq(feeVaultManager.userPaidFees(user1, address(mockUSD)), 1e18)
assertEq(feeVaultManager.userPaidFees(user2, address(mockUSD)), 2e18)
assertEq(feeVaultManager.userPaidFees(user3, address(mockUSD)), 3e18)
```

**test_E07_BalanceInvariant**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
_depositAndCollectFee(user2, 100e18,  5e18, 2, "execution")
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 6e18)
uint256 collected = feeVaultManager.totalFeesCollected(address(mockUSD))
uint256 withdrawn = feeVaultManager.totalFeesWithdrawn(address(mockUSD))
assertEq(feeVaultManager.protocolUsdFeeBalance(), collected - withdrawn)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 9e18)  // 15 - 6
```

---

## Group F — Pause / Unpause Lifecycle (5 tests)

**test_F01_PauseBlocksCollectFee**
```
_depositForUser(user1, 100e18)
vm.prank(owner); feeVaultManager.pause()
vm.prank(address(orderBookManager))
vm.expectRevert()  // EnforcedPause from OZ PausableUpgradeable
feeVaultManager.collectFee(address(mockUSD), user1, 1e18, 1, "placement")
```

**test_F02_UnpauseRestoresCollectFee**
```
_depositForUser(user1, 100e18)
vm.prank(owner); feeVaultManager.pause()
vm.prank(owner); feeVaultManager.unpause()
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1e18)
```

**test_F03_PauseDoesNotBlockWithdrawFee**
```
// withdrawFee has no whenNotPaused modifier
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.prank(owner); feeVaultManager.pause()
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 5e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 5e18)
```

**test_F04_PauseDoesNotBlockViewFunctions**
```
vm.prank(owner); feeVaultManager.pause()
feeVaultManager.getFeeRate("placement")           // must not revert
feeVaultManager.calculateFee(100e18, "placement") // must not revert
feeVaultManager.getFeeBalance(address(mockUSD))   // must not revert
feeVaultManager.getProtocolUsdFeeBalance()        // must not revert
```

**test_F05_PauseUnpauseCycle**
```
_depositForUser(user1, 100e18)
vm.startPrank(owner)
feeVaultManager.pause()
feeVaultManager.unpause()
feeVaultManager.pause()
feeVaultManager.unpause()
vm.stopPrank()
_collectFee(address(mockUSD), user1, 1e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1e18)
```

---

## Group G — Multi-Event / Multi-User Aggregation (4 tests)

**test_G01_ThreeUsersThreeEvents**
```
_depositForUser(user1, 100e18)
_depositForUser(user2, 100e18)
_depositForUser(user3, 100e18)
_collectFee(mockUSD, user1, 1e18, 1, "placement")  // user1 → event1
_collectFee(mockUSD, user1, 2e18, 2, "execution")  // user1 → event2
_collectFee(mockUSD, user2, 3e18, 2, "placement")  // user2 → event2
_collectFee(mockUSD, user2, 4e18, 3, "placement")  // user2 → event3
_collectFee(mockUSD, user3, 5e18, 3, "execution")  // user3 → event3
assertEq(feeVaultManager.protocolUsdFeeBalance(), 15e18)
assertEq(feeVaultManager.eventFees(1, address(mockUSD)), 1e18)
assertEq(feeVaultManager.eventFees(2, address(mockUSD)), 5e18)   // 2 + 3
assertEq(feeVaultManager.eventFees(3, address(mockUSD)), 9e18)   // 4 + 5
assertEq(feeVaultManager.userPaidFees(user1, address(mockUSD)), 3e18)
assertEq(feeVaultManager.userPaidFees(user2, address(mockUSD)), 7e18)
assertEq(feeVaultManager.userPaidFees(user3, address(mockUSD)), 5e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 15e18)
```

**test_G02_CollectThenWithdrawThenCollectMore**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 10e18)
vm.prank(owner); feeVaultManager.withdrawFee(address(mockUSD), 5e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 5e18)
_collectFee(address(mockUSD), user1, 8e18, 2, "placement")  // user1 still has balance
assertEq(feeVaultManager.protocolUsdFeeBalance(), 13e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 18e18)
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 5e18)
```

**test_G03_MultipleWithdrawalsUntilDrained**
```
_depositAndCollectFee(user1, 100e18, 10e18, 1, "placement")
vm.startPrank(owner)
feeVaultManager.withdrawFee(address(mockUSD), 3e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 7e18)
feeVaultManager.withdrawFee(address(mockUSD), 3e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 4e18)
feeVaultManager.withdrawFee(address(mockUSD), 4e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 0)
vm.stopPrank()
assertEq(feeVaultManager.totalFeesWithdrawn(address(mockUSD)), 10e18)
```

**test_G04_TenUsersAccumulateFees**
```
// Create 10 users with makeAddr(), deposit 50e18 and collect 1e18 each
address[10] memory users;
for (uint i = 0; i < 10; i++) {
    users[i] = makeAddr(string.concat("bulk_user", vm.toString(i)));
    _depositAndCollectFee(users[i], 50e18, 1e18, i + 1, "placement");
}
assertEq(feeVaultManager.protocolUsdFeeBalance(), 10e18)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 10e18)
for (uint i = 0; i < 10; i++) {
    assertEq(feeVaultManager.userPaidFees(users[i], address(mockUSD)), 1e18)
}
```

---

## Group H — Edge Cases (8 tests)

**test_H01_CollectFeeSmallAmount**
```
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1, 1, "placement")  // 1 wei
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1)
assertEq(feeVaultManager.totalFeesCollected(address(mockUSD)), 1)
```

**test_H02_CollectFeeLargeAmount**
```
_depositForUser(user1, 2_000_000e18)
_collectFee(address(mockUSD), user1, 1_000_000e18, 1, "placement")
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1_000_000e18)
```

**test_H03_CalculateFeeRoundsTruncated**
```
// 1 wei * 10 / 10000 = 0 (integer division truncates)
assertEq(feeVaultManager.calculateFee(1, "placement"), 0)
```

**test_H04_CalculateFeeExactDivision**
```
// 10000e18 * 10 / 10000 = exactly 10e18
assertEq(feeVaultManager.calculateFee(10000e18, "placement"), 10e18)
```

**test_H05_WithdrawWithNoFeesReverts**
```
vm.prank(owner)
vm.expectRevert(
    abi.encodeWithSelector(IFeeVaultManager.InsufficientFeeBalance.selector, address(mockUSD), 1, 0)
)
feeVaultManager.withdrawFee(address(mockUSD), 1)
```

**test_H06_CollectFeeWithEventIdZero**
```
// FeeVaultManager does NOT validate eventId (no event lookup)
_depositForUser(user1, 100e18)
_collectFee(address(mockUSD), user1, 1e18, 0, "placement")
assertEq(feeVaultManager.eventFees(0, address(mockUSD)), 1e18)
assertEq(feeVaultManager.protocolUsdFeeBalance(), 1e18)
```

**test_H07_GetFeeBalanceBeforeAnyCollection**
```
assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 0)
assertEq(feeVaultManager.getProtocolUsdFeeBalance(), 0)
```

**test_H08_SetFeeRateOverwriteEmitsOldAndNewRate**
```
// Default placement rate is 10; overwrite with 50
vm.prank(owner)
vm.expectEmit(true, false, false, true)
emit IFeeVaultManager.FeeRateUpdated("placement", 10, 50)
feeVaultManager.setFeeRate("placement", 50)
assertEq(feeVaultManager.getFeeRate("placement"), 50)
```

---

## Implementation Checklist

- [ ] Create `/workspace/test/unit/FeeVaultManager.t.sol`
- [ ] Add `MockUSD` contract at top of file
- [ ] Implement `setUp()` per structure above
- [ ] Implement `_depositForUser`, `_collectFee`, `_depositAndCollectFee` helpers
- [ ] Implement all 61 tests in groups A–H
- [ ] Every test starts with `vm.revertTo(baseSnapshot)`
- [ ] Run `forge test --match-contract FeeVaultManagerTest -vvv` — all tests pass
- [ ] Check `forge coverage --match-contract FeeVaultManagerTest` — aim for 80%+

---

## Review Section

**Status**: Complete — 61/61 tests passing.

**File created**: `/workspace/test/unit/FeeVaultManager.t.sol`

**Implementation notes**:
- `FeeVaultManager` is a UUPS proxy with a `receive()` payable fallback; casting requires `payable(address(...))` → `FeeVaultManager(payable(address(...)))`
- `FEE_PRECISION`, `MAX_FEE_RATE`, and all public state mappings (`protocolUsdFeeBalance`, `totalFeesCollected`, `totalFeesWithdrawn`, `eventFees`, `userPaidFees`) are not on the `IFeeVaultManager` interface; accessed via concrete `fvm` variable typed as `FeeVaultManager`
- `MockOracleAdapter.getTokenPrice()` always returns `1e18` — 18-decimal tokens price at $1 making normalisation a no-op (identity function), which simplifies expected values greatly
- The `vm.snapshot()` / `vm.revertTo()` cheatcodes emit deprecation warnings in newer Foundry; these are cosmetic and do not affect test execution
