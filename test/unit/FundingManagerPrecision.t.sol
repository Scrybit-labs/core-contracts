// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {FundingManager} from "../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../src/core/proxies/FundingManagerProxy.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract FundingManagerPrecisionTest is Test {
    using stdStorage for StdStorage;

    FundingManager internal fundingManager;
    address internal owner;
    address internal orderBook;
    address internal buyer;
    address internal seller;

    uint256 internal constant EVENT_ID = 1;
    uint8 internal constant OUTCOME_INDEX = 0;

    function setUp() public {
        owner = makeAddr("owner");
        orderBook = makeAddr("orderBook");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");

        FundingManager impl = new FundingManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy proxy = new FundingManagerProxy(address(impl), initData);
        fundingManager = FundingManager(payable(address(proxy)));

        vm.startPrank(owner);
        fundingManager.setOrderBookManager(orderBook);
        vm.stopPrank();
    }

    function testSettleMatchedOrder_NormalAmount() public {
        uint256 buyOrderId = 1;
        uint256 sellOrderId = 2;
        uint256 matchAmount = 100 ether;
        uint256 matchPrice = 5000;
        uint256 payment = 50 ether;

        _setOrderLockedUsd(buyOrderId, payment);
        _setOrderLockedLong(sellOrderId, matchAmount);

        vm.prank(orderBook);
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );

        assertEq(fundingManager.orderLockedUsd(buyOrderId), 0);
        assertEq(fundingManager.orderLockedLong(sellOrderId), 0);
        assertEq(fundingManager.getLongPosition(buyer, EVENT_ID, OUTCOME_INDEX), matchAmount);
        assertEq(fundingManager.getUserUsdBalance(seller), payment);
    }

    function testSettleMatchedOrder_SmallAmount_NonZeroPayment() public {
        uint256 buyOrderId = 3;
        uint256 sellOrderId = 4;
        uint256 matchAmount = 1e14;
        uint256 matchPrice = 100;
        uint256 payment = 1e12;

        _setOrderLockedUsd(buyOrderId, payment);
        _setOrderLockedLong(sellOrderId, matchAmount);

        vm.prank(orderBook);
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );

        assertEq(fundingManager.getUserUsdBalance(seller), payment);
    }

    function testSettleMatchedOrder_VerySmallAmount_RevertsOnZeroPayment() public {
        uint256 buyOrderId = 5;
        uint256 sellOrderId = 6;
        uint256 matchAmount = 1;
        uint256 matchPrice = 1;

        _setOrderLockedUsd(buyOrderId, 0);
        _setOrderLockedLong(sellOrderId, matchAmount);

        vm.prank(orderBook);
        vm.expectRevert("FundingManager: payment rounds to zero");
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );
    }

    function testSettleMatchedOrder_ZeroAmount_Allowed() public {
        uint256 buyOrderId = 7;
        uint256 sellOrderId = 8;
        uint256 matchAmount = 0;
        uint256 matchPrice = 1;

        _setOrderLockedUsd(buyOrderId, 0);
        _setOrderLockedLong(sellOrderId, 0);

        vm.prank(orderBook);
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );

        assertEq(fundingManager.getUserUsdBalance(seller), 0);
    }

    function testFuzz_SettleMatchedOrder_PaymentNeverExceedsAmount(uint256 matchAmount, uint256 matchPrice) public {
        uint256 pricePrecision = fundingManager.PRICE_PRECISION();
        matchPrice = bound(matchPrice, 1, pricePrecision);
        matchAmount = bound(matchAmount, 1, type(uint256).max / pricePrecision);

        uint256 payment = FixedPointMathLib.mulDiv(matchAmount, matchPrice, pricePrecision);
        vm.assume(payment > 0);

        uint256 buyOrderId = 9;
        uint256 sellOrderId = 10;

        _setOrderLockedUsd(buyOrderId, payment);
        _setOrderLockedLong(sellOrderId, matchAmount);

        vm.prank(orderBook);
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );

        assertLe(payment, matchAmount);
        assertEq(fundingManager.getUserUsdBalance(seller), payment);
    }

    function testSettleMatchedOrder_LargeValues_NoOverflow() public {
        uint256 buyOrderId = 11;
        uint256 sellOrderId = 12;
        uint256 matchAmount = type(uint256).max / fundingManager.PRICE_PRECISION();
        uint256 matchPrice = fundingManager.PRICE_PRECISION();

        uint256 payment = FixedPointMathLib.mulDiv(matchAmount, matchPrice, fundingManager.PRICE_PRECISION());

        _setOrderLockedUsd(buyOrderId, payment);
        _setOrderLockedLong(sellOrderId, matchAmount);

        vm.prank(orderBook);
        fundingManager.settleMatchedOrder(
            buyOrderId,
            sellOrderId,
            buyer,
            seller,
            matchAmount,
            matchPrice,
            EVENT_ID,
            OUTCOME_INDEX
        );

        assertEq(fundingManager.getUserUsdBalance(seller), payment);
    }

    function _setOrderLockedUsd(uint256 orderId, uint256 amount) internal {
        stdstore
            .target(address(fundingManager))
            .sig("orderLockedUsd(uint256)")
            .with_key(orderId)
            .checked_write(amount);
    }

    function _setOrderLockedLong(uint256 orderId, uint256 amount) internal {
        stdstore
            .target(address(fundingManager))
            .sig("orderLockedLong(uint256)")
            .with_key(orderId)
            .checked_write(amount);
    }
}
