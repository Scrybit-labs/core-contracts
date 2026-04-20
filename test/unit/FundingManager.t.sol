// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {FundingManager} from "../../src/core/FundingManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ---------------------------------------------------------------------------
// Helper mock tokens
// ---------------------------------------------------------------------------

contract MockToken is ERC20 {
    uint8 private _dec;

    constructor(string memory name, string memory symbol, uint8 dec) ERC20(name, symbol) {
        _dec = dec;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ---------------------------------------------------------------------------
// Test contract
// ---------------------------------------------------------------------------

contract FundingManagerTest is Test {
    // ---- contracts ----
    Deploy public deployer;
    IFundingManager public fundingManager;
    FundingManager public fm; // concrete type for public state variable access
    IOrderBookManager public orderBookManager;
    IFeeVaultManager public feeVaultManager;

    // ---- tokens ----
    MockToken public mockToken18; // 18-decimal token — $1 oracle → normalizeToUsd = identity
    MockToken public mockToken6; // 6-decimal token  — $1 oracle → normalizeToUsd(amount) = amount * 1e12

    // ---- actors ----
    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // ---- snapshot ----
    uint256 public baseSnapshot;

    // ====================================================================
    // setUp
    // ====================================================================

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

    // ====================================================================
    // Helpers
    // ====================================================================

    /// @dev Mint amount + 6e18 to user so they keep ≥5e18 USD after deposit
    function _deposit18(address user, uint256 amount) internal {
        mockToken18.mint(user, amount + 6e18);
        vm.startPrank(user);
        IERC20(address(mockToken18)).approve(address(fundingManager), amount);
        fundingManager.depositErc20(IERC20(address(mockToken18)), amount);
        vm.stopPrank();
    }

    /// @dev For 6-decimal token: mint amount6 + 6e6 (=$6) to satisfy minTokenBalanceUsd
    function _deposit6(address user, uint256 amount6) internal {
        mockToken6.mint(user, amount6 + 6e6);
        vm.startPrank(user);
        IERC20(address(mockToken6)).approve(address(fundingManager), amount6);
        fundingManager.depositErc20(IERC20(address(mockToken6)), amount6);
        vm.stopPrank();
    }

    /// @dev Prank as orderBookManager to registerEvent
    function _registerEvent(uint256 eventId, uint8 outcomeCount) internal {
        vm.prank(address(orderBookManager));
        fundingManager.registerEvent(eventId, outcomeCount);
    }

    /// @dev Prank as orderBookManager to lockForOrder
    function _lockForOrder(
        address user,
        uint256 orderId,
        bool isBuy,
        uint256 amount,
        uint256 eventId,
        uint8 outcomeIndex
    ) internal {
        vm.prank(address(orderBookManager));
        fundingManager.lockForOrder(user, orderId, isBuy, amount, eventId, outcomeIndex);
    }

    /// @dev Prank as orderBookManager to unlockForOrder
    function _unlockForOrder(address user, uint256 orderId, bool isBuy, uint256 eventId, uint8 outcomeIndex)
        internal
    {
        vm.prank(address(orderBookManager));
        fundingManager.unlockForOrder(user, orderId, isBuy, eventId, outcomeIndex);
    }

    /// @dev Prank as orderBookManager to settleMatchedOrder
    function _settleMatchedOrder(
        uint256 buyId,
        uint256 sellId,
        address buyer,
        address seller,
        uint256 matchAmount,
        uint256 matchPrice,
        uint256 eventId,
        uint8 outcomeIndex
    ) internal {
        vm.prank(address(orderBookManager));
        fundingManager.settleMatchedOrder(buyId, sellId, buyer, seller, matchAmount, matchPrice, eventId, outcomeIndex);
    }

    /// @dev Prank as orderBookManager to markEventSettled
    function _markEventSettled(uint256 eventId, uint8 winningOutcome) internal {
        vm.prank(address(orderBookManager));
        fundingManager.markEventSettled(eventId, winningOutcome);
    }

    /// @dev Full setup: deposit + register event + mint complete set → user gets Long tokens for all outcomes
    function _setupUserWithLongTokens(address user, uint256 eventId, uint8 outcomeCount, uint256 usdAmount) internal {
        _deposit18(user, usdAmount + 6e18);
        _registerEvent(eventId, outcomeCount);
        vm.prank(user);
        fundingManager.mintCompleteSetDirect(eventId, usdAmount);
    }

    // ====================================================================
    // Group A: Token Configuration
    // ====================================================================

    function test_A01_ConfigureNewToken() public {
        vm.revertTo(baseSnapshot);
        MockToken newToken = new MockToken("New Token", "NEW", 18);

        vm.expectEmit(true, false, false, true);
        emit IFundingManager.TokenConfigured(address(newToken), 18, true, block.chainid);

        vm.prank(owner);
        fundingManager.configureToken(address(newToken), 18, true);

        address[] memory supported = fundingManager.getSupportedTokens();
        bool found = false;
        for (uint256 i = 0; i < supported.length; i++) {
            if (supported[i] == address(newToken)) found = true;
        }
        assertTrue(found, "new token should be in supported list");
    }

    function test_A02_ReconfigureTokenEnabled() public {
        vm.revertTo(baseSnapshot);
        // Disable mockToken18
        vm.prank(owner);
        fundingManager.configureToken(address(mockToken18), 18, false);

        // Attempt deposit should revert
        mockToken18.mint(user1, 106e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 100e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 100e18);
        vm.stopPrank();
    }

    function test_A03_ConfigureSixDecimalToken() public {
        vm.revertTo(baseSnapshot);
        // 1e6 of 6-dec token at $1 oracle → should equal 1e18 USD
        uint256 normalised = fundingManager.normalizeToUsd(address(mockToken6), 1e6);
        assertEq(normalised, 1e18, "1e6 of 6-dec token should normalise to 1e18 USD");
    }

    function test_A04_ConfigureTokenNonOwnerReverts() public {
        vm.revertTo(baseSnapshot);
        MockToken newToken = new MockToken("T", "T", 18);
        vm.prank(user1);
        vm.expectRevert();
        fundingManager.configureToken(address(newToken), 18, true);
    }

    function test_A05_DisableTokenBlocksDeposit() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.configureToken(address(mockToken18), 18, false);

        mockToken18.mint(user1, 106e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 100e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 100e18);
        vm.stopPrank();
    }

    function test_A06_SetMinDepositPerTxnUsd() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.setMinDepositPerTxnUsd(2e18);

        assertEq(fundingManager.getMinDepositPerTxnUsd(), 2e18);

        // Deposit of 1e18 (below new min of 2e18) should revert
        mockToken18.mint(user1, 107e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 1e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 1e18);
        vm.stopPrank();
    }

    function test_A07_SetMinTokenBalanceUsd() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.setMinTokenBalanceUsd(10e18);

        assertEq(fundingManager.getMinTokenBalanceUsd(), 10e18);

        // Mint only enough that 9e18 remains after deposit → should revert (< 10e18 min)
        mockToken18.mint(user1, 110e18); // 110e18 total; deposit 101e18 leaves 9e18 → revert
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 101e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 101e18);
        vm.stopPrank();
    }

    // ====================================================================
    // Group B: Deposit ERC20
    // ====================================================================

    function test_B01_DepositErc20BasicFlow() public {
        vm.revertTo(baseSnapshot);

        mockToken18.mint(user1, 106e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 100e18);

        vm.expectEmit(true, true, false, true);
        emit IFundingManager.DepositToken(address(mockToken18), user1, 100e18);

        fundingManager.depositErc20(IERC20(address(mockToken18)), 100e18);
        vm.stopPrank();

        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 100e18);
        assertEq(IERC20(address(mockToken18)).balanceOf(address(fundingManager)), 100e18);
    }

    function test_B02_DepositErc20AccumulatesBalance() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 50e18);
        _deposit18(user1, 50e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 100e18);
    }

    function test_B03_DepositErc20MultipleUsers() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 200e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getUserUsdBalance(user2), 200e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 300e18);
    }

    function test_B04_DepositBelowMinPerTxnReverts() public {
        vm.revertTo(baseSnapshot);
        // Default min is 1e18. Try to deposit 0.5e18
        mockToken18.mint(user1, 10e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 5e17);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 5e17);
        vm.stopPrank();
    }

    function test_B05_DepositLeavingWalletBelowMinReverts() public {
        vm.revertTo(baseSnapshot);
        // Mint 105e18; deposit 104e18 would leave 1e18 < 5e18 threshold
        mockToken18.mint(user1, 105e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 104e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 104e18);
        vm.stopPrank();
    }

    function test_B06_DepositSixDecimalToken() public {
        vm.revertTo(baseSnapshot);
        _deposit6(user1, 100e6);

        // 100e6 of 6-dec token at $1 normalises to 100e18 USD
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken6)), 100e6);
    }

    function test_B07_DepositErc20WhenPausedReverts() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.pause();

        mockToken18.mint(user1, 106e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 100e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 100e18);
        vm.stopPrank();
    }

    function test_B08_DepositUpdatesTotalDeposited() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        // totalDeposited is on concrete type
        assertEq(fm.totalDeposited(address(mockToken18)), 100e18);
    }

    // ====================================================================
    // Group C: Withdrawal
    // ====================================================================

    function test_C01_WithdrawDirectBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        uint256 balanceBefore = IERC20(address(mockToken18)).balanceOf(user1);

        vm.expectEmit(true, true, false, false);
        emit IFundingManager.WithdrawToken(address(mockToken18), user1, user1, 60e18);

        vm.prank(user1);
        fundingManager.withdrawDirect(address(mockToken18), 60e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 40e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 40e18);
        assertEq(IERC20(address(mockToken18)).balanceOf(user1), balanceBefore + 60e18);
    }

    function test_C02_WithdrawTokenAmountBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        uint256 balanceBefore = IERC20(address(mockToken18)).balanceOf(user1);

        vm.prank(user1);
        fundingManager.withdrawTokenAmount(address(mockToken18), 60e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 40e18);
        assertEq(IERC20(address(mockToken18)).balanceOf(user1), balanceBefore + 60e18);
    }

    function test_C03_WithdrawFullBalance() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(user1);
        fundingManager.withdrawDirect(address(mockToken18), 100e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 0);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 0);
    }

    function test_C04_WithdrawMoreThanBalanceReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 50e18);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.withdrawDirect(address(mockToken18), 100e18);
    }

    function test_C05_WithdrawSixDecimalToken() public {
        vm.revertTo(baseSnapshot);
        _deposit6(user1, 100e6); // deposits 100e6 → 100e18 USD
        uint256 balanceBefore = IERC20(address(mockToken6)).balanceOf(user1);

        vm.prank(user1);
        fundingManager.withdrawDirect(address(mockToken6), 50e18); // withdraw 50 USD

        // 50 USD of 6-dec token at $1 → 50e6 tokens
        assertEq(IERC20(address(mockToken6)).balanceOf(user1), balanceBefore + 50e6);
        assertEq(fundingManager.getUserUsdBalance(user1), 50e18);
    }

    function test_C06_WithdrawWhenPausedReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(owner);
        fundingManager.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.withdrawDirect(address(mockToken18), 50e18);
    }

    function test_C07_WithdrawUpdatesTotalWithdrawn() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(user1);
        fundingManager.withdrawDirect(address(mockToken18), 60e18);

        assertEq(fm.totalWithdrawn(address(mockToken18)), 60e18);
    }

    function test_C08_CanWithdrawView() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        assertTrue(fundingManager.canWithdraw(address(mockToken18), 60e18));
        assertFalse(fundingManager.canWithdraw(address(mockToken18), 150e18));
    }

    // ====================================================================
    // Group D: Normalization & Pricing
    // ====================================================================

    function test_D01_NormalizeToUsd18DecimalToken() public {
        vm.revertTo(baseSnapshot);
        assertEq(fundingManager.normalizeToUsd(address(mockToken18), 100e18), 100e18);
        assertEq(fundingManager.normalizeToUsd(address(mockToken18), 1e18), 1e18);
        assertEq(fundingManager.normalizeToUsd(address(mockToken18), 0), 0);
    }

    function test_D02_NormalizeToUsd6DecimalToken() public {
        vm.revertTo(baseSnapshot);
        assertEq(fundingManager.normalizeToUsd(address(mockToken6), 1e6), 1e18);
        assertEq(fundingManager.normalizeToUsd(address(mockToken6), 100e6), 100e18);
    }

    function test_D03_DenormalizeFromUsd18DecimalToken() public {
        vm.revertTo(baseSnapshot);
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken18), 100e18), 100e18);
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken18), 0), 0);
    }

    function test_D04_DenormalizeFromUsd6DecimalToken() public {
        vm.revertTo(baseSnapshot);
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken6), 1e18), 1e6);
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken6), 100e18), 100e6);
    }

    function test_D05_NormalizeDenormalizeRoundTrip() public {
        vm.revertTo(baseSnapshot);
        // 18-dec token: round trip should be identity
        uint256 raw18 = 77e18;
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken18), fundingManager.normalizeToUsd(address(mockToken18), raw18)), raw18);

        // 6-dec token: round trip should be identity
        uint256 raw6 = 77e6;
        assertEq(fundingManager.denormalizeFromUsd(address(mockToken6), fundingManager.normalizeToUsd(address(mockToken6), raw6)), raw6);
    }

    function test_D06_GetTokenPrice() public {
        vm.revertTo(baseSnapshot);
        // MockOracleAdapter returns 1e18 for all tokens
        assertEq(fundingManager.getTokenPrice(address(mockToken18)), 1e18);
        assertEq(fundingManager.getTokenPrice(address(mockToken6)), 1e18);
    }

    // ====================================================================
    // Group E: Balance & Liquidity Queries
    // ====================================================================

    function test_E01_GetUserUsdBalanceAfterDeposit() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
    }

    function test_E02_GetTokenLiquidityAfterDeposit() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 100e18);
    }

    function test_E03_GetAllTokenBalancesEmpty() public {
        vm.revertTo(baseSnapshot);
        // user3 has never deposited
        assertEq(fundingManager.getUserUsdBalance(user3), 0);
    }

    function test_E04_GetSupportedTokens() public {
        vm.revertTo(baseSnapshot);
        address[] memory supported = fundingManager.getSupportedTokens();
        bool found18 = false;
        bool found6 = false;
        for (uint256 i = 0; i < supported.length; i++) {
            if (supported[i] == address(mockToken18)) found18 = true;
            if (supported[i] == address(mockToken6)) found6 = true;
        }
        assertTrue(found18, "mockToken18 should be in supported list");
        assertTrue(found6, "mockToken6 should be in supported list");
    }

    function test_E05_MultiTokenLiquidity() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit6(user2, 100e6);

        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 100e18);
        assertEq(fundingManager.getTokenLiquidity(address(mockToken6)), 100e6);
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getUserUsdBalance(user2), 100e18);
    }

    // ====================================================================
    // Group F: Complete Set Mint / Burn
    // ====================================================================

    function test_F01_MintCompleteSetBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.expectEmit(true, true, false, true);
        emit IFundingManager.CompleteSetMinted(user1, 1, 50e18);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 50e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 50e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 50e18);
        assertEq(fundingManager.getEventPrizePool(1), 50e18);
    }

    function test_F02_MintCompleteSetThreeOutcomes() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 3);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 90e18);

        assertEq(fundingManager.getLongPosition(user1, 1, 0), 90e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 90e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 2), 90e18);
        assertEq(fundingManager.getEventPrizePool(1), 90e18);
    }

    function test_F03_MintCompleteSetInsufficientBalanceReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 30e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.mintCompleteSetDirect(1, 50e18);
    }

    function test_F04_BurnCompleteSetBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);
        // user now has 40e18 USD balance + 60e18 Long[0] + 60e18 Long[1]

        vm.expectEmit(true, true, false, true);
        emit IFundingManager.CompleteSetBurned(user1, 1, 30e18);

        vm.prank(user1);
        fundingManager.burnCompleteSetDirect(1, 30e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 70e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 30e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 30e18);
        assertEq(fundingManager.getEventPrizePool(1), 30e18);
    }

    function test_F05_BurnCompleteSetInsufficientLongTokensReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.burnCompleteSetDirect(1, 80e18);
    }

    function test_F06_MintBurnRoundTrip() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);

        vm.prank(user1);
        fundingManager.burnCompleteSetDirect(1, 60e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 0);
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 0);
        assertEq(fundingManager.getEventPrizePool(1), 0);
    }

    function test_F07_MintCompleteSetWhenPausedReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(owner);
        fundingManager.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.mintCompleteSetDirect(1, 50e18);
    }

    function test_F08_MintCompleteSetUpdatesLiquidityAndPrizePool() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 40e18);

        // tokenLiquidity unchanged (no external token movement)
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 100e18);
        assertEq(fundingManager.getEventPrizePool(1), 40e18);
        assertEq(fundingManager.getUserUsdBalance(user1), 60e18);
    }

    // ====================================================================
    // Group G: Order Locking / Unlocking
    // ====================================================================

    function test_G01_LockForBuyOrderBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.expectEmit(true, false, false, true);
        emit IFundingManager.FundsLocked(user1, 40e18, 1, 0);

        _lockForOrder(user1, 101, true, 40e18, 1, 0);

        assertEq(fundingManager.getOrderLockedUsd(101), 40e18);
        assertEq(fundingManager.getUserUsdBalance(user1), 60e18);
    }

    function test_G02_LockForSellOrderBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 50e18); // user1 now has 50e18 Long[0]

        _lockForOrder(user1, 102, false, 20e18, 1, 0);

        assertEq(fundingManager.getOrderLockedLong(102), 20e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 30e18);
    }

    function test_G03_UnlockForBuyOrderBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);
        _lockForOrder(user1, 101, true, 40e18, 1, 0);

        vm.expectEmit(true, false, false, true);
        emit IFundingManager.FundsUnlocked(user1, 40e18, 1, 0);

        _unlockForOrder(user1, 101, true, 1, 0);

        assertEq(fundingManager.getOrderLockedUsd(101), 0);
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
    }

    function test_G04_UnlockForSellOrderBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        _lockForOrder(user1, 102, false, 20e18, 1, 0);
        _unlockForOrder(user1, 102, false, 1, 0);

        assertEq(fundingManager.getOrderLockedLong(102), 0);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 50e18);
    }

    function test_G05_LockBuyOrderInsufficientBalanceReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 30e18);
        _registerEvent(1, 2);

        vm.prank(address(orderBookManager));
        vm.expectRevert();
        fundingManager.lockForOrder(user1, 101, true, 50e18, 1, 0);
    }

    function test_G06_LockSellOrderInsufficientLongTokensReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);
        // user1 has 0 Long tokens — lock should revert

        vm.prank(address(orderBookManager));
        vm.expectRevert();
        fundingManager.lockForOrder(user1, 102, false, 20e18, 1, 0);
    }

    function test_G07_LockOrderNonOrderBookManagerReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.lockForOrder(user1, 101, true, 40e18, 1, 0);
    }

    function test_G08_MultipleOrderLocksForSameUser() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        _lockForOrder(user1, 101, true, 30e18, 1, 0);
        _lockForOrder(user1, 102, true, 40e18, 1, 0);

        assertEq(fundingManager.getUserUsdBalance(user1), 30e18);
        assertEq(fundingManager.getOrderLockedUsd(101), 30e18);
        assertEq(fundingManager.getOrderLockedUsd(102), 40e18);
    }

    // ====================================================================
    // Group H: Order Settlement
    // ====================================================================

    function test_H01_SettleMatchedOrderBasicFlow() public {
        vm.revertTo(baseSnapshot);
        // buyer deposits, seller gets Long tokens via mintCompleteSet
        _deposit18(user1, 100e18); // buyer
        _deposit18(user2, 100e18); // seller
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18); // seller has 50e18 Long[0] + Long[1]

        // matchAmount=10e18, matchPrice=5000 → payment = 10e18*5000/10000 = 5e18 USD
        _lockForOrder(user1, 101, true, 5e18, 1, 0);   // buyer locks 5e18 USD
        _lockForOrder(user2, 102, false, 10e18, 1, 0);  // seller locks 10e18 Long[0]

        vm.expectEmit(true, true, false, true);
        emit IFundingManager.OrderSettled(101, 102, 10e18);

        _settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 0);

        // buyer got 10e18 Long[0]
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 10e18);
        // seller received 5e18 USD (on top of 50e18 remaining from deposit)
        assertEq(fundingManager.getUserUsdBalance(user2), 50e18 + 5e18);
        // locked amounts consumed
        assertEq(fundingManager.getOrderLockedUsd(101), 0);
        assertEq(fundingManager.getOrderLockedLong(102), 0);
    }

    function test_H02_SettleMatchedOrderFullPrice() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        // matchPrice=10000 → payment = 10e18 USD (full 1:1)
        _lockForOrder(user1, 101, true, 10e18, 1, 0);
        _lockForOrder(user2, 102, false, 10e18, 1, 0);

        _settleMatchedOrder(101, 102, user1, user2, 10e18, 10000, 1, 0);

        assertEq(fundingManager.getLongPosition(user1, 1, 0), 10e18);
        assertEq(fundingManager.getOrderLockedUsd(101), 0); // fully consumed
        assertEq(fundingManager.getUserUsdBalance(user2), 50e18 + 10e18);
    }

    function test_H03_SettleMatchedOrderMinimalPrice() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        // matchAmount=10e18, matchPrice=1 → payment = 10e18*1/10000 = 0.001e18
        uint256 payment = 10e18 * 1 / 10000;
        _lockForOrder(user1, 101, true, payment, 1, 0);
        _lockForOrder(user2, 102, false, 10e18, 1, 0);

        _settleMatchedOrder(101, 102, user1, user2, 10e18, 1, 1, 0);

        assertEq(fundingManager.getLongPosition(user1, 1, 0), 10e18);
        assertEq(fundingManager.getUserUsdBalance(user2), 50e18 + payment);
    }

    function test_H04_SettleMatchedOrderNonOrderBookManagerReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 0);
    }

    function test_H05_SettleMatchedOrderUpdatesLiquidityCorrectly() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        uint256 liquidityBefore = fundingManager.getTokenLiquidity(address(mockToken18));

        _lockForOrder(user1, 101, true, 5e18, 1, 0);
        _lockForOrder(user2, 102, false, 10e18, 1, 0);
        _settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 0);

        // tokenLiquidity unchanged — just USD redistributed between buyers/sellers
        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), liquidityBefore);
    }

    function test_H06_MultipleSettlementsAccumulate() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        // First settlement: 5e18 Long at price 5000 → payment = 2.5e18
        _lockForOrder(user1, 101, true, 2.5e18, 1, 0);
        _lockForOrder(user2, 102, false, 5e18, 1, 0);
        _settleMatchedOrder(101, 102, user1, user2, 5e18, 5000, 1, 0);

        // Second settlement: 5e18 Long at price 5000 → payment = 2.5e18
        _lockForOrder(user1, 103, true, 2.5e18, 1, 0);
        _lockForOrder(user2, 104, false, 5e18, 1, 0);
        _settleMatchedOrder(103, 104, user1, user2, 5e18, 5000, 1, 0);

        assertEq(fundingManager.getLongPosition(user1, 1, 0), 10e18);
    }

    function test_H07_SettleMatchedOrderBuyerGetsLongForCorrectOutcome() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 3); // 3 outcomes

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        uint256 payment = 10e18 * 5000 / 10000;
        _lockForOrder(user1, 101, true, payment, 1, 1);   // buying outcome index 1
        _lockForOrder(user2, 102, false, 10e18, 1, 1);    // selling outcome index 1

        _settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 1);

        assertEq(fundingManager.getLongPosition(user1, 1, 0), 0, "outcome 0 unchanged");
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 10e18, "outcome 1 increased");
        assertEq(fundingManager.getLongPosition(user1, 1, 2), 0, "outcome 2 unchanged");
    }

    function test_H08_SettlementPriceCalculationVerification() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        // matchAmount=100e18, matchPrice=3000 → payment = 100e18*3000/10000 = 30e18
        uint256 payment = 100e18 * 3000 / 10000;
        _lockForOrder(user1, 101, true, payment, 1, 0);
        _lockForOrder(user2, 102, false, 50e18, 1, 0);

        uint256 sellerBalanceBefore = fundingManager.getUserUsdBalance(user2);
        _settleMatchedOrder(101, 102, user1, user2, 100e18 / 2, 3000, 1, 0); // 50e18 Long

        // payment for 50e18 at price 3000 = 50e18*3000/10000 = 15e18
        uint256 expectedPayment = 50e18 * 3000 / 10000;
        assertEq(fundingManager.getUserUsdBalance(user2), sellerBalanceBefore + expectedPayment);
    }

    function test_H09_PartialFillThenCancel() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        // Lock 10e18 USD for buy order (enough for 20e18 at price 5000)
        _lockForOrder(user1, 101, true, 10e18, 1, 0);
        _lockForOrder(user2, 102, false, 20e18, 1, 0);

        // Partially fill: settle 10e18 Long → payment = 10e18*5000/10000 = 5e18
        _settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 0);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 10e18);
        assertEq(fundingManager.getOrderLockedUsd(101), 5e18); // 5e18 remaining locked

        // Cancel remaining: unlock remaining Long tokens
        _unlockForOrder(user2, 102, false, 1, 0);
        assertEq(fundingManager.getOrderLockedLong(102), 0);
        assertEq(fundingManager.getLongPosition(user2, 1, 0), 40e18); // remaining unlocked
    }

    function test_H10_GetOrderLockedAfterFullSettlement() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 50e18);

        uint256 payment = 10e18 * 5000 / 10000;
        _lockForOrder(user1, 101, true, payment, 1, 0);
        _lockForOrder(user2, 102, false, 10e18, 1, 0);
        _settleMatchedOrder(101, 102, user1, user2, 10e18, 5000, 1, 0);

        assertEq(fundingManager.getOrderLockedUsd(101), 0);
        assertEq(fundingManager.getOrderLockedLong(102), 0);
    }

    // ====================================================================
    // Group I: Event Settlement & Winnings Redemption
    // ====================================================================

    function test_I01_RegisterEventBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _registerEvent(1, 2);
        assertFalse(fundingManager.isEventSettled(1));
    }

    function test_I02_MarkEventSettledBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _registerEvent(1, 2);

        vm.expectEmit(true, false, false, true);
        emit IFundingManager.EventMarkedSettled(1, 0, 0);

        _markEventSettled(1, 0);
        assertTrue(fundingManager.isEventSettled(1));
    }

    function test_I03_MarkEventSettledNonOrderBookManagerReverts() public {
        vm.revertTo(baseSnapshot);
        _registerEvent(1, 2);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.markEventSettled(1, 0);
    }

    function test_I04_RedeemWinningsBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);
        // user1: 40e18 USD + 60e18 Long[0] + 60e18 Long[1]

        _markEventSettled(1, 0); // outcome 0 wins

        vm.expectEmit(true, true, false, true);
        emit IFundingManager.WinningsRedeemed(user1, 1, 0, 60e18);

        vm.prank(user1);
        fundingManager.redeemWinnings(1);

        assertEq(fundingManager.getUserUsdBalance(user1), 40e18 + 60e18);
        assertEq(fundingManager.getLongPosition(user1, 1, 0), 0);
        assertEq(fundingManager.getLongPosition(user1, 1, 1), 60e18); // losing tokens remain
    }

    function test_I05_RedeemWinningsNoPositionReverts() public {
        vm.revertTo(baseSnapshot);
        _registerEvent(1, 2);
        _markEventSettled(1, 0);

        // user1 has no winning position
        vm.prank(user1);
        vm.expectRevert();
        fundingManager.redeemWinnings(1);
    }

    function test_I06_CanRedeemWinningsView() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);

        // Before settlement
        (bool canRedeem, uint256 amount) = fundingManager.canRedeemWinnings(1, user1);
        assertFalse(canRedeem);
        assertEq(amount, 0);

        _markEventSettled(1, 0);

        // After settlement, before redeem
        (canRedeem, amount) = fundingManager.canRedeemWinnings(1, user1);
        assertTrue(canRedeem);
        assertEq(amount, 60e18);

        // After redeem
        vm.prank(user1);
        fundingManager.redeemWinnings(1);

        (canRedeem, amount) = fundingManager.canRedeemWinnings(1, user1);
        assertFalse(canRedeem);
        assertEq(amount, 0);
    }

    function test_I07_DoubleRedeemReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);

        _markEventSettled(1, 0);

        vm.prank(user1);
        fundingManager.redeemWinnings(1);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.redeemWinnings(1);
    }

    function test_I08_RedeemLosingOutcomeReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);
        // User has Long[0] and Long[1]. Outcome 0 wins → user1 has winner.
        // Now check: can user2 (no position) redeem? No.
        // Check: what about a user who only acquires Long[1] (loser)?

        // Give user2 Long[1] via buy/sell trade — they won't have Long[0]
        _deposit18(user2, 100e18);
        uint256 payment = 10e18 * 5000 / 10000;
        _lockForOrder(user2, 201, true, payment, 1, 1);   // user2 buys outcome 1 Long
        _lockForOrder(user1, 202, false, 10e18, 1, 1);    // user1 sells outcome 1 Long
        _settleMatchedOrder(201, 202, user2, user1, 10e18, 5000, 1, 1);

        // Settle: outcome 0 wins
        _markEventSettled(1, 0);

        // user2 only has Long[1] — losing side → should revert
        vm.prank(user2);
        vm.expectRevert();
        fundingManager.redeemWinnings(1);
    }

    function test_I09_MultipleUsersRedeemWinnings() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _deposit18(user2, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 60e18);

        vm.prank(user2);
        fundingManager.mintCompleteSetDirect(1, 40e18);

        assertEq(fundingManager.getEventPrizePool(1), 100e18);

        _markEventSettled(1, 0);

        vm.prank(user1);
        fundingManager.redeemWinnings(1);

        vm.prank(user2);
        fundingManager.redeemWinnings(1);

        assertEq(fundingManager.getEventPrizePool(1), 0);
    }

    function test_I10_GetEventPrizePool() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(user1);
        fundingManager.mintCompleteSetDirect(1, 80e18);
        assertEq(fundingManager.getEventPrizePool(1), 80e18);

        vm.prank(user1);
        fundingManager.burnCompleteSetDirect(1, 20e18);
        assertEq(fundingManager.getEventPrizePool(1), 60e18);

        _markEventSettled(1, 0);

        vm.prank(user1);
        fundingManager.redeemWinnings(1);
        assertEq(fundingManager.getEventPrizePool(1), 0);
    }

    // ====================================================================
    // Group J: Fee Integration (collectProtocolFee / withdrawLiquidity)
    // ====================================================================

    function test_J01_CollectProtocolFeeBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(address(feeVaultManager));
        fundingManager.collectProtocolFee(user1, 10e18);

        assertEq(fundingManager.getUserUsdBalance(user1), 90e18);
    }

    function test_J02_CollectProtocolFeeNonFeeVaultManagerReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.collectProtocolFee(user1, 10e18);
    }

    function test_J03_WithdrawLiquidityBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        uint256 ownerBalanceBefore = IERC20(address(mockToken18)).balanceOf(owner);

        vm.prank(address(feeVaultManager));
        fundingManager.withdrawLiquidity(address(mockToken18), 30e18, owner);

        assertEq(fundingManager.getTokenLiquidity(address(mockToken18)), 70e18);
        assertEq(IERC20(address(mockToken18)).balanceOf(owner), ownerBalanceBefore + 30e18);
    }

    function test_J04_WithdrawLiquidityInsufficientReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(address(feeVaultManager));
        vm.expectRevert();
        fundingManager.withdrawLiquidity(address(mockToken18), 150e18, owner);
    }

    function test_J05_WithdrawLiquidityNonFeeVaultManagerReverts() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.withdrawLiquidity(address(mockToken18), 30e18, owner);
    }

    // ====================================================================
    // Group K: Pause & Admin
    // ====================================================================

    function test_K01_PauseBlocksDeposit() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.pause();

        mockToken18.mint(user1, 106e18);
        vm.startPrank(user1);
        IERC20(address(mockToken18)).approve(address(fundingManager), 100e18);
        vm.expectRevert();
        fundingManager.depositErc20(IERC20(address(mockToken18)), 100e18);
        vm.stopPrank();
    }

    function test_K02_PauseBlocksWithdraw() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);

        vm.prank(owner);
        fundingManager.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.withdrawDirect(address(mockToken18), 50e18);
    }

    function test_K03_PauseBlocksMintBurn() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);

        vm.prank(owner);
        fundingManager.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.mintCompleteSetDirect(1, 50e18);
    }

    function test_K04_UnpauseRestoresOperations() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        fundingManager.pause();

        vm.prank(owner);
        fundingManager.unpause();

        _deposit18(user1, 100e18);
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
    }

    function test_K05_OrderOpsWorkWhenPaused() public {
        vm.revertTo(baseSnapshot);
        _deposit18(user1, 100e18);
        _registerEvent(1, 2);
        _lockForOrder(user1, 101, true, 40e18, 1, 0);

        // Pause the contract
        vm.prank(owner);
        fundingManager.pause();

        // lockForOrder / unlockForOrder don't have whenNotPaused — should still work
        _unlockForOrder(user1, 101, true, 1, 0);
        assertEq(fundingManager.getOrderLockedUsd(101), 0);
        assertEq(fundingManager.getUserUsdBalance(user1), 100e18);
    }
}
