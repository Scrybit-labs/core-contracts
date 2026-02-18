// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {OrderStorage} from "../../src/core/OrderStorage.sol";
import {OrderStorageProxy} from "../../src/core/proxies/OrderStorageProxy.sol";
import {OrderKey, OrderStruct} from "../../src/library/OrderStruct.sol";
import {Price} from "../../src/library/RedBlackTreeLibrary.sol";

/**
 * @title OrderStorageTest
 * @notice Comprehensive unit tests for OrderStorage 3-layer architecture
 * @dev Tests Layer 1 (Price Trees), Layer 2 (Order Queues), Layer 3 (Global Orders)
 */
contract OrderStorageTest is Test {
    OrderStorage internal orderStorage;
    address internal owner;
    address internal orderBookManager;
    address internal unauthorized;

    uint256 internal constant EVENT_ID = 1;
    uint8 internal constant OUTCOME_INDEX = 0;
    uint128 internal constant PRICE_8000 = 8000;
    uint128 internal constant PRICE_7000 = 7000;
    uint128 internal constant PRICE_9000 = 9000;

    function setUp() public {
        owner = makeAddr("owner");
        orderBookManager = makeAddr("orderBookManager");
        unauthorized = makeAddr("unauthorized");

        // Deploy OrderStorage with proxy
        OrderStorage impl = new OrderStorage();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        OrderStorageProxy proxy = new OrderStorageProxy(address(impl), initData);
        orderStorage = OrderStorage(address(proxy));

        // Set OrderBookManager
        vm.prank(owner);
        orderStorage.setOrderBookManager(orderBookManager);
    }

    // ============ Helper Functions ============

    function _createEmptyOrder() internal pure returns (OrderStruct.Order memory) {
        return OrderStruct.Order({
            orderId: 0,
            eventId: 0,
            maker: address(0),
            outcomeIndex: 0,
            side: OrderStruct.Side.Buy,
            price: 0,
            amount: 0,
            filledAmount: 0,
            remainingAmount: 0,
            status: OrderStruct.OrderStatus.Pending,
            timestamp: 0,
            expiry: 0,
            salt: 0,
            tokenAddress: address(0)
        });
    }

    // ============ Layer 1: Price Tree Tests ============

    function testInsertPrice_SinglePrice_Success() public {
        vm.prank(orderBookManager);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        // Verify price is now the best price
        uint128 bestPrice = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, true);
        assertEq(bestPrice, PRICE_8000, "Best price should be 8000");
    }

    function testInsertPrice_MultiplePrices_SortedCorrectly() public {
        vm.startPrank(orderBookManager);

        // Insert prices in random order
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_7000);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_9000);

        vm.stopPrank();

        // For buy orders, best price should be highest (9000)
        uint128 bestBid = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, true);
        assertEq(bestBid, PRICE_9000, "Best bid should be 9000");

        // Next price should be 8000
        uint128 nextPrice = orderStorage.getNextPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_9000);
        assertEq(nextPrice, PRICE_8000, "Next price should be 8000");

        // Next price should be 7000
        nextPrice = orderStorage.getNextPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertEq(nextPrice, PRICE_7000, "Next price should be 7000");
    }

    function testInsertPrice_SellOrders_BestPriceIsLowest() public {
        vm.startPrank(orderBookManager);

        // Insert sell prices
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, false, PRICE_8000);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, false, PRICE_7000);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, false, PRICE_9000);

        vm.stopPrank();

        // For sell orders, best price should be lowest (7000)
        uint128 bestAsk = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, false);
        assertEq(bestAsk, PRICE_7000, "Best ask should be 7000");
    }

    function testRemovePrice_ExistingPrice_Success() public {
        vm.startPrank(orderBookManager);

        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_7000);

        // Remove 8000
        orderStorage.removePrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        vm.stopPrank();

        // Best price should now be 7000
        uint128 bestPrice = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, true);
        assertEq(bestPrice, PRICE_7000, "Best price should be 7000 after removal");
    }

    function testGetBestPrice_EmptyTree_ReturnsZero() public {
        uint128 bestPrice = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, true);
        assertEq(bestPrice, 0, "Best price should be 0 for empty tree");
    }

    function testGetNextPrice_NoMorePrices_ReturnsZero() public {
        vm.prank(orderBookManager);
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        uint128 nextPrice = orderStorage.getNextPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertEq(nextPrice, 0, "Next price should be 0 when no more prices");
    }

    function testInsertPrice_UnauthorizedCaller_Reverts() public {
        vm.prank(unauthorized);
        vm.expectRevert("OrderStorage: only OrderBookManager");
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
    }

    // ============ Layer 2: Order Queue Tests ============

    function testEnqueueOrder_SingleOrder_Success() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));

        vm.prank(orderBookManager);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);

        // Verify order is at head
        OrderKey head = orderStorage.peekOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertEq(OrderKey.unwrap(head), OrderKey.unwrap(key1), "Order should be at head");

        // Verify queue is not empty
        bool isEmpty = orderStorage.isQueueEmpty(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertFalse(isEmpty, "Queue should not be empty");
    }

    function testEnqueueOrder_MultipleOrders_FIFOOrder() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));
        OrderKey key3 = OrderKey.wrap(keccak256("order3"));

        vm.startPrank(orderBookManager);

        // Enqueue orders
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key2);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key3);

        vm.stopPrank();

        // First order should be key1
        OrderKey head = orderStorage.peekOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertEq(OrderKey.unwrap(head), OrderKey.unwrap(key1), "First order should be key1");
    }

    function testDequeueOrder_SingleOrder_EmptiesQueue() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));

        vm.startPrank(orderBookManager);

        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);
        OrderKey dequeued = orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        vm.stopPrank();

        // Verify dequeued order is key1
        assertEq(OrderKey.unwrap(dequeued), OrderKey.unwrap(key1), "Dequeued order should be key1");

        // Verify queue is now empty
        bool isEmpty = orderStorage.isQueueEmpty(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertTrue(isEmpty, "Queue should be empty after dequeue");
    }

    function testDequeueOrder_MultipleOrders_FIFOOrder() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));
        OrderKey key3 = OrderKey.wrap(keccak256("order3"));

        vm.startPrank(orderBookManager);

        // Enqueue orders
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key2);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key3);

        // Store order data to link them
        OrderStruct.Order memory emptyOrder = _createEmptyOrder();
        OrderStruct.DBOrder memory order1 = OrderStruct.DBOrder({order: emptyOrder, next: key2});
        OrderStruct.DBOrder memory order2 = OrderStruct.DBOrder({order: emptyOrder, next: key3});
        OrderStruct.DBOrder memory order3 = OrderStruct.DBOrder({order: emptyOrder, next: OrderKey.wrap(bytes32(0))});

        orderStorage.storeOrder(key1, order1);
        orderStorage.storeOrder(key2, order2);
        orderStorage.storeOrder(key3, order3);

        // Dequeue in FIFO order
        OrderKey dequeued1 = orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        OrderKey dequeued2 = orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        OrderKey dequeued3 = orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        vm.stopPrank();

        // Verify FIFO order
        assertEq(OrderKey.unwrap(dequeued1), OrderKey.unwrap(key1), "First dequeued should be key1");
        assertEq(OrderKey.unwrap(dequeued2), OrderKey.unwrap(key2), "Second dequeued should be key2");
        assertEq(OrderKey.unwrap(dequeued3), OrderKey.unwrap(key3), "Third dequeued should be key3");

        // Verify queue is now empty
        bool isEmpty = orderStorage.isQueueEmpty(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertTrue(isEmpty, "Queue should be empty after all dequeues");
    }

    function testDequeueOrder_EmptyQueue_Reverts() public {
        vm.prank(orderBookManager);
        vm.expectRevert("Queue is empty");
        orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
    }

    function testPeekOrder_EmptyQueue_ReturnsZero() public {
        OrderKey head = orderStorage.peekOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertEq(OrderKey.unwrap(head), bytes32(0), "Peek should return zero for empty queue");
    }

    function testIsQueueEmpty_EmptyQueue_ReturnsTrue() public {
        bool isEmpty = orderStorage.isQueueEmpty(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertTrue(isEmpty, "Empty queue should return true");
    }

    function testEnqueueOrder_UnauthorizedCaller_Reverts() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));

        vm.prank(unauthorized);
        vm.expectRevert("OrderStorage: only OrderBookManager");
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);
    }

    // ============ Layer 3: Global Order Tests ============

    function testStoreOrder_Success() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));
        OrderStruct.Order memory emptyOrder = _createEmptyOrder();
        OrderStruct.DBOrder memory order = OrderStruct.DBOrder({order: emptyOrder, next: key2});

        vm.prank(orderBookManager);
        orderStorage.storeOrder(key1, order);

        // Verify order is stored
        OrderStruct.DBOrder memory retrieved = orderStorage.getOrder(key1);
        assertEq(OrderKey.unwrap(retrieved.next), OrderKey.unwrap(key2), "Order next pointer should match");
    }

    function testGetOrder_NonExistent_ReturnsEmpty() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));

        OrderStruct.DBOrder memory retrieved = orderStorage.getOrder(key1);
        assertEq(OrderKey.unwrap(retrieved.next), bytes32(0), "Non-existent order should return empty");
    }

    function testDeleteOrder_Success() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));
        OrderStruct.Order memory emptyOrder = _createEmptyOrder();
        OrderStruct.DBOrder memory order = OrderStruct.DBOrder({order: emptyOrder, next: key2});

        vm.startPrank(orderBookManager);

        orderStorage.storeOrder(key1, order);
        orderStorage.deleteOrder(key1);

        vm.stopPrank();

        // Verify order is deleted
        OrderStruct.DBOrder memory retrieved = orderStorage.getOrder(key1);
        assertEq(OrderKey.unwrap(retrieved.next), bytes32(0), "Deleted order should return empty");
    }

    function testStoreOrder_UnauthorizedCaller_Reverts() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderStruct.Order memory emptyOrder = _createEmptyOrder();
        OrderStruct.DBOrder memory order = OrderStruct.DBOrder({order: emptyOrder, next: OrderKey.wrap(bytes32(0))});

        vm.prank(unauthorized);
        vm.expectRevert("OrderStorage: only OrderBookManager");
        orderStorage.storeOrder(key1, order);
    }

    // ============ Access Control Tests ============

    function testSetOrderBookManager_OnlyOwner() public {
        address newOrderBookManager = makeAddr("newOrderBookManager");

        vm.prank(unauthorized);
        vm.expectRevert();
        orderStorage.setOrderBookManager(newOrderBookManager);
    }

    function testSetOrderBookManager_CannotSetTwice() public {
        address newOrderBookManager = makeAddr("newOrderBookManager");

        vm.prank(owner);
        vm.expectRevert("OrderStorage: already set");
        orderStorage.setOrderBookManager(newOrderBookManager);
    }

    function testSetOrderBookManager_CannotSetZeroAddress() public {
        // Deploy new OrderStorage to test zero address
        OrderStorage impl = new OrderStorage();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        OrderStorageProxy proxy = new OrderStorageProxy(address(impl), initData);
        OrderStorage newStorage = OrderStorage(address(proxy));

        vm.prank(owner);
        vm.expectRevert("OrderStorage: invalid address");
        newStorage.setOrderBookManager(address(0));
    }

    // ============ Integration Tests ============

    function testFullWorkflow_InsertPriceEnqueueDequeue() public {
        OrderKey key1 = OrderKey.wrap(keccak256("order1"));
        OrderKey key2 = OrderKey.wrap(keccak256("order2"));

        vm.startPrank(orderBookManager);

        // Insert price level
        orderStorage.insertPrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        // Enqueue orders
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key1);
        orderStorage.enqueueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000, key2);

        // Store order data
        OrderStruct.Order memory emptyOrder = _createEmptyOrder();
        OrderStruct.DBOrder memory order1 = OrderStruct.DBOrder({order: emptyOrder, next: key2});
        OrderStruct.DBOrder memory order2 = OrderStruct.DBOrder({order: emptyOrder, next: OrderKey.wrap(bytes32(0))});
        orderStorage.storeOrder(key1, order1);
        orderStorage.storeOrder(key2, order2);

        // Dequeue all orders
        orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        orderStorage.dequeueOrder(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        // Remove price level
        orderStorage.removePrice(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);

        vm.stopPrank();

        // Verify price level is removed
        uint128 bestPrice = orderStorage.getBestPrice(EVENT_ID, OUTCOME_INDEX, true);
        assertEq(bestPrice, 0, "Price level should be removed");

        // Verify queue is empty
        bool isEmpty = orderStorage.isQueueEmpty(EVENT_ID, OUTCOME_INDEX, true, PRICE_8000);
        assertTrue(isEmpty, "Queue should be empty");
    }

    function testMultipleEvents_IsolatedStorage() public {
        uint256 event1 = 1;
        uint256 event2 = 2;

        vm.startPrank(orderBookManager);

        // Insert prices for different events
        orderStorage.insertPrice(event1, OUTCOME_INDEX, true, PRICE_8000);
        orderStorage.insertPrice(event2, OUTCOME_INDEX, true, PRICE_7000);

        vm.stopPrank();

        // Verify prices are isolated
        uint128 bestPrice1 = orderStorage.getBestPrice(event1, OUTCOME_INDEX, true);
        uint128 bestPrice2 = orderStorage.getBestPrice(event2, OUTCOME_INDEX, true);

        assertEq(bestPrice1, PRICE_8000, "Event 1 best price should be 8000");
        assertEq(bestPrice2, PRICE_7000, "Event 2 best price should be 7000");
    }
}
