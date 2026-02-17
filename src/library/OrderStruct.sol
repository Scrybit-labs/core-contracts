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
        List, // 卖单（挂单出售）
        Bid // 买单（出价购买）
    }

    /// @notice 订单结构
    /// @dev 包含订单的所有必要信息
    ///需要补充订单结构的其他字段
    struct Order {
        Side side; // 订单方向（List 或 Bid）
        address maker; // 订单创建者地址
        uint64 expiry; // 过期时间（0 表示永不过期）
        uint64 salt; // 随机盐值（防止订单重复）
        Price price; // 订单价格
        uint96 amount; // 订单数量
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
    /// @dev 用于链下签名验证，包含嵌套的 Asset 类型
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint8 side,address maker,uint64 expiry,uint64 salt,uint128 price,uint96 amount)"
    );

    /**
     * @notice 计算 Order 的哈希值（生成 OrderKey）
     * @dev 使用 EIP-712 标准计算订单的唯一标识符
     *      哈希包含订单的所有字段，确保唯一性
     * @param order 订单结构
     * @return OrderKey 订单的唯一标识符
     */
    function hash(Order memory order) internal pure returns (OrderKey) {
        return OrderKey.wrap(
            keccak256(
                abi.encode(ORDER_TYPEHASH, order.side, order.maker, order.expiry, order.salt, order.price, order.amount)
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
