# FundingManager Test Implementation Plan

## Baseline
"Focus on usability and completeness of interaction cycle, ignore security, ignore gas usage"

## Pattern
- Deploy via `Deploy` script in setUp
- `baseSnapshot = vm.snapshot()` at end of setUp
- Every test: `vm.revertTo(baseSnapshot)` first
- Naming: `test_[GROUP][NUMBER]_[Description]`
- Helpers for repeated actions

---

## Key Facts / Assumptions

- MockOracleAdapter.getTokenPrice() → always `1e18` for all tokens
- 18-decimal token at $1 oracle price: `normalizeToUsd(amount)` = `amount` (identity)
- 6-decimal token at $1 oracle price: `normalizeToUsd(amount)` = `amount * 1e12`
- `minDepositPerTxnUsd = 1e18` (1 USD), `minTokenBalanceUsd = 5e18` (5 USD)
- Deposit constraint: wallet must retain ≥5e18 USD after deposit → mint `amount + 6e18`
- `FEE_PRECISION = 10000`, price range 1–10000 bp
- `settleMatchedOrder`: buyer gets `matchAmount` Long tokens, seller gets `matchAmount * matchPrice / 10000` USD
- Public state mappings (`totalDeposited`, `totalWithdrawn`, `userUsdBalances`, `longPositions`, etc.) not on `IFundingManager` → require concrete `FundingManager(payable(...))` type
- `receive()` payable means cast needs intermediate `payable()`: `FundingManager(payable(address(deployer.fundingManager())))`

---

## File: `test/unit/FundingManager.t.sol`

### Imports
```solidity
import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {FundingManager} from "../../src/core/FundingManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Decimals} from ... (inline MockERC20 with decimals param)
```

### Helper Contracts
```solidity
contract MockToken is ERC20 {
    uint8 private _decimals;
    constructor(string name, string symbol, uint8 dec) ERC20(name, symbol) { _decimals = dec; }
    function decimals() public view override returns (uint8) { return _decimals; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
```

### setUp()
```solidity
function setUp() public {
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    user3 = makeAddr("user3");
    vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(uint256(keccak256("owner"))));
    deployer = new Deploy();
    deployer.setUp();
    deployer.run();
    fundingManager = IFundingManager(address(deployer.fundingManager()));
    fm = FundingManager(payable(address(deployer.fundingManager())));
    orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));
    feeVaultManager = IFeeVaultManager(address(deployer.feeVaultManager()));
    owner = deployer.initialOwner();
    mockToken18 = new MockToken("Mock USD", "mUSD", 18);
    mockToken6 = new MockToken("Mock USDC", "mUSDC", 6);
    vm.startPrank(owner);
    fundingManager.configureToken(address(mockToken18), 18, true);
    fundingManager.configureToken(address(mockToken6), 6, true);
    vm.stopPrank();
    baseSnapshot = vm.snapshot();
}
```

### Helpers
```solidity
// Mint enough for user to deposit `amount` while keeping ≥5e18 USD in wallet
function _depositForUser(address user, address token, uint256 amount) internal;
// Mint + approve + depositErc20 for 18-decimal token
function _deposit18(address user, uint256 amount) internal;
// Mint + approve + depositErc20 for 6-decimal token (deposits in raw 6-dec units)
function _deposit6(address user, uint256 amount6) internal;
// Prank as orderBookManager to registerEvent
function _registerEvent(uint256 eventId, uint8 outcomeCount) internal;
// Prank as orderBookManager to lockForOrder
function _lockForOrder(address user, uint256 orderId, bool isBuy, uint256 amount, uint256 eventId, uint8 outcomeIndex) internal;
// Prank as orderBookManager to unlockForOrder
function _unlockForOrder(address user, uint256 orderId, bool isBuy, uint256 eventId, uint8 outcomeIndex) internal;
// Prank as orderBookManager to settleMatchedOrder
function _settleMatchedOrder(uint256 buyId, uint256 sellId, address buyer, address seller, uint256 amount, uint256 price, uint256 eventId, uint8 outcome) internal;
// Prank as orderBookManager to markEventSettled
function _markEventSettled(uint256 eventId, uint8 winningOutcome) internal;
// Full setup: deposit + register event + mint complete set (gives user Long tokens for all outcomes)
function _setupUserWithLongTokens(address user, uint256 eventId, uint8 outcomeCount, uint256 usdAmount) internal;
```

---

## Group A: Token Configuration (7 tests)

**A01** `test_A01_ConfigureNewToken`
- Owner configures a brand-new 18-dec token (enabled=true)
- Assert: `getSupportedTokens()` includes token, `tokenConfigs[token].decimals == 18`, `tokenConfigs[token].enabled == true`
- Expect event: `TokenConfigured`

**A02** `test_A02_ReconfigureTokenEnabled`
- Owner configures token (enabled=true), then reconfigures (enabled=false)
- Assert: token no longer accepted for deposit (deposit reverts with `TokenIsNotSupported`)

**A03** `test_A03_ConfigureSixDecimalToken`
- Owner configures 6-decimal token
- Assert: `tokenConfigs[address(mockToken6)].decimals == 6`
- Verify `normalizeToUsd(token6, 1e6)` returns ~`1e18` (factor = 10^12 × price 1e18 / 1e18)

**A04** `test_A04_ConfigureTokenNonOwnerReverts`
- Non-owner tries configureToken
- Expect revert (`OwnableUnauthorizedAccount`)

**A05** `test_A05_DisableTokenBlocksDeposit`
- Configure token as enabled, then disable it
- User tries to deposit → expect revert `TokenIsNotSupported`

**A06** `test_A06_SetMinDepositPerTxnUsd`
- Owner calls `setMinDepositPerTxnUsd(2e18)`
- Assert: `getMinDepositPerTxnUsd() == 2e18`
- Verify deposit below 2e18 reverts

**A07** `test_A07_SetMinTokenBalanceUsd`
- Owner calls `setMinTokenBalanceUsd(10e18)`
- Assert: `getMinTokenBalanceUsd() == 10e18`
- Verify deposit that leaves <10e18 in wallet reverts

---

## Group B: Deposit ERC20 (8 tests)

**B01** `test_B01_DepositErc20BasicFlow`
- Mint 106e18 to user1, approve 100e18, deposit 100e18 mockToken18
- Assert: `getUserUsdBalance(user1) == 100e18`
- Assert: `getTokenLiquidity(address(mockToken18)) == 100e18`
- Assert: token balance of FundingManager == 100e18
- Expect event: `DepositToken`

**B02** `test_B02_DepositErc20AccumulatesBalance`
- User1 deposits 50e18 twice (two separate txns)
- Assert: `getUserUsdBalance(user1) == 100e18`
- Assert: `getTokenLiquidity == 100e18`

**B03** `test_B03_DepositErc20MultipleUsers`
- user1 deposits 100e18, user2 deposits 200e18
- Assert: balances are independent
- Assert: `getTokenLiquidity == 300e18`

**B04** `test_B04_DepositBelowMinPerTxnReverts`
- Attempt to deposit 0.5e18 (below 1e18 minimum)
- Expect revert

**B05** `test_B05_DepositLeavingWalletBelowMinReverts`
- Mint exactly 105e18 to user (1e18 stays in wallet = <5e18 threshold)
- Attempt deposit 104e18
- Expect revert (would leave 1e18 < 5e18)

**B06** `test_B06_DepositSixDecimalToken`
- Mint 1006 units of 6-dec token (106e6) to user (leaves 6e6 = $6 in wallet)
- Deposit 100e6 (= 100 USD after normalization × 10^12)
- Assert: `getUserUsdBalance(user1) == 100e18`
- Assert: `getTokenLiquidity(address(mockToken6)) == 100e6`

**B07** `test_B07_DepositErc20WhenPausedReverts`
- Owner pauses
- User tries to deposit → expect revert (`EnforcedPause`)

**B08** `test_B08_DepositUpdatesTotalDeposited`
- User deposits 100e18
- Assert: `fm.totalDeposited(address(mockToken18)) == 100e18` (concrete type needed)

---

## Group C: Withdrawal (8 tests)

**C01** `test_C01_WithdrawDirectBasicFlow`
- User deposits 100e18, then withdrawDirect(token, 60e18)
- Assert: `getUserUsdBalance(user1) == 40e18`
- Assert: `getTokenLiquidity == 40e18`
- Assert: token received by user == 60e18 (identity for 18-dec at $1)
- Expect event: `WithdrawToken`

**C02** `test_C02_WithdrawTokenAmountBasicFlow`
- User deposits 100e18, then withdrawTokenAmount(token, 60e18)
- Assert: balance reduced by 60e18 USD
- Assert: user receives 60e18 tokens

**C03** `test_C03_WithdrawFullBalance`
- User deposits 100e18, withdraws all (100e18 USD)
- Assert: `getUserUsdBalance == 0`
- Assert: `getTokenLiquidity == 0`

**C04** `test_C04_WithdrawMoreThanBalanceReverts`
- User deposits 50e18, tries to withdraw 100e18
- Expect revert (`InsufficientUsdBalance`)

**C05** `test_C05_WithdrawSixDecimalToken`
- User deposits 100e6 of 6-dec token (= 100e18 USD)
- WithdrawDirect(token6, 50e18 USD) → should receive ~50e6 tokens
- Assert: user token balance == 50e6

**C06** `test_C06_WithdrawWhenPausedReverts`
- Deposit, then owner pauses, then try withdraw → revert

**C07** `test_C07_WithdrawUpdatesTotalWithdrawn`
- Deposit 100e18, withdraw 60e18
- Assert: `fm.totalWithdrawn(address(mockToken18)) == 60e18`

**C08** `test_C08_CanWithdrawView`
- Deposit 100e18
- Assert: `canWithdraw(token, 60e18) == true`
- Assert: `canWithdraw(token, 150e18) == false` (insufficient liquidity)

---

## Group D: Normalization & Pricing (6 tests)

**D01** `test_D01_NormalizeToUsd18DecimalToken`
- `normalizeToUsd(mockToken18, 100e18)` → expect `100e18`
- `normalizeToUsd(mockToken18, 1e18)` → expect `1e18`
- `normalizeToUsd(mockToken18, 0)` → expect `0`

**D02** `test_D02_NormalizeToUsd6DecimalToken`
- `normalizeToUsd(mockToken6, 1e6)` → expect `1e18` (factor = 10^12, price = 1e18)
- `normalizeToUsd(mockToken6, 100e6)` → expect `100e18`

**D03** `test_D03_DenormalizeFromUsd18DecimalToken`
- `denormalizeFromUsd(mockToken18, 100e18)` → expect `100e18`
- `denormalizeFromUsd(mockToken18, 0)` → expect `0`

**D04** `test_D04_DenormalizeFromUsd6DecimalToken`
- `denormalizeFromUsd(mockToken6, 1e18)` → expect `1e6`
- `denormalizeFromUsd(mockToken6, 100e18)` → expect `100e6`

**D05** `test_D05_NormalizeDenormalizeRoundTrip`
- For 18-dec token: `denormalizeFromUsd(t, normalizeToUsd(t, 77e18)) == 77e18`
- For 6-dec token: `denormalizeFromUsd(t6, normalizeToUsd(t6, 77e6)) == 77e6`

**D06** `test_D06_GetTokenPrice`
- `getTokenPrice(mockToken18)` → expect `1e18` (MockOracleAdapter returns 1e18)
- `getTokenPrice(address(0))` → expect `1e18` (default fallback)

---

## Group E: Balance & Liquidity Queries (5 tests)

**E01** `test_E01_GetUserUsdBalanceAfterDeposit`
- Deposit 100e18 → `getUserUsdBalance(user1) == 100e18`

**E02** `test_E02_GetTokenLiquidityAfterDeposit`
- Deposit 100e18 → `getTokenLiquidity(mockToken18) == 100e18`

**E03** `test_E03_GetAllTokenBalancesEmpty`
- No deposit: `getAllTokenBalances(user1)` returns empty/zero values

**E04** `test_E04_GetSupportedTokens`
- Two tokens configured in setUp
- `getSupportedTokens()` includes both

**E05** `test_E05_MultiTokenLiquidity`
- user1 deposits 100e18 of token18, user2 deposits 100e6 of token6
- Assert: `getTokenLiquidity(token18) == 100e18`
- Assert: `getTokenLiquidity(token6) == 100e6`
- Assert: `getUserUsdBalance(user1) == 100e18`, `getUserUsdBalance(user2) == 100e18`

---

## Group F: Complete Set Mint / Burn (8 tests)

**F01** `test_F01_MintCompleteSetBasicFlow`
- _deposit18(user1, 100e18), _registerEvent(1, 2 outcomes)
- mintCompleteSetDirect(eventId=1, usdAmount=50e18)
- Assert: `getUserUsdBalance(user1) == 50e18` (locked into prize pool)
- Assert: `getLongPosition(user1, 1, 0) == 50e18`
- Assert: `getLongPosition(user1, 1, 1) == 50e18` (both outcomes)
- Assert: `getEventPrizePool(1) == 50e18`
- Expect event: `CompleteSetMinted`

**F02** `test_F02_MintCompleteSetThreeOutcomes`
- Register event with 3 outcomes, mint 90e18 complete set
- Assert: `getLongPosition(user1, 1, 0) == 90e18`
- Assert: `getLongPosition(user1, 1, 1) == 90e18`
- Assert: `getLongPosition(user1, 1, 2) == 90e18`
- Assert: prize pool == 90e18

**F03** `test_F03_MintCompleteSetInsufficientBalanceReverts`
- Deposit 30e18, try to mint 50e18 complete set
- Expect revert (`InsufficientUsdBalance`)

**F04** `test_F04_BurnCompleteSetBasicFlow`
- Deposit 100e18, register event (2 outcomes), mint 60e18 complete set
- burnCompleteSetDirect(eventId=1, usdAmount=30e18)
- Assert: `getUserUsdBalance` increases by 30e18 (back to 70e18)
- Assert: `getLongPosition(user1, 1, 0) == 30e18`, `getLongPosition(user1, 1, 1) == 30e18`
- Assert: `getEventPrizePool(1) == 30e18`
- Expect event: `CompleteSetBurned`

**F05** `test_F05_BurnCompleteSetInsufficientLongTokensReverts`
- Deposit 100e18, mint 50e18 complete set
- Try to burn 80e18 → revert (`InsufficientLongPosition`)

**F06** `test_F06_MintBurnRoundTrip`
- Deposit 100e18, mint 60e18, burn 60e18
- Final state: `getUserUsdBalance == 100e18`, positions == 0, prize pool == 0

**F07** `test_F07_MintCompleteSetWhenPausedReverts`
- Deposit, pause, try mintCompleteSet → revert

**F08** `test_F08_MintCompleteSetUpdatesLiquidityAndPrizePool`
- Deposit 100e18 (tokenLiquidity = 100e18), mint 40e18 complete set
- Assert: `getTokenLiquidity` stays 100e18 (no external token movement)
- Assert: `getEventPrizePool(1) == 40e18`
- Assert: `getUserUsdBalance(user1) == 60e18`

---

## Group G: Order Locking / Unlocking (8 tests)

**G01** `test_G01_LockForBuyOrderBasicFlow`
- _deposit18(user1, 100e18), _registerEvent(1, 2)
- _lockForOrder(user1, orderId=101, isBuy=true, amount=40e18, eventId=1, outcomeIndex=0)
- Assert: `getOrderLockedUsd(101) == 40e18`
- Assert: `getUserUsdBalance(user1) == 60e18` (deducted)
- Expect event: `FundsLocked`

**G02** `test_G02_LockForSellOrderBasicFlow`
- Setup user with Long tokens via mintCompleteSet
- _lockForOrder(user1, orderId=102, isBuy=false, amount=20e18, eventId=1, outcomeIndex=0)
- Assert: `getOrderLockedLong(102) == 20e18`
- Assert: `getLongPosition(user1, 1, 0)` reduced by 20e18

**G03** `test_G03_UnlockForBuyOrderBasicFlow`
- Deposit 100e18, lock 40e18 for buy order 101
- _unlockForOrder(user1, 101, isBuy=true, 1, 0)
- Assert: `getOrderLockedUsd(101) == 0`
- Assert: `getUserUsdBalance(user1) == 100e18` (restored)
- Expect event: `FundsUnlocked`

**G04** `test_G04_UnlockForSellOrderBasicFlow`
- Setup long tokens, lock 20e18 for sell order 102
- _unlockForOrder(user1, 102, isBuy=false, 1, 0)
- Assert: `getOrderLockedLong(102) == 0`
- Assert: `getLongPosition(user1, 1, 0)` restored

**G05** `test_G05_LockBuyOrderInsufficientBalanceReverts`
- Deposit 30e18, try to lock 50e18 for buy
- Expect revert (`InsufficientUsdBalance`)

**G06** `test_G06_LockSellOrderInsufficientLongTokensReverts`
- Register event, lock for sell without having Long tokens
- Expect revert (`InsufficientLongPosition`)

**G07** `test_G07_LockOrderNonOrderBookManagerReverts`
- user1 tries to call `lockForOrder` directly
- Expect revert (unauthorized)

**G08** `test_G08_MultipleOrderLocksForSameUser`
- Deposit 100e18, lock 30e18 for order 101, lock 40e18 for order 102
- Assert: `getUserUsdBalance == 30e18`
- Assert: `getOrderLockedUsd(101) == 30e18`, `getOrderLockedUsd(102) == 40e18`

---

## Group H: Order Settlement (10 tests)

**H01** `test_H01_SettleMatchedOrderBasicFlow`
- Setup: user1 deposits 100e18, user2 has Long tokens
- Register event(1, 2), user2 mints complete set (has Long tokens), user1 locks for buy, user2 locks for sell
- _settleMatchedOrder(buyId=101, sellId=102, buyer=user1, seller=user2, matchAmount=10e18, matchPrice=5000, eventId=1, outcomeIndex=0)
- Expected: buyer gets 10e18 Long tokens for outcome 0
- Expected: seller receives `10e18 * 5000 / 10000 = 5e18` USD
- Assert: `getLongPosition(user1, 1, 0) == 10e18`
- Assert: seller USD balance increased by 5e18
- Assert: `getOrderLockedUsd(101)` reduced, `getOrderLockedLong(102)` reduced
- Expect event: `OrderSettled`

**H02** `test_H02_SettleMatchedOrderFullPrice`
- matchPrice=10000 (100%), matchAmount=10e18
- Buyer pays 10e18 USD (locked), gets 10e18 Long tokens
- Seller receives 10e18 USD (1:1)

**H03** `test_H03_SettleMatchedOrderMinimalPrice`
- matchPrice=1 (0.01%), matchAmount=10e18
- Seller receives `10e18 * 1 / 10000 = 0.001e18` USD

**H04** `test_H04_SettleMatchedOrderNonOrderBookManagerReverts`
- Direct call to settleMatchedOrder → revert

**H05** `test_H05_SettleMatchedOrderUpdatesLiquidityCorrectly`
- Full settlement flow
- Assert: total tokenLiquidity unchanged (just redistributed between USD balances and locked orders)

**H06** `test_H06_MultipleSettlementsAccumulate`
- user1 buys 5e18 Long twice at price 5000
- Assert: `getLongPosition(user1, 1, 0) == 10e18`

**H07** `test_H07_SettleMatchedOrderBuyerGetsLongTokenForCorrectOutcome`
- Setup with 3 outcomes, settle for outcome 1
- Assert: `getLongPosition(buyer, 1, 1) == matchAmount`
- Assert: outcome 0 and 2 unchanged

**H08** `test_H08_SettlementPriceCalculationVerification`
- matchAmount=100e18, matchPrice=3000
- Seller should receive exactly `100e18 * 3000 / 10000 = 30e18` USD
- Verify by checking balance delta

**H09** `test_H09_PartialFillThenCancel`
- Lock 100e18 for buy order, settle 60e18 partial, then unlock remaining 40e18
- Assert: buyer has 60e18 Long, full locked USD reconciled

**H10** `test_H10_GetOrderLockedAfterSettlement`
- After full settlement, `getOrderLockedUsd(orderId)` == 0 (fully consumed)

---

## Group I: Event Settlement & Winnings Redemption (10 tests)

**I01** `test_I01_RegisterEventBasicFlow`
- _registerEvent(1, 2)
- Assert: `isEventSettled(1) == false`
- Assert: event can receive Long position minting

**I02** `test_I02_MarkEventSettledBasicFlow`
- Register event(1, 2), _markEventSettled(1, winningOutcome=0)
- Assert: `isEventSettled(1) == true`
- Expect event: `EventMarkedSettled`

**I03** `test_I03_MarkEventSettledNonOrderBookManagerReverts`
- Direct call to `markEventSettled` → revert

**I04** `test_I04_RedeemWinningsBasicFlow`
- Register event(1, 2), deposit 100e18, mint 60e18 complete set (user has 60 Long[0] + 60 Long[1])
- _markEventSettled(1, winningOutcome=0)
- user calls `redeemWinnings(1)`
- Expected: user gets 60e18 USD back (60 winning Long[0] × 1 USD each)
- Assert: `getUserUsdBalance` increased by 60e18
- Assert: `getLongPosition(user, 1, 0) == 0` (consumed)
- Assert: `getLongPosition(user, 1, 1) == 60e18` (losing tokens remain)
- Expect event: `WinningsRedeemed`

**I05** `test_I05_RedeemWinningsNoPositionReverts`
- Event settled, user has no winning Long tokens
- `redeemWinnings` → revert or return 0 (check actual behavior)

**I06** `test_I06_CanRedeemWinningsView`
- Before settlement: `canRedeemWinnings(1, user1)` → (false, 0)
- After settlement + having position: `canRedeemWinnings(1, user1)` → (true, amount)
- After redeeming: `canRedeemWinnings(1, user1)` → (false, 0)

**I07** `test_I07_DoubleRedeemReverts`
- Redeem once (success), redeem again → revert or 0 return

**I08** `test_I08_RedeemLosingOutcomeReverts`
- Event settled with outcome 0 as winner
- User has only outcome 1 Long tokens → redeemWinnings returns 0 or reverts

**I09** `test_I09_MultipleUsersRedeemWinnings`
- user1 mints 60e18 complete set, user2 mints 40e18 complete set
- Event settles, outcome 0 wins
- user1 redeems 60e18, user2 redeems 40e18
- Assert prize pool → 0 after both redeem

**I10** `test_I10_GetEventPrizePool`
- Register, mint 80e18 complete set
- Assert: `getEventPrizePool(1) == 80e18`
- Burn 20e18, assert prize pool == 60e18
- Settle + redeem, assert prize pool decreases

---

## Group J: Fee Integration (5 tests)

**J01** `test_J01_CollectProtocolFeeBasicFlow`
- Deposit 100e18 for user1
- Prank feeVaultManager: `fundingManager.collectProtocolFee(user1, 10e18)`
- Assert: `getUserUsdBalance(user1) == 90e18`

**J02** `test_J02_CollectProtocolFeeNonFeeVaultManagerReverts`
- user1 calls `collectProtocolFee` directly → revert

**J03** `test_J03_WithdrawLiquidityBasicFlow`
- Deposit 100e18 (tokenLiquidity = 100e18)
- Prank feeVaultManager: `fundingManager.withdrawLiquidity(mockToken18, 30e18, owner)`
- Assert: `getTokenLiquidity(mockToken18) == 70e18`
- Assert: owner received 30e18 tokens

**J04** `test_J04_WithdrawLiquidityInsufficientReverts`
- tokenLiquidity = 100e18
- Try withdraw 150e18 → revert (`InsufficientTokenLiquidity`)

**J05** `test_J05_WithdrawLiquidityNonFeeVaultManagerReverts`
- Direct call to `withdrawLiquidity` → revert

---

## Group K: Pause & Admin (5 tests)

**K01** `test_K01_PauseBlocksDeposit`
- Owner pauses
- User tries depositErc20 → revert (`EnforcedPause`)

**K02** `test_K02_PauseBlocksWithdraw`
- Deposit, pause, try withdrawDirect → revert

**K03** `test_K03_PauseBlocksMintBurn`
- Deposit + register event, pause
- mintCompleteSetDirect → revert
- burnCompleteSetDirect → revert

**K04** `test_K04_UnpauseRestoresOperations`
- Deposit, pause, unpause, deposit again → success

**K05** `test_K05_OrderOpsWorkWhenPaused`
- lockForOrder / unlockForOrder / settleMatchedOrder / markEventSettled have NO `whenNotPaused`
- Deposit + lock for order, then pause, then unlock → should still work
- (Verifies these are only gated by onlyOrderBookManager, not pause)

---

## Total: 80 tests across 11 groups (A–K)

---

## Implementation Notes

1. **Concrete type needed for**:
   - `fm.totalDeposited(token)` — not on IFundingManager
   - `fm.totalWithdrawn(token)` — not on IFundingManager
   - `fm.userUsdBalances(user)` — use `fundingManager.getUserUsdBalance(user)` instead (available on interface)
   - `fm.longPositions(user, eventId, outcomeIndex)` — use `fundingManager.getLongPosition(...)` instead
   - `fm.eventPrizePool(eventId)` — use `fundingManager.getEventPrizePool(...)` instead
   - `fm.eventSettled(eventId)` — use `fundingManager.isEventSettled(...)` instead
   - `fm.tokenLiquidity(token)` — use `fundingManager.getTokenLiquidity(...)` instead

2. **Ordering of setters**: OrderBookManager address is set once in Deploy script; cannot re-set

3. **SettleMatchedOrder**: Locked USD for buy order is the full matchAmount (not price-adjusted) — the payment to seller is `matchAmount * matchPrice / FEE_PRECISION`. The remaining locked USD difference (if any) may need further clarification by reading the implementation.

4. **vm.snapshot() deprecation**: Use `vm.snapshot()` / `vm.revertTo()` for now (cosmetic warnings only)

5. **ERC20 approve**: Always approve FundingManager before calling depositErc20

6. **Group H**: Check `FundingManager.sol` `settleMatchedOrder` carefully for exact balance accounting — the locked USD for a buy order is `matchAmount` (full amount), but the payment is price-scaled. The difference is returned to the buyer's USD balance.

---

## Review

**All 80 tests pass** (`forge test --match-path test/unit/FundingManager.t.sol`).

### Implementation Notes / Fixes

1. **`vm.expectEmit` placement**: Must be placed immediately before the emitting call, not before a helper that wraps multiple operations. `_deposit18()` calls `mint()` first (emits `Transfer`), which Foundry matched against the expected `DepositToken` event, causing a mismatch. Fixed `test_B01` by inlining the deposit steps so `vm.expectEmit` appears right before `depositErc20`.

2. **Concrete type cast**: `FundingManager(payable(address(deployer.fundingManager())))` required because `FundingManager` has `receive() external payable`. Used `fm` (concrete) for `totalDeposited`/`totalWithdrawn` state variables not exposed on interface; all other queries use `fundingManager` (interface).

3. **Calculation verification**:
   - `normalizeToUsd(18-dec token, amount)` = `amount` (identity at $1 oracle price)
   - `denormalizeFromUsd(18-dec token, usd)` = `usd` (identity)
   - `normalizeToUsd(6-dec token, amount)` = `amount * 1e12`
   - `settleMatchedOrder`: `payment = matchAmount * matchPrice / 10000`; buyer's locked USD decreases by `payment`, seller's USD increases by `payment`
   - `lockForOrder(buy, amount)`: locks exactly `amount` USD from `userUsdBalances`
   - `mintCompleteSetDirect(eventId, usd)`: decreases `userUsdBalances` by `usd`, adds `usd` Long tokens to each outcome

4. **`_deposit18` helper**: Mints `amount + 6e18` so wallet retains ≥6e18 > 5e18 `minTokenBalanceUsd` after deposit.

5. **`_setupUserWithLongTokens` helper**: Deposits `usdAmount + 6e18` (extra buffer for the helper's own deposit), registers event, then mints complete set.

### Coverage Summary

| Group | Feature | Tests |
|-------|---------|-------|
| A | Token Configuration | 7 |
| B | Deposit ERC20 | 8 |
| C | Withdrawal | 8 |
| D | Normalization & Pricing | 6 |
| E | Balance & Liquidity Queries | 5 |
| F | Complete Set Mint/Burn | 8 |
| G | Order Locking/Unlocking | 8 |
| H | Order Settlement | 10 |
| I | Event Settlement & Redemption | 10 |
| J | Fee Integration | 5 |
| K | Pause & Admin | 5 |
| **Total** | | **80** |
