// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {FeeVaultManager} from "../../src/core/FeeVaultManager.sol";
import {FeeVaultManagerProxy} from "../../src/core/proxies/FeeVaultManagerProxy.sol";

/**
 * @title FeeVaultManagerMakerTakerTest
 * @notice Unit tests for FeeVaultManager maker-taker fee functionality
 * @dev Tests the calculateMakerTakerFee function and fee rate initialization
 */
contract FeeVaultManagerMakerTakerTest is Test {
    FeeVaultManager internal feeVaultManager;
    address internal owner;
    address internal orderBookManager;
    address internal fundingManager;

    uint256 internal constant FEE_PRECISION = 10000; // 100% = 10000 basis points
    uint256 internal constant MAKER_PLACEMENT_FEE = 0; // 0%
    uint256 internal constant MAKER_EXECUTION_FEE = 5; // 0.05%
    uint256 internal constant TAKER_EXECUTION_FEE = 25; // 0.25%

    function setUp() public {
        owner = makeAddr("owner");
        orderBookManager = makeAddr("orderBookManager");
        fundingManager = makeAddr("fundingManager");

        // Deploy FeeVaultManager with proxy
        FeeVaultManager impl = new FeeVaultManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        FeeVaultManagerProxy proxy = new FeeVaultManagerProxy(address(impl), initData);
        feeVaultManager = FeeVaultManager(payable(address(proxy)));

        // Set managers
        vm.startPrank(owner);
        feeVaultManager.setOrderBookManager(orderBookManager);
        feeVaultManager.setFundingManager(fundingManager);
        vm.stopPrank();
    }

    // ============ Initialization Tests ============

    function testInitialize_MakerTakerFeesSet() public {
        // Verify maker placement fee is 0%
        uint256 makerPlacementRate = feeVaultManager.getFeeRate("maker_placement");
        assertEq(makerPlacementRate, MAKER_PLACEMENT_FEE, "Maker placement fee should be 0%");

        // Verify maker execution fee is 0.05%
        uint256 makerExecutionRate = feeVaultManager.getFeeRate("maker_execution");
        assertEq(makerExecutionRate, MAKER_EXECUTION_FEE, "Maker execution fee should be 0.05%");

        // Verify taker execution fee is 0.25%
        uint256 takerExecutionRate = feeVaultManager.getFeeRate("taker_execution");
        assertEq(takerExecutionRate, TAKER_EXECUTION_FEE, "Taker execution fee should be 0.25%");
    }

    // ============ Maker Fee Calculation Tests ============

    function testCalculateMakerTakerFee_Maker_SmallAmount() public {
        uint256 amount = 100 ether; // 100 USD
        uint256 expectedFee = (amount * MAKER_EXECUTION_FEE) / FEE_PRECISION; // 0.05 USD

        uint256 fee = feeVaultManager.calculateMakerTakerFee(amount, true);

        assertEq(fee, expectedFee, "Maker fee should be 0.05% of amount");
        assertEq(fee, 0.05 ether, "Maker fee should be 0.05 USD");
    }

    function testCalculateMakerTakerFee_Maker_LargeAmount() public {
        uint256 amount = 10000 ether; // 10,000 USD
        uint256 expectedFee = (amount * MAKER_EXECUTION_FEE) / FEE_PRECISION; // 5 USD

        uint256 fee = feeVaultManager.calculateMakerTakerFee(amount, true);

        assertEq(fee, expectedFee, "Maker fee should be 0.05% of amount");
        assertEq(fee, 5 ether, "Maker fee should be 5 USD");
    }

    function testCalculateMakerTakerFee_Maker_ZeroAmount() public {
        uint256 fee = feeVaultManager.calculateMakerTakerFee(0, true);
        assertEq(fee, 0, "Maker fee should be 0 for zero amount");
    }

    // ============ Taker Fee Calculation Tests ============

    function testCalculateMakerTakerFee_Taker_SmallAmount() public {
        uint256 amount = 100 ether; // 100 USD
        uint256 expectedFee = (amount * TAKER_EXECUTION_FEE) / FEE_PRECISION; // 0.25 USD

        uint256 fee = feeVaultManager.calculateMakerTakerFee(amount, false);

        assertEq(fee, expectedFee, "Taker fee should be 0.25% of amount");
        assertEq(fee, 0.25 ether, "Taker fee should be 0.25 USD");
    }

    function testCalculateMakerTakerFee_Taker_LargeAmount() public {
        uint256 amount = 10000 ether; // 10,000 USD
        uint256 expectedFee = (amount * TAKER_EXECUTION_FEE) / FEE_PRECISION; // 25 USD

        uint256 fee = feeVaultManager.calculateMakerTakerFee(amount, false);

        assertEq(fee, expectedFee, "Taker fee should be 0.25% of amount");
        assertEq(fee, 25 ether, "Taker fee should be 25 USD");
    }

    function testCalculateMakerTakerFee_Taker_ZeroAmount() public {
        uint256 fee = feeVaultManager.calculateMakerTakerFee(0, false);
        assertEq(fee, 0, "Taker fee should be 0 for zero amount");
    }

    // ============ Comparison Tests ============

    function testCalculateMakerTakerFee_TakerPaysFiveTimesMore() public {
        uint256 amount = 1000 ether; // 1,000 USD

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(amount, false);

        // Taker fee (0.25%) should be 5x maker fee (0.05%)
        assertEq(takerFee, makerFee * 5, "Taker fee should be 5x maker fee");
        assertEq(makerFee, 0.5 ether, "Maker fee should be 0.5 USD");
        assertEq(takerFee, 2.5 ether, "Taker fee should be 2.5 USD");
    }

    function testCalculateMakerTakerFee_MakerCheaperThanTaker() public {
        uint256 amount = 5000 ether; // 5,000 USD

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(amount, false);

        assertTrue(makerFee < takerFee, "Maker fee should be less than taker fee");
        assertEq(makerFee, 2.5 ether, "Maker fee should be 2.5 USD");
        assertEq(takerFee, 12.5 ether, "Taker fee should be 12.5 USD");
    }

    // ============ Edge Case Tests ============

    function testCalculateMakerTakerFee_VerySmallAmount() public {
        uint256 amount = 1 wei;

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(amount, false);

        // Fees should round up to prevent undercharging (ceiling division)
        // For 1 wei: (1 * 5 + 9999) / 10000 = 1, (1 * 25 + 9999) / 10000 = 1
        assertEq(makerFee, 1, "Maker fee should round up to 1");
        assertEq(takerFee, 1, "Taker fee should round up to 1");
    }

    function testCalculateMakerTakerFee_PrecisionTest() public {
        // Test that fee calculation maintains precision
        uint256 amount = 12345 ether; // 12,345 USD

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(amount, false);

        // Maker: 12345 * 5 / 10000 = 6.1725 USD
        assertEq(makerFee, 6.1725 ether, "Maker fee precision");

        // Taker: 12345 * 25 / 10000 = 30.8625 USD
        assertEq(takerFee, 30.8625 ether, "Taker fee precision");
    }

    // ============ Real-World Scenario Tests ============

    function testCalculateMakerTakerFee_TypicalTrade() public {
        // Typical trade: 500 USD worth of tokens
        uint256 tradeAmount = 500 ether;

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, false);

        // Maker pays 0.25 USD (0.05%)
        assertEq(makerFee, 0.25 ether, "Maker pays 0.25 USD");

        // Taker pays 1.25 USD (0.25%)
        assertEq(takerFee, 1.25 ether, "Taker pays 1.25 USD");

        // Total fees: 1.5 USD (0.3% of trade)
        uint256 totalFees = makerFee + takerFee;
        assertEq(totalFees, 1.5 ether, "Total fees should be 1.5 USD");
    }

    function testCalculateMakerTakerFee_LargeInstitutionalTrade() public {
        // Large institutional trade: 100,000 USD
        uint256 tradeAmount = 100000 ether;

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, false);

        // Maker pays 50 USD (0.05%)
        assertEq(makerFee, 50 ether, "Maker pays 50 USD");

        // Taker pays 250 USD (0.25%)
        assertEq(takerFee, 250 ether, "Taker pays 250 USD");

        // Total fees: 300 USD (0.3% of trade)
        uint256 totalFees = makerFee + takerFee;
        assertEq(totalFees, 300 ether, "Total fees should be 300 USD");
    }

    function testCalculateMakerTakerFee_SmallRetailTrade() public {
        // Small retail trade: 10 USD
        uint256 tradeAmount = 10 ether;

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(tradeAmount, false);

        // Maker pays 0.005 USD (0.05%)
        assertEq(makerFee, 0.005 ether, "Maker pays 0.005 USD");

        // Taker pays 0.025 USD (0.25%)
        assertEq(takerFee, 0.025 ether, "Taker pays 0.025 USD");

        // Total fees: 0.03 USD (0.3% of trade)
        uint256 totalFees = makerFee + takerFee;
        assertEq(totalFees, 0.03 ether, "Total fees should be 0.03 USD");
    }

    // ============ Fuzz Tests ============

    function testFuzz_CalculateMakerTakerFee_MakerAlwaysCheaper(uint256 amount) public {
        // Constrain to reasonable range to avoid overflow and ensure non-zero fees
        vm.assume(amount >= 10000 && amount < type(uint128).max);

        uint256 makerFee = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 takerFee = feeVaultManager.calculateMakerTakerFee(amount, false);

        // Maker fee should always be less than taker fee
        assertTrue(makerFee < takerFee, "Maker fee should always be less than taker fee");
    }

    function testFuzz_CalculateMakerTakerFee_ProportionalToAmount(uint256 amount) public {
        // Constrain to reasonable range
        vm.assume(amount > 1000 && amount < type(uint128).max);

        uint256 makerFee1 = feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 makerFee2 = feeVaultManager.calculateMakerTakerFee(amount * 2, true);

        // Fee for 2x amount should be approximately 2x the fee
        // Allow for rounding errors
        uint256 expectedFee2 = makerFee1 * 2;
        uint256 diff = makerFee2 > expectedFee2 ? makerFee2 - expectedFee2 : expectedFee2 - makerFee2;

        // Difference should be less than 1 wei (rounding error)
        assertTrue(diff <= 1, "Fee should be proportional to amount");
    }

    // ============ Gas Optimization Tests ============

    function testGas_CalculateMakerTakerFee_Maker() public {
        uint256 amount = 1000 ether;

        uint256 gasBefore = gasleft();
        feeVaultManager.calculateMakerTakerFee(amount, true);
        uint256 gasUsed = gasBefore - gasleft();

        // Fee calculation should be reasonably cheap (< 20000 gas)
        assertTrue(gasUsed < 20000, "Maker fee calculation should be gas efficient");
    }

    function testGas_CalculateMakerTakerFee_Taker() public {
        uint256 amount = 1000 ether;

        uint256 gasBefore = gasleft();
        feeVaultManager.calculateMakerTakerFee(amount, false);
        uint256 gasUsed = gasBefore - gasleft();

        // Fee calculation should be reasonably cheap (< 20000 gas)
        assertTrue(gasUsed < 20000, "Taker fee calculation should be gas efficient");
    }
}
