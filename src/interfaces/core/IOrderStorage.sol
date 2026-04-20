// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OrderKey, OrderStruct} from "../../library/OrderStruct.sol";

/**
 * @title IOrderStorage
 * @notice Interface for the 3-layer order storage system
 * @dev Layer 1: Price Trees (RedBlackTree) - O(log n) price level management
 *      Layer 2: Order Queues (Linked List) - O(1) FIFO order management
 *      Layer 3: Global Orders (Mapping) - O(1) order lookup
 */
interface IOrderStorage {
    // ============ Price Tree Operations (Layer 1) ============

    /**
     * @notice Insert a new price level into the price tree
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level to insert
     */
    function insertPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;

    /**
     * @notice Remove a price level from the price tree
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level to remove
     */
    function removePrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;

    /**
     * @notice Get the best price for a given side
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders (returns highest bid), false for sell orders (returns lowest ask)
     * @return The best price, or 0 if no orders exist
     */
    function getBestPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy) external view returns (uint128);

    /**
     * @notice Get the next price level in the tree
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param current The current price level
     * @return The next price level, or 0 if no more levels exist
     */
    function getNextPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 current)
        external
        view
        returns (uint128);

    // ============ Order Queue Operations (Layer 2) ============

    /**
     * @notice Enqueue an order at a specific price level (FIFO)
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level
     * @param key The order key to enqueue
     */
    function enqueueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price, OrderKey key) external;

    /**
     * @notice Dequeue the first order from a price level queue
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level
     * @return The dequeued order key
     */
    function dequeueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        returns (OrderKey);

    /**
     * @notice Peek at the first order in a price level queue without removing it
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level
     * @return The first order key in the queue
     */
    function peekOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        view
        returns (OrderKey);

    /**
     * @notice Check if a price level queue is empty
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param isBuy True for buy orders, false for sell orders
     * @param price The price level
     * @return True if the queue is empty, false otherwise
     */
    function isQueueEmpty(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        external
        view
        returns (bool);

    // ============ Global Order Operations (Layer 3) ============

    /**
     * @notice Store an order in the global order mapping
     * @param key The order key
     * @param order The order data to store
     */
    function storeOrder(OrderKey key, OrderStruct.DBOrder calldata order) external;

    /**
     * @notice Get an order from the global order mapping
     * @param key The order key
     * @return The order data
     */
    function getOrder(OrderKey key) external view returns (OrderStruct.DBOrder memory);

    /**
     * @notice Delete an order from the global order mapping
     * @param key The order key
     */
    function deleteOrder(OrderKey key) external;
}
