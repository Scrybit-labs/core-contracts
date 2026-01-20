// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IOrderBookPod.sol";

/**
 * @title IOrderBookManager
 * @notice 订单簿管理器接口 - 负责 Pod 路由和订单管理
 */
interface IOrderBookManager {
    // ============ 事件 Events ============

    /// @notice Pod 添加到白名单事件
    event PodWhitelisted(address indexed pod);

    /// @notice Pod 从白名单移除事件
    event PodRemovedFromWhitelist(address indexed pod);

    /// @notice 事件注册到 Pod 事件
    event EventRegisteredToPod(uint256 indexed eventId, address indexed pod);

    // ============ Pod 管理功能 ============

    /**
     * @notice 注册事件到 Pod
     * @param pod Pod 地址
     * @param eventId 事件 ID
     * @param outcomeIds 结果 ID 列表
     */
    function registerEventToPod(
        IOrderBookPod pod,
        uint256 eventId,
        uint256[] calldata outcomeIds
    ) external;

    /**
     * @notice 添加 Pod 到白名单
     * @param pod Pod 地址
     */
    function addPodToWhitelist(IOrderBookPod pod) external;

    /**
     * @notice 从白名单移除 Pod
     * @param pod Pod 地址
     */
    function removePodFromWhitelist(IOrderBookPod pod) external;

    // ============ 订单管理功能 ============

    /**
     * @notice 下单
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @param side 订单方向(买/卖)
     * @param price 价格
     * @param amount 数量
     * @param tokenAddress Token 地址
     * @return orderId 订单 ID
     */
    function placeOrder(
        uint256 eventId,
        uint256 outcomeId,
        IOrderBookPod.OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external returns (uint256 orderId);

    /**
     * @notice 撤单
     * @param eventId 事件 ID
     * @param orderId 订单 ID
     */
    function cancelOrder(uint256 eventId, uint256 orderId) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IOrderBookPod pod) external view returns (bool);

    /**
     * @notice 获取事件对应的 Pod
     * @param eventId 事件 ID
     * @return pod Pod 地址
     */
    function getEventPod(uint256 eventId) external view returns (IOrderBookPod pod);
}
