// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OrderKey, OrderStruct} from "../library/OrderStruct.sol";
import {RedBlackTreeLibrary, Price} from "../library/RedBlackTreeLibrary.sol";
import {IOrderStorage} from "../interfaces/core/IOrderStorage.sol";

/**
 * @title OrderStorage
 * @notice Core storage layer for the order book using a 3-layer architecture
 * @dev Layer 1: Price Trees (RedBlackTree) - O(log n) price level management
 *      Layer 2: Order Queues (Linked List) - O(1) FIFO order management
 *      Layer 3: Global Orders (Mapping) - O(1) order lookup
 */
contract OrderStorage is IOrderStorage {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    // ============ Storage ============

    // Layer 1: Price trees
    // eventId => outcomeIndex => side (0=buy, 1=sell) => Tree
    mapping(uint256 => mapping(uint8 => mapping(uint8 => RedBlackTreeLibrary.Tree))) internal priceTrees;

    // Layer 2: Order queues
    // eventId => outcomeIndex => side => price => OrderQueue
    mapping(uint256 => mapping(uint8 => mapping(uint8 => mapping(Price => OrderStruct.OrderQueue)))) internal orderQueues;

    // Layer 3: Global orders
    mapping(OrderKey => OrderStruct.DBOrder) internal orders;

    // ============ Price Tree Operations (Layer 1) ============

    /**
     * @notice Insert a new price level into the price tree
     * @dev Only inserts if the price doesn't already exist
     */
    function insertPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external {
        uint8 side = isBuy ? 0 : 1;
        RedBlackTreeLibrary.Tree storage tree = priceTrees[eventId][outcomeIndex][side];
        Price priceKey = Price.wrap(price);

        if (!tree.exists(priceKey)) {
            tree.insert(priceKey);
        }
    }

    /**
     * @notice Remove a price level from the price tree
     * @dev Only removes if the price exists
     */
    function removePrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external {
        uint8 side = isBuy ? 0 : 1;
        RedBlackTreeLibrary.Tree storage tree = priceTrees[eventId][outcomeIndex][side];
        Price priceKey = Price.wrap(price);

        if (tree.exists(priceKey)) {
            tree.remove(priceKey);
        }
    }

    /**
     * @notice Get the best price for a given side
     * @dev For buy orders, returns the highest bid (last in tree)
     *      For sell orders, returns the lowest ask (first in tree)
     * @return The best price, or 0 if no orders exist
     */
    function getBestPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy) external view returns (uint128) {
        uint8 side = isBuy ? 0 : 1;
        RedBlackTreeLibrary.Tree storage tree = priceTrees[eventId][outcomeIndex][side];

        Price bestPrice = isBuy ? tree.last() : tree.first();
        return Price.unwrap(bestPrice);
    }

    /**
     * @notice Get the next price level in the tree
     * @dev For buy orders, returns the next lower price (prev in tree)
     *      For sell orders, returns the next higher price (next in tree)
     * @return The next price level, or 0 if no more levels exist
     */
    function getNextPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 current)
        external
        view
        returns (uint128)
    {
        uint8 side = isBuy ? 0 : 1;
        RedBlackTreeLibrary.Tree storage tree = priceTrees[eventId][outcomeIndex][side];
        Price currentPrice = Price.wrap(current);

        Price nextPrice = isBuy ? tree.prev(currentPrice) : tree.next(currentPrice);
        return Price.unwrap(nextPrice);
    }

    // ============ Order Queue Operations (Layer 2) ============

    /**
     * @notice Enqueue an order at a specific price level (FIFO)
     * @dev Appends to the tail of the queue
     */
    function enqueueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price, OrderKey key) external {
        uint8 side = isBuy ? 0 : 1;
        Price priceKey = Price.wrap(price);
        OrderStruct.OrderQueue storage queue = orderQueues[eventId][outcomeIndex][side][priceKey];

        if (OrderKey.unwrap(queue.head) == bytes32(0)) {
            // Queue is empty, set both head and tail
            queue.head = key;
            queue.tail = key;
        } else {
            // Append to tail
            orders[queue.tail].next = key;
            queue.tail = key;
        }
    }

    /**
     * @notice Dequeue the first order from a price level queue
     * @dev Removes from the head of the queue
     * @return The dequeued order key
     */
    function dequeueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        returns (OrderKey)
    {
        uint8 side = isBuy ? 0 : 1;
        Price priceKey = Price.wrap(price);
        OrderStruct.OrderQueue storage queue = orderQueues[eventId][outcomeIndex][side][priceKey];

        require(OrderKey.unwrap(queue.head) != bytes32(0), "Queue is empty");

        OrderKey dequeuedKey = queue.head;
        OrderStruct.DBOrder storage dequeuedOrder = orders[dequeuedKey];

        if (OrderKey.unwrap(dequeuedOrder.next) == bytes32(0)) {
            // Last order in queue
            queue.head = OrderKey.wrap(bytes32(0));
            queue.tail = OrderKey.wrap(bytes32(0));
        } else {
            // Move head to next order
            queue.head = dequeuedOrder.next;
        }

        return dequeuedKey;
    }

    /**
     * @notice Peek at the first order in a price level queue without removing it
     * @return The first order key in the queue
     */
    function peekOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        view
        returns (OrderKey)
    {
        uint8 side = isBuy ? 0 : 1;
        Price priceKey = Price.wrap(price);
        OrderStruct.OrderQueue storage queue = orderQueues[eventId][outcomeIndex][side][priceKey];

        return queue.head;
    }

    /**
     * @notice Check if a price level queue is empty
     * @return True if the queue is empty, false otherwise
     */
    function isQueueEmpty(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        view
        returns (bool)
    {
        uint8 side = isBuy ? 0 : 1;
        Price priceKey = Price.wrap(price);
        OrderStruct.OrderQueue storage queue = orderQueues[eventId][outcomeIndex][side][priceKey];

        return OrderKey.unwrap(queue.head) == bytes32(0);
    }

    // ============ Global Order Operations (Layer 3) ============

    /**
     * @notice Store an order in the global order mapping
     */
    function storeOrder(OrderKey key, OrderStruct.DBOrder calldata order) external {
        orders[key] = order;
    }

    /**
     * @notice Get an order from the global order mapping
     * @return The order data
     */
    function getOrder(OrderKey key) external view returns (OrderStruct.DBOrder memory) {
        return orders[key];
    }

    /**
     * @notice Delete an order from the global order mapping
     */
    function deleteOrder(OrderKey key) external {
        delete orders[key];
    }
}
