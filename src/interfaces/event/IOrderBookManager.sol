// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IOrderBookPod.sol";

/**
 * @title IOrderBookManager
 * @notice 订单簿管理器接口 - 负责 Pod 路由和订单管理
 */
interface IOrderBookManager {
    // ============ 事件 Events ============

    /// @notice OrderBookPod 部署事件
    event OrderBookPodDeployed(uint256 indexed vendorId, address indexed orderBookPod);

    // ============ Pod 部署功能 ============

    /**
     * @notice 部署 OrderBookPod (仅 Factory 可调用)
     * @param vendorId Vendor ID
     * @param vendorAddress Vendor 地址
     * @param eventPod EventPod 地址
     * @param fundingPod FundingPod 地址
     * @param feeVaultPod FeeVaultPod 地址
     * @return orderBookPod OrderBookPod 地址
     */
    function deployOrderBookPod(
        uint256 vendorId,
        address vendorAddress,
        address eventPod,
        address fundingPod,
        address feeVaultPod
    ) external returns (address orderBookPod);

    /**
     * @notice 获取 vendor 的 OrderBookPod 地址
     * @param vendorId Vendor ID
     * @return orderBookPod OrderBookPod 地址
     */
    function getVendorOrderBookPod(uint256 vendorId) external view returns (address);

    /**
     * @notice 设置 PodDeployer 地址
     * @param _podDeployer PodDeployer 合约地址
     */
    function setPodDeployer(address _podDeployer) external;

    // ============ Pod 管理功能 ============

    // ============ 订单管理功能 ============

    /**
     * @notice 下单
     * @param vendorId Vendor ID
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @param side 订单方向(买/卖)
     * @param price 价格
     * @param amount 数量
     * @param tokenAddress Token 地址
     * @return orderId 订单 ID
     */
    function placeOrder(
        uint256 vendorId,
        uint256 eventId,
        uint256 outcomeId,
        IOrderBookPod.OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external returns (uint256 orderId);

    /**
     * @notice 撤单
     * @param vendorId Vendor ID
     * @param eventId 事件 ID
     * @param orderId 订单 ID
     */
    function cancelOrder(uint256 vendorId, uint256 eventId, uint256 orderId) external;

    // ============ 查询功能 View Functions ============
}
