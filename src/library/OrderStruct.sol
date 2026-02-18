// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Price} from "./RedBlackTreeLibrary.sol";

/// @notice 订单唯一标识符类型（bytes32 包装类型）
/// @dev 通过 hash(Order) 生成，用于唯一标识一个订单
type OrderKey is bytes32;

/**
 * @title OrderStruct - 订单库
 * @notice 定义订单相关的数据结构、常量和工具函数
 * @dev 包含订单的完整定义、哈希计算和验证逻辑
 */
library OrderStruct {
    /// @notice 订单方向枚举
    enum Side {
        Sell, // 卖单（挂单出售）- 原 List
        Buy // 买单（出价购买）- 原 Bid
    }

    /// @notice 订单状态枚举
    enum OrderStatus {
        Pending, // 待成交
        Partial, // 部分成交
        Filled, // 完全成交
        Cancelled // 已取消
    }

    /// @notice 订单结构（统一版本）
    /// @dev 包含所有必要字段，支持完整的订单生命周期管理
    struct Order {
        uint256 orderId; // 订单 ID（用于 OrderBookManager）
        uint256 eventId; // 事件 ID
        address maker; // 订单创建者地址
        uint8 outcomeIndex; // 结果索引
        Side side; // 订单方向
        uint128 price; // 订单价格
        uint128 amount; // 订单数量
        uint128 filledAmount; // 已成交数量
        uint128 remainingAmount; // 剩余数量
        OrderStatus status; // 订单状态
        uint64 timestamp; // 创建时间戳
        uint64 expiry; // 过期时间（0 表示永不过期）
        uint64 salt; // 随机盐值（防止订单重复）
        address tokenAddress; // Token 地址
    }

    /// @notice 数据库订单结构（用于链表存储）
    /// @dev 包含订单数据和链表指针
    struct DBOrder {
        Order order; // 订单数据
        OrderKey next; // 下一个订单的 OrderKey（链表指针）
    }

    /// @notice 订单队列结构
    /// @dev 用于存储同一价格的订单（FIFO 队列）
    struct OrderQueue {
        OrderKey head; // 队列头部（最早的订单）
        OrderKey tail; // 队列尾部（最新的订单）
    }

    /// @notice 订单匹配详情结构
    /// @dev 用于 matchOrders 函数
    struct MatchDetail {
        OrderStruct.Order sellOrder; // 卖单
        OrderStruct.Order buyOrder; // 买单
    }

    /// @notice 哨兵值（空 OrderKey）
    /// @dev 用于标识链表结束或空值
    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);

    /// @notice Order 结构的 EIP-712 类型哈希
    /// @dev 用于链下签名验证，只包含核心订单字段（不包括运行时状态）
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 eventId,address maker,uint8 outcomeIndex,uint8 side,uint128 price,uint128 amount,uint64 expiry,uint64 salt)"
    );

    /**
     * @notice 计算 Order 的哈希值（生成 OrderKey）
     * @dev 使用 EIP-712 标准计算订单的唯一标识符
     *      只包含核心订单字段，不包括运行时状态（orderId, filledAmount, status等）
     * @param order 订单结构
     * @return OrderKey 订单的唯一标识符
     */
    function hash(Order memory order) internal pure returns (OrderKey) {
        return OrderKey.wrap(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.eventId,
                    order.maker,
                    order.outcomeIndex,
                    order.side,
                    order.price,
                    order.amount,
                    order.expiry,
                    order.salt
                )
            )
        );
    }

    /**
     * @notice 检查 OrderKey 是否为哨兵值
     * @dev 哨兵值用于标识链表结束或空值
     * @param orderKey 要检查的 OrderKey
     * @return 如果是哨兵值返回 true，否则返回 false
     */
    function isSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) == OrderKey.unwrap(ORDERKEY_SENTINEL);
    }

    /**
     * @notice 检查 OrderKey 是否不是哨兵值
     * @dev 用于链表遍历时判断是否到达结尾
     * @param orderKey 要检查的 OrderKey
     * @return 如果不是哨兵值返回 true，否则返回 false
     */
    function isNotSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) != OrderKey.unwrap(ORDERKEY_SENTINEL);
    }
}
