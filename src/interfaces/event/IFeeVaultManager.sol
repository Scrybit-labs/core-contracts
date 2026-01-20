// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IFeeVaultPod.sol";

/**
 * @title IFeeVaultManager
 * @notice 手续费管理器接口 - 负责 Pod 路由和手续费管理
 * @dev Manager 层负责协调,Pod 层负责执行
 */
interface IFeeVaultManager {
    // ============ 事件 Events ============

    /// @notice Pod 添加到白名单事件
    event PodWhitelisted(address indexed pod);

    /// @notice Pod 从白名单移除事件
    event PodRemovedFromWhitelist(address indexed pod);

    /// @notice 事件注册到 Pod 事件
    event EventRegisteredToPod(uint256 indexed eventId, address indexed pod);

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param pod Pod 地址
     */
    function addPodToWhitelist(IFeeVaultPod pod) external;

    /**
     * @notice 从白名单移除 Pod
     * @param pod Pod 地址
     */
    function removePodFromWhitelist(IFeeVaultPod pod) external;

    /**
     * @notice 注册事件到 Pod
     * @param pod Pod 地址
     * @param eventId 事件 ID
     */
    function registerEventToPod(IFeeVaultPod pod, uint256 eventId) external;

    // ============ 手续费管理功能 ============

    /**
     * @notice 收取手续费(通过路由到对应 Pod)
     * @param eventId 事件 ID
     * @param token Token 地址
     * @param payer 支付者地址
     * @param amount 手续费金额
     * @param feeType 手续费类型
     */
    function collectFee(
        uint256 eventId,
        address token,
        address payer,
        uint256 amount,
        string calldata feeType
    ) external;

    /**
     * @notice 提取手续费
     * @param pod Pod 地址
     * @param token Token 地址
     * @param recipient 接收者地址
     * @param amount 提取金额
     */
    function withdrawFee(
        IFeeVaultPod pod,
        address token,
        address recipient,
        uint256 amount
    ) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IFeeVaultPod pod) external view returns (bool);

    /**
     * @notice 获取事件对应的 Pod
     * @param eventId 事件 ID
     * @return pod Pod 地址
     */
    function getEventPod(uint256 eventId) external view returns (IFeeVaultPod pod);

    /**
     * @notice 获取 Pod 的手续费余额
     * @param pod Pod 地址
     * @param token Token 地址
     * @return balance 手续费余额
     */
    function getPodFeeBalance(
        IFeeVaultPod pod,
        address token
    ) external view returns (uint256 balance);
}
