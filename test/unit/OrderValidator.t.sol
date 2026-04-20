// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {OrderValidator} from "../../src/core/OrderValidator.sol";
import {OrderStruct, OrderKey} from "../../src/library/OrderStruct.sol";

/**
 * @title OrderValidatorHarness
 * @notice Concrete implementation of OrderValidator for testing
 */
contract OrderValidatorHarness is OrderValidator {
    // Mock event outcome counts for testing
    mapping(uint256 => uint8) private mockEventOutcomeCount;

    function initialize() public initializer {
        __EIP712_init("OrderBook", "1");
    }

    // Implement abstract function for testing
    function _getEventOutcomeCount(uint256 eventId) internal view override returns (uint8) {
        return mockEventOutcomeCount[eventId];
    }

    // Helper function to set mock event outcome count for tests
    function setMockEventOutcomeCount(uint256 eventId, uint8 outcomeCount) external {
        mockEventOutcomeCount[eventId] = outcomeCount;
    }

    function markFilled(OrderKey key, uint128 amount) external {
        _markFilled(key, amount);
    }

    function markCancelled(OrderKey key) external {
        _markCancelled(key);
    }

    function isCancelled(OrderKey key) external view returns (bool) {
        return _isCancelled(key);
    }

    function getFilledAmount(OrderKey key) external view returns (uint128) {
        return _getFilledAmount(key);
    }
}

/**
 * @title OrderValidatorTest
 * @notice Comprehensive unit tests for OrderValidator
 * @dev Tests parameter validation, EIP712 signature verification, and state management
 */
contract OrderValidatorTest is Test {
    OrderValidatorHarness internal validator;

    address internal maker;
    uint256 internal makerPrivateKey;

    uint256 internal constant EVENT_ID = 1;
    uint8 internal constant OUTCOME_INDEX = 0;
    uint128 internal constant VALID_PRICE = 8000; // 80%
    uint128 internal constant VALID_AMOUNT = 100 ether;
    uint64 internal constant FUTURE_EXPIRY = type(uint64).max;

    function setUp() public {
        validator = new OrderValidatorHarness();
        validator.initialize();

        // Create maker with known private key for signature testing
        makerPrivateKey = 0x1234;
        maker = vm.addr(makerPrivateKey);

        // Set up mock event with 3 outcomes for testing
        validator.setMockEventOutcomeCount(EVENT_ID, 3);
    }

    // ============ Parameter Validation Tests ============

    function testValidateOrderParams_ValidParams_Success() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            VALID_PRICE,
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertTrue(valid, "Valid params should pass");
        assertEq(bytes(reason).length, 0, "Reason should be empty for valid params");
    }

    function testValidateOrderParams_ZeroMaker_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            address(0),
            EVENT_ID,
            OUTCOME_INDEX,
            VALID_PRICE,
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Zero maker should fail");
        assertEq(reason, "Invalid maker address", "Wrong error message");
    }

    function testValidateOrderParams_EventNotRegistered_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            999, // Unregistered event
            OUTCOME_INDEX,
            VALID_PRICE,
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Unregistered event should fail");
        assertEq(reason, "Event not registered", "Wrong error message");
    }

    function testValidateOrderParams_OutcomeIndexOutOfRange_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            5, // Out of range (event has 3 outcomes: 0, 1, 2)
            VALID_PRICE,
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Out of range outcome should fail");
        assertEq(reason, "Outcome index out of range", "Wrong error message");
    }

    function testValidateOrderParams_ZeroPrice_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            0, // Zero price
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Zero price should fail");
        assertEq(reason, "Price out of range", "Wrong error message");
    }

    function testValidateOrderParams_PriceTooHigh_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            10001, // Above MAX_PRICE
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Price above MAX_PRICE should fail");
        assertEq(reason, "Price out of range", "Wrong error message");
    }

    function testValidateOrderParams_PriceNotAligned_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            8005, // Not multiple of TICK_SIZE (10)
            VALID_AMOUNT,
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Misaligned price should fail");
        assertEq(reason, "Price not aligned with tick size", "Wrong error message");
    }

    function testValidateOrderParams_ZeroAmount_Fails() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            VALID_PRICE,
            0, // Zero amount
            FUTURE_EXPIRY
        );

        assertFalse(valid, "Zero amount should fail");
        assertEq(reason, "Amount must be greater than zero", "Wrong error message");
    }

    function testValidateOrderParams_ExpiredOrder_Fails() public {
        // Set block timestamp to a known value
        vm.warp(1000000);
        uint64 pastExpiry = uint64(block.timestamp - 1);

        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            VALID_PRICE,
            VALID_AMOUNT,
            pastExpiry
        );

        assertFalse(valid, "Expired order should fail");
        assertEq(reason, "Order expired", "Wrong error message");
    }

    function testValidateOrderParams_ZeroExpiry_Success() public {
        (bool valid, string memory reason) = validator.validateOrderParams(
            maker,
            EVENT_ID,
            OUTCOME_INDEX,
            VALID_PRICE,
            VALID_AMOUNT,
            0 // Zero expiry means never expires
        );

        assertTrue(valid, "Zero expiry should be valid");
        assertEq(bytes(reason).length, 0, "Reason should be empty");
    }

    function testValidateOrderParams_EdgeCasePrices() public {
        // Test minimum valid price (10 = 0.1%)
        (bool valid1,) = validator.validateOrderParams(
            maker, EVENT_ID, OUTCOME_INDEX, 10, VALID_AMOUNT, 0
        );
        assertTrue(valid1, "Minimum price (10) should be valid");

        // Test maximum valid price (10000 = 100%)
        (bool valid2,) = validator.validateOrderParams(
            maker, EVENT_ID, OUTCOME_INDEX, 10000, VALID_AMOUNT, 0
        );
        assertTrue(valid2, "Maximum price (10000) should be valid");

        // Test mid-range aligned price (5000 = 50%)
        (bool valid3,) = validator.validateOrderParams(
            maker, EVENT_ID, OUTCOME_INDEX, 5000, VALID_AMOUNT, 0
        );
        assertTrue(valid3, "Mid-range price (5000) should be valid");
    }

    // ============ EIP712 Signature Tests ============

    function testVerifyOrderSignature_ValidSignature_Success() public {
        OrderStruct.Order memory order = _createOrder(maker, VALID_PRICE, VALID_AMOUNT, 0, 12345);

        // Sign the order
        bytes32 orderHash = validator.getOrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature
        bool isValid = validator.verifyOrderSignature(order, signature);
        assertTrue(isValid, "Valid signature should pass verification");
    }

    function testVerifyOrderSignature_InvalidSignature_Fails() public {
        OrderStruct.Order memory order = _createOrder(maker, VALID_PRICE, VALID_AMOUNT, 0, 12345);

        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x5678;
        bytes32 orderHash = validator.getOrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, orderHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature
        bool isValid = validator.verifyOrderSignature(order, signature);
        assertFalse(isValid, "Invalid signature should fail verification");
    }

    function testVerifyOrderSignature_ModifiedOrder_Fails() public {
        OrderStruct.Order memory order = _createOrder(maker, VALID_PRICE, VALID_AMOUNT, 0, 12345);

        // Sign the original order
        bytes32 orderHash = validator.getOrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Modify the order after signing
        order.price = 7000;

        // Verify signature (should fail because order was modified)
        bool isValid = validator.verifyOrderSignature(order, signature);
        assertFalse(isValid, "Signature should fail for modified order");
    }

    function testGetOrderHash_DifferentOrders_DifferentHashes() public {
        OrderStruct.Order memory order1 = _createOrder(maker, 8000, 100 ether, 0, 12345);
        OrderStruct.Order memory order2 = _createOrder(maker, 7000, 100 ether, 0, 12345);

        bytes32 hash1 = validator.getOrderHash(order1);
        bytes32 hash2 = validator.getOrderHash(order2);

        assertTrue(hash1 != hash2, "Different orders should have different hashes");
    }

    function testGetOrderHash_SameOrders_SameHashes() public {
        OrderStruct.Order memory order1 = _createOrder(maker, 8000, 100 ether, 0, 12345);
        OrderStruct.Order memory order2 = _createOrder(maker, 8000, 100 ether, 0, 12345);

        bytes32 hash1 = validator.getOrderHash(order1);
        bytes32 hash2 = validator.getOrderHash(order2);

        assertEq(hash1, hash2, "Same orders should have same hashes");
    }

    // ============ State Management Tests ============

    function testMarkFilled_SingleFill_Success() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));
        uint128 fillAmount = 50 ether;

        validator.markFilled(key, fillAmount);

        uint128 filled = validator.getFilledAmount(key);
        assertEq(filled, fillAmount, "Filled amount should match");
    }

    function testMarkFilled_MultipleFills_Accumulates() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));

        validator.markFilled(key, 30 ether);
        validator.markFilled(key, 20 ether);
        validator.markFilled(key, 50 ether);

        uint128 filled = validator.getFilledAmount(key);
        assertEq(filled, 100 ether, "Filled amount should accumulate");
    }

    function testMarkCancelled_Success() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));

        assertFalse(validator.isCancelled(key), "Order should not be cancelled initially");

        validator.markCancelled(key);

        assertTrue(validator.isCancelled(key), "Order should be cancelled after marking");
    }

    function testGetFilledAmount_UnfilledOrder_ReturnsZero() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));

        uint128 filled = validator.getFilledAmount(key);
        assertEq(filled, 0, "Unfilled order should return zero");
    }

    function testIsCancelled_UncancelledOrder_ReturnsFalse() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));

        bool cancelled = validator.isCancelled(key);
        assertFalse(cancelled, "Uncancelled order should return false");
    }

    // ============ Integration Tests ============

    function testFullOrderLifecycle_PartialFillThenCancel() public {
        OrderKey key = OrderKey.wrap(keccak256("order1"));

        // Partially fill the order
        validator.markFilled(key, 30 ether);
        assertEq(validator.getFilledAmount(key), 30 ether, "Should have 30 ether filled");
        assertFalse(validator.isCancelled(key), "Should not be cancelled yet");

        // Fill more
        validator.markFilled(key, 20 ether);
        assertEq(validator.getFilledAmount(key), 50 ether, "Should have 50 ether filled");

        // Cancel the order
        validator.markCancelled(key);
        assertTrue(validator.isCancelled(key), "Should be cancelled");
        assertEq(validator.getFilledAmount(key), 50 ether, "Filled amount should remain");
    }

    function testMultipleOrders_IsolatedState() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));

        // Fill and cancel different orders
        validator.markFilled(key1, 30 ether);
        validator.markFilled(key2, 50 ether);
        validator.markCancelled(key1);

        // Verify isolation
        assertEq(validator.getFilledAmount(key1), 30 ether, "Order 1 filled amount");
        assertEq(validator.getFilledAmount(key2), 50 ether, "Order 2 filled amount");
        assertTrue(validator.isCancelled(key1), "Order 1 should be cancelled");
        assertFalse(validator.isCancelled(key2), "Order 2 should not be cancelled");
    }

    // ============ Fuzz Tests ============

    function testFuzz_ValidateOrderParams_ValidPrices(uint128 price) public {
        // Constrain price to valid range and alignment
        vm.assume(price > 0 && price <= 10000);
        vm.assume(price % 10 == 0); // Aligned with TICK_SIZE

        (bool valid,) = validator.validateOrderParams(
            maker, EVENT_ID, OUTCOME_INDEX, price, VALID_AMOUNT, 0
        );

        assertTrue(valid, "Valid aligned price should pass");
    }

    function testFuzz_ValidateOrderParams_InvalidPrices(uint128 price) public {
        // Test prices that are either out of range or misaligned
        vm.assume(price == 0 || price > 10000 || price % 10 != 0);

        (bool valid,) = validator.validateOrderParams(
            maker, EVENT_ID, OUTCOME_INDEX, price, VALID_AMOUNT, 0
        );

        assertFalse(valid, "Invalid price should fail");
    }

    function testFuzz_MarkFilled_Accumulation(uint128 amount1, uint128 amount2) public {
        // Prevent overflow
        vm.assume(uint256(amount1) + uint256(amount2) <= type(uint128).max);

        OrderKey key = OrderKey.wrap(keccak256("order1"));

        validator.markFilled(key, amount1);
        validator.markFilled(key, amount2);

        uint128 filled = validator.getFilledAmount(key);
        assertEq(filled, amount1 + amount2, "Filled amounts should accumulate");
    }

    // ============ Helper Functions ============

    function _createOrder(
        address _maker,
        uint128 _price,
        uint128 _amount,
        uint64 _expiry,
        uint64 _salt
    ) internal pure returns (OrderStruct.Order memory) {
        return OrderStruct.Order({
            orderId: 0,
            eventId: EVENT_ID,
            maker: _maker,
            outcomeIndex: OUTCOME_INDEX,
            side: OrderStruct.Side.Buy,
            price: _price,
            amount: _amount,
            filledAmount: 0,
            remainingAmount: _amount,
            status: OrderStruct.OrderStatus.Pending,
            timestamp: 0,
            expiry: _expiry,
            salt: _salt,
            tokenAddress: address(0)
        });
    }
}
