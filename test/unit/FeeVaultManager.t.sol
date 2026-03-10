// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {FeeVaultManager} from "../../src/core/FeeVaultManager.sol";
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
    // ============ Contracts ============

    Deploy public deployer;
    IFeeVaultManager public feeVaultManager;
    FeeVaultManager public fvm; // concrete type for public state variable access
    IFundingManager public fundingManager;
    IOrderBookManager public orderBookManager;
    MockUSD public mockUSD;

    // ============ Actors ============

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // ============ Snapshot ============

    uint256 public baseSnapshot;

    // ============ Setup ============

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(uint256(keccak256("owner"))));
        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        feeVaultManager = IFeeVaultManager(address(deployer.feeVaultManager()));
        fvm = FeeVaultManager(payable(address(deployer.feeVaultManager())));
        fundingManager = IFundingManager(address(deployer.fundingManager()));
        orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));
        owner = deployer.initialOwner();

        // Deploy MockUSD and register it as a supported token (price oracle returns $1 for any token)
        mockUSD = new MockUSD();
        vm.prank(owner);
        fundingManager.configureToken(address(mockUSD), 18, true);

        baseSnapshot = vm.snapshot();
    }

    // ============ Helpers ============

    /// @dev Mints amount + 6e18 to satisfy FundingManager's minTokenBalanceUsd (5e18) wallet requirement.
    ///      After call: fundingManager.getUserUsdBalance(user) increases by `amount` (1:1 at $1, 18 decimals).
    function _depositForUser(address user, uint256 amount) internal {
        mockUSD.mint(user, amount + 6e18);
        vm.startPrank(user);
        IERC20(address(mockUSD)).approve(address(fundingManager), amount);
        fundingManager.depositErc20(IERC20(address(mockUSD)), amount);
        vm.stopPrank();
    }

    /// @dev Collect a fee by impersonating the OrderBookManager (onlyOrderBookManager).
    function _collectFee(address token, address payer, uint256 amount, uint256 eventId, string memory feeType)
        internal
    {
        vm.prank(address(orderBookManager));
        feeVaultManager.collectFee(token, payer, amount, eventId, feeType);
    }

    /// @dev Deposit for user then collect fee in one step.
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

    // ============================================================
    // Group A — Initialization & Default State
    // ============================================================

    function test_A01_InitializeDefaultFeeRates() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.getFeeRate("placement"), 10, "default placement rate");
        assertEq(feeVaultManager.getFeeRate("execution"), 20, "default execution rate");
    }

    function test_A02_InitializeZeroBalances() public {
        vm.revertTo(baseSnapshot);
        assertEq(fvm.protocolUsdFeeBalance(), 0, "protocolUsdFeeBalance");
        assertEq(feeVaultManager.getProtocolUsdFeeBalance(), 0, "getProtocolUsdFeeBalance");
        assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 0, "getFeeBalance");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 0, "totalFeesCollected");
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 0, "totalFeesWithdrawn");
    }

    function test_A03_InitializeConstants() public {
        vm.revertTo(baseSnapshot);
        assertEq(fvm.FEE_PRECISION(), 10000, "FEE_PRECISION");
        assertEq(fvm.MAX_FEE_RATE(), 1000, "MAX_FEE_RATE");
    }

    function test_A04_InitializeLinkedContracts() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.orderBookManager(), address(orderBookManager), "orderBookManager link");
        assertEq(feeVaultManager.fundingManager(), address(fundingManager), "fundingManager link");
    }

    function test_A05_InitializeOwner() public {
        vm.revertTo(baseSnapshot);
        // OwnableUpgradeable exposes owner() — call via low-level to avoid interface cast
        (bool ok, bytes memory data) = address(feeVaultManager).staticcall(abi.encodeWithSignature("owner()"));
        assertTrue(ok, "owner() call failed");
        address actualOwner = abi.decode(data, (address));
        assertEq(actualOwner, deployer.initialOwner(), "owner");
    }

    // ============================================================
    // Group B — Fee Rate Management
    // ============================================================

    function test_B01_SetFeeRateUpdatesRate() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        feeVaultManager.setFeeRate("placement", 50);
        assertEq(feeVaultManager.getFeeRate("placement"), 50);
    }

    function test_B02_SetFeeRateEmitsEvent() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        // feeType is string indexed — checked as keccak256 topic
        vm.expectEmit(true, false, false, true);
        emit IFeeVaultManager.FeeRateUpdated("placement", 10, 50);
        feeVaultManager.setFeeRate("placement", 50);
    }

    function test_B03_SetFeeRateToZero() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        feeVaultManager.setFeeRate("placement", 0);
        assertEq(feeVaultManager.getFeeRate("placement"), 0);
    }

    function test_B04_SetFeeRateToMaximum() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        feeVaultManager.setFeeRate("custom", 1000);
        assertEq(feeVaultManager.getFeeRate("custom"), 1000);
    }

    function test_B05_SetFeeRateAboveMaxReverts() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidFeeRate.selector, 1001));
        feeVaultManager.setFeeRate("custom", 1001);
    }

    function test_B06_SetNewFeeType() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.getFeeRate("settlement"), 0, "not yet set");
        vm.prank(owner);
        feeVaultManager.setFeeRate("settlement", 5);
        assertEq(feeVaultManager.getFeeRate("settlement"), 5);
    }

    function test_B07_GetFeeRateUnknownType() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.getFeeRate("nonexistent"), 0);
    }

    function test_B08_CalculateFeeWithPlacement() public {
        vm.revertTo(baseSnapshot);
        // rate = 10; 1000e18 * 10 / 10000 = 1e18
        assertEq(feeVaultManager.calculateFee(1000e18, "placement"), 1e18);
    }

    function test_B09_CalculateFeeWithExecution() public {
        vm.revertTo(baseSnapshot);
        // rate = 20; 1000e18 * 20 / 10000 = 2e18
        assertEq(feeVaultManager.calculateFee(1000e18, "execution"), 2e18);
    }

    function test_B10_CalculateFeeWithZeroRate() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.calculateFee(1000e18, "nonexistent"), 0);
    }

    function test_B11_CalculateFeeWithZeroAmount() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.calculateFee(0, "placement"), 0);
    }

    function test_B12_CalculateFeeAfterRateChange() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.calculateFee(1000e18, "placement"), 1e18);
        vm.prank(owner);
        feeVaultManager.setFeeRate("placement", 100);
        // 1000e18 * 100 / 10000 = 10e18
        assertEq(feeVaultManager.calculateFee(1000e18, "placement"), 10e18);
    }

    function test_B13_SetFeeRateMultipleTypes() public {
        vm.revertTo(baseSnapshot);
        vm.startPrank(owner);
        feeVaultManager.setFeeRate("placement", 15);
        feeVaultManager.setFeeRate("execution", 25);
        feeVaultManager.setFeeRate("settlement", 30);
        vm.stopPrank();
        assertEq(feeVaultManager.getFeeRate("placement"), 15);
        assertEq(feeVaultManager.getFeeRate("execution"), 25);
        assertEq(feeVaultManager.getFeeRate("settlement"), 30);
    }

    // ============================================================
    // Group C — Fee Collection Interaction Cycle
    // ============================================================

    function test_C01_CollectFeeBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 1e18);
    }

    function test_C02_CollectFeeUpdatesAllCounters() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 2e18, 42, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 2e18, "protocol balance");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 2e18, "totalFeesCollected");
        assertEq(fvm.eventFees(42, address(mockUSD)), 2e18, "eventFees");
        assertEq(fvm.userPaidFees(user1, address(mockUSD)), 2e18, "userPaidFees");
    }

    function test_C03_CollectFeeEmitsEvent() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        vm.expectEmit(true, true, false, true);
        emit IFeeVaultManager.FeeCollected(address(mockUSD), user1, 1e18, 1, "placement");
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
    }

    function test_C04_CollectFeeDeductsUserBalance() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        uint256 balBefore = fundingManager.getUserUsdBalance(user1);
        _collectFee(address(mockUSD), user1, 3e18, 1, "placement");
        uint256 balAfter = fundingManager.getUserUsdBalance(user1);
        assertEq(balBefore - balAfter, 3e18);
    }

    function test_C05_CollectFeeZeroAmountReverts() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        vm.prank(address(orderBookManager));
        vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidAmount.selector, 0));
        feeVaultManager.collectFee(address(mockUSD), user1, 0, 1, "placement");
    }

    function test_C06_CollectFeeInsufficientUserBalance() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 5e18);
        vm.prank(address(orderBookManager));
        vm.expectRevert();
        feeVaultManager.collectFee(address(mockUSD), user1, 10e18, 1, "placement");
    }

    function test_C07_CollectFeeMultipleTimes() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        _collectFee(address(mockUSD), user1, 2e18, 1, "execution");
        _collectFee(address(mockUSD), user1, 3e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 6e18, "protocol balance");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 6e18, "totalFeesCollected");
        assertEq(fvm.userPaidFees(user1, address(mockUSD)), 6e18, "userPaidFees");
    }

    function test_C08_CollectFeeMultipleEvents() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 2e18, 1, "placement");
        _collectFee(address(mockUSD), user1, 3e18, 2, "placement");
        assertEq(fvm.eventFees(1, address(mockUSD)), 2e18, "event 1 fees");
        assertEq(fvm.eventFees(2, address(mockUSD)), 3e18, "event 2 fees");
        assertEq(fvm.protocolUsdFeeBalance(), 5e18, "total balance");
    }

    function test_C09_CollectFeeMultipleUsers() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _depositForUser(user2, 100e18);
        _collectFee(address(mockUSD), user1, 2e18, 1, "placement");
        _collectFee(address(mockUSD), user2, 3e18, 1, "placement");
        assertEq(fvm.userPaidFees(user1, address(mockUSD)), 2e18, "user1 paid");
        assertEq(fvm.userPaidFees(user2, address(mockUSD)), 3e18, "user2 paid");
        assertEq(fvm.protocolUsdFeeBalance(), 5e18, "total balance");
    }

    function test_C10_CollectFeeDifferentFeeTypes() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        _collectFee(address(mockUSD), user1, 2e18, 1, "execution");
        // Both types accumulate into the same protocolUsdFeeBalance
        assertEq(fvm.protocolUsdFeeBalance(), 3e18);
    }

    // ============================================================
    // Group D — Fee Withdrawal Interaction Cycle
    // ============================================================

    function test_D01_WithdrawFeeBasicFlow() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        uint256 ownerBalBefore = mockUSD.balanceOf(owner);
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
        assertEq(fvm.protocolUsdFeeBalance(), 5e18, "remaining balance");
        // MockOracleAdapter returns $1 for any token; denormalizeFromUsd(mockUSD, 5e18) == 5e18
        assertEq(mockUSD.balanceOf(owner) - ownerBalBefore, 5e18, "owner received tokens");
    }

    function test_D02_WithdrawFeeFullAmount() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 10e18);
        assertEq(fvm.protocolUsdFeeBalance(), 0);
    }

    function test_D03_WithdrawFeeEmitsEvent() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IFeeVaultManager.FeeWithdrawn(address(mockUSD), owner, 5e18);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
    }

    function test_D04_WithdrawFeeUpdatesTotalWithdrawn() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 5e18);
    }

    function test_D05_WithdrawFeeOwnerReceivesTokens() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        uint256 balBefore = mockUSD.balanceOf(owner);
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 7e18);
        assertEq(mockUSD.balanceOf(owner) - balBefore, 7e18);
    }

    function test_D06_WithdrawFeeZeroAmountReverts() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFeeVaultManager.InvalidAmount.selector, 0));
        feeVaultManager.withdrawFee(address(mockUSD), 0);
    }

    function test_D07_WithdrawFeeExceedsBalanceReverts() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 5e18, 1, "placement");
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IFeeVaultManager.InsufficientFeeBalance.selector, address(mockUSD), 10e18, 5e18)
        );
        feeVaultManager.withdrawFee(address(mockUSD), 10e18);
    }

    function test_D08_WithdrawFeeMultipleTimes() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 3e18);
        assertEq(fvm.protocolUsdFeeBalance(), 7e18, "after first withdrawal");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 4e18);
        assertEq(fvm.protocolUsdFeeBalance(), 3e18, "after second withdrawal");
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 7e18, "total withdrawn");
    }

    function test_D09_WithdrawFeeReducesFundingManagerLiquidity() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        uint256 liqBefore = fundingManager.getTokenLiquidity(address(mockUSD));
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
        uint256 liqAfter = fundingManager.getTokenLiquidity(address(mockUSD));
        assertEq(liqBefore - liqAfter, 5e18);
    }

    // ============================================================
    // Group E — State Tracking & View Functions
    // ============================================================

    function test_E01_GetFeeBalanceReturnsProtocolBalance() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 7e18, 1, "placement");
        // token param is ignored — both return protocolUsdFeeBalance
        assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 7e18, "with mockUSD token");
        assertEq(feeVaultManager.getFeeBalance(address(0x1234)), 7e18, "with random token");
        assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), fvm.protocolUsdFeeBalance(), "matches public var");
    }

    function test_E02_GetProtocolUsdFeeBalanceMatchesPublicVar() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 4e18, 1, "placement");
        assertEq(feeVaultManager.getProtocolUsdFeeBalance(), fvm.protocolUsdFeeBalance());
    }

    function test_E03_TotalFeesCollectedPerToken() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 3e18, 1, "placement");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 3e18, "mockUSD collected");
        // Collect with a different token label — FundingManager still deducts from user's unified USD balance
        _collectFee(address(0xDEAD), user1, 2e18, 2, "execution");
        assertEq(fvm.totalFeesCollected(address(0xDEAD)), 2e18, "0xDEAD collected");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 3e18, "mockUSD unchanged");
    }

    function test_E04_TotalFeesWithdrawnPerToken() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 4e18);
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 4e18);
    }

    function test_E05_EventFeesPerEventPerToken() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 10, "placement");
        _collectFee(address(mockUSD), user1, 2e18, 20, "placement");
        _collectFee(address(mockUSD), user1, 3e18, 30, "placement");
        assertEq(fvm.eventFees(10, address(mockUSD)), 1e18, "event 10");
        assertEq(fvm.eventFees(20, address(mockUSD)), 2e18, "event 20");
        assertEq(fvm.eventFees(30, address(mockUSD)), 3e18, "event 30");
    }

    function test_E06_UserPaidFeesPerUserPerToken() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _depositForUser(user2, 100e18);
        _depositForUser(user3, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        _collectFee(address(mockUSD), user2, 2e18, 1, "placement");
        _collectFee(address(mockUSD), user3, 3e18, 1, "placement");
        assertEq(fvm.userPaidFees(user1, address(mockUSD)), 1e18, "user1");
        assertEq(fvm.userPaidFees(user2, address(mockUSD)), 2e18, "user2");
        assertEq(fvm.userPaidFees(user3, address(mockUSD)), 3e18, "user3");
    }

    function test_E07_BalanceInvariant() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        _depositAndCollectFee(user2, 100e18, 5e18, 2, "execution");
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 6e18);
        uint256 collected = fvm.totalFeesCollected(address(mockUSD));
        uint256 withdrawn = fvm.totalFeesWithdrawn(address(mockUSD));
        assertEq(fvm.protocolUsdFeeBalance(), collected - withdrawn, "balance invariant");
        assertEq(fvm.protocolUsdFeeBalance(), 9e18, "expected 9e18");
    }

    // ============================================================
    // Group F — Pause / Unpause Lifecycle
    // ============================================================

    function test_F01_PauseBlocksCollectFee() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        vm.prank(owner);
        feeVaultManager.pause();
        vm.prank(address(orderBookManager));
        vm.expectRevert();
        feeVaultManager.collectFee(address(mockUSD), user1, 1e18, 1, "placement");
    }

    function test_F02_UnpauseRestoresCollectFee() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        vm.prank(owner);
        feeVaultManager.pause();
        vm.prank(owner);
        feeVaultManager.unpause();
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 1e18);
    }

    function test_F03_PauseDoesNotBlockWithdrawFee() public {
        vm.revertTo(baseSnapshot);
        // withdrawFee has no whenNotPaused modifier — owner can still withdraw while paused
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.prank(owner);
        feeVaultManager.pause();
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
        assertEq(fvm.protocolUsdFeeBalance(), 5e18);
    }

    function test_F04_PauseDoesNotBlockViewFunctions() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        feeVaultManager.pause();
        feeVaultManager.getFeeRate("placement");
        feeVaultManager.calculateFee(100e18, "placement");
        feeVaultManager.getFeeBalance(address(mockUSD));
        feeVaultManager.getProtocolUsdFeeBalance();
        // All view calls above must complete without revert
    }

    function test_F05_PauseUnpauseCycle() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        vm.startPrank(owner);
        feeVaultManager.pause();
        feeVaultManager.unpause();
        feeVaultManager.pause();
        feeVaultManager.unpause();
        vm.stopPrank();
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 1e18);
    }

    // ============================================================
    // Group G — Multi-Event / Multi-User Aggregation
    // ============================================================

    function test_G01_ThreeUsersThreeEvents() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _depositForUser(user2, 100e18);
        _depositForUser(user3, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 1, "placement"); // user1 → event1
        _collectFee(address(mockUSD), user1, 2e18, 2, "execution"); // user1 → event2
        _collectFee(address(mockUSD), user2, 3e18, 2, "placement"); // user2 → event2
        _collectFee(address(mockUSD), user2, 4e18, 3, "placement"); // user2 → event3
        _collectFee(address(mockUSD), user3, 5e18, 3, "execution"); // user3 → event3
        assertEq(fvm.protocolUsdFeeBalance(), 15e18, "total");
        assertEq(fvm.eventFees(1, address(mockUSD)), 1e18, "event1");
        assertEq(fvm.eventFees(2, address(mockUSD)), 5e18, "event2: 2+3");
        assertEq(fvm.eventFees(3, address(mockUSD)), 9e18, "event3: 4+5");
        assertEq(fvm.userPaidFees(user1, address(mockUSD)), 3e18, "user1: 1+2");
        assertEq(fvm.userPaidFees(user2, address(mockUSD)), 7e18, "user2: 3+4");
        assertEq(fvm.userPaidFees(user3, address(mockUSD)), 5e18, "user3");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 15e18, "total collected");
    }

    function test_G02_CollectThenWithdrawThenCollectMore() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 10e18);
        vm.prank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 5e18);
        assertEq(fvm.protocolUsdFeeBalance(), 5e18);
        _collectFee(address(mockUSD), user1, 8e18, 2, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 13e18);
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 18e18, "total collected");
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 5e18, "total withdrawn");
    }

    function test_G03_MultipleWithdrawalsUntilDrained() public {
        vm.revertTo(baseSnapshot);
        _depositAndCollectFee(user1, 100e18, 10e18, 1, "placement");
        vm.startPrank(owner);
        feeVaultManager.withdrawFee(address(mockUSD), 3e18);
        assertEq(fvm.protocolUsdFeeBalance(), 7e18, "after 1st");
        feeVaultManager.withdrawFee(address(mockUSD), 3e18);
        assertEq(fvm.protocolUsdFeeBalance(), 4e18, "after 2nd");
        feeVaultManager.withdrawFee(address(mockUSD), 4e18);
        assertEq(fvm.protocolUsdFeeBalance(), 0, "drained");
        vm.stopPrank();
        assertEq(fvm.totalFeesWithdrawn(address(mockUSD)), 10e18);
    }

    function test_G04_TenUsersAccumulateFees() public {
        vm.revertTo(baseSnapshot);
        address[10] memory users;
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string.concat("bulk_user", vm.toString(i)));
            _depositAndCollectFee(users[i], 50e18, 1e18, i + 1, "placement");
        }
        assertEq(fvm.protocolUsdFeeBalance(), 10e18, "total balance");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 10e18, "total collected");
        for (uint256 i = 0; i < 10; i++) {
            assertEq(fvm.userPaidFees(users[i], address(mockUSD)), 1e18, "per user");
        }
    }

    // ============================================================
    // Group H — Edge Cases
    // ============================================================

    function test_H01_CollectFeeSmallAmount() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1, 1, "placement"); // 1 wei
        assertEq(fvm.protocolUsdFeeBalance(), 1, "balance");
        assertEq(fvm.totalFeesCollected(address(mockUSD)), 1, "collected");
    }

    function test_H02_CollectFeeLargeAmount() public {
        vm.revertTo(baseSnapshot);
        _depositForUser(user1, 2_000_000e18);
        _collectFee(address(mockUSD), user1, 1_000_000e18, 1, "placement");
        assertEq(fvm.protocolUsdFeeBalance(), 1_000_000e18);
    }

    function test_H03_CalculateFeeRoundsTruncated() public {
        vm.revertTo(baseSnapshot);
        // 1 wei * 10 / 10000 = 0 (integer truncation)
        assertEq(feeVaultManager.calculateFee(1, "placement"), 0);
    }

    function test_H04_CalculateFeeExactDivision() public {
        vm.revertTo(baseSnapshot);
        // 10000e18 * 10 / 10000 = exactly 10e18
        assertEq(feeVaultManager.calculateFee(10000e18, "placement"), 10e18);
    }

    function test_H05_WithdrawWithNoFeesReverts() public {
        vm.revertTo(baseSnapshot);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IFeeVaultManager.InsufficientFeeBalance.selector, address(mockUSD), 1, 0)
        );
        feeVaultManager.withdrawFee(address(mockUSD), 1);
    }

    function test_H06_CollectFeeWithEventIdZero() public {
        vm.revertTo(baseSnapshot);
        // FeeVaultManager does not validate eventId
        _depositForUser(user1, 100e18);
        _collectFee(address(mockUSD), user1, 1e18, 0, "placement");
        assertEq(fvm.eventFees(0, address(mockUSD)), 1e18, "event 0 fees");
        assertEq(fvm.protocolUsdFeeBalance(), 1e18, "balance");
    }

    function test_H07_GetFeeBalanceBeforeAnyCollection() public {
        vm.revertTo(baseSnapshot);
        assertEq(feeVaultManager.getFeeBalance(address(mockUSD)), 0);
        assertEq(feeVaultManager.getProtocolUsdFeeBalance(), 0);
    }

    function test_H08_SetFeeRateOverwriteEmitsOldAndNewRate() public {
        vm.revertTo(baseSnapshot);
        // Default placement rate is 10; overwrite to 50; event should include old=10, new=50
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IFeeVaultManager.FeeRateUpdated("placement", 10, 50);
        feeVaultManager.setFeeRate("placement", 50);
        assertEq(feeVaultManager.getFeeRate("placement"), 50);
    }
}
