// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IEventPod.sol";

/**
 * @title IEventManager
 * @notice 事件管理器接口 - 负责事件生命周期管理和 Pod 路由
 * @dev Manager 层负责协调,Pod 层负责执行
 */
interface IEventManager {
    // ============ 事件 Events ============

    /// @notice Pod 添加到白名单事件
    event PodWhitelisted(address indexed pod);

    /// @notice Pod 从白名单移除事件
    event PodRemovedFromWhitelist(address indexed pod);

    /// @notice 预言机注册事件
    event OracleRegistered(address indexed oracle);

    /// @notice 预言机移除事件
    event OracleRemoved(address indexed oracle);

    /// @notice 事件创建事件
    event EventCreatedByManager(
        uint256 indexed eventId,
        address indexed pod,
        address indexed creator,
        string title
    );

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param pod EventPod 合约地址
     */
    function addPodToWhitelist(IEventPod pod) external;

    /**
     * @notice 从白名单移除 Pod
     * @param pod EventPod 合约地址
     */
    function removePodFromWhitelist(IEventPod pod) external;

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod EventPod 合约地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IEventPod pod) external view returns (bool);

    // ============ 预言机管理功能 ============

    /**
     * @notice 注册预言机
     * @param oracle 预言机地址
     */
    function registerOracle(address oracle) external;

    /**
     * @notice 移除预言机
     * @param oracle 预言机地址
     */
    function removeOracle(address oracle) external;

    /**
     * @notice 检查预言机是否已授权
     * @param oracle 预言机地址
     * @return isAuthorized 是否已授权
     */
    function isOracleAuthorized(address oracle) external view returns (bool);

    // ============ 事件创建功能 ============

    /**
     * @notice 创建事件并分配到 Pod
     * @param title 事件标题
     * @param description 事件描述
     * @param deadline 下注截止时间
     * @param settlementTime 预计结算时间
     * @param outcomeNames 结果选项名称列表
     * @param outcomeDescriptions 结果选项描述列表
     * @return eventId 创建的事件 ID
     * @return assignedPod 分配的 Pod 地址
     */
    function createEvent(
        string calldata title,
        string calldata description,
        uint256 deadline,
        uint256 settlementTime,
        string[] calldata outcomeNames,
        string[] calldata outcomeDescriptions
    ) external returns (uint256 eventId, IEventPod assignedPod);

    // ============ 查询功能 ============

    /**
     * @notice 获取事件所属的 Pod
     * @param eventId 事件 ID
     * @return pod EventPod 合约地址
     */
    function getEventPod(uint256 eventId) external view returns (IEventPod);

    /**
     * @notice 获取下一个事件 ID
     * @return nextId 下一个事件 ID
     */
    function getNextEventId() external view returns (uint256);

    /**
     * @notice 获取所有白名单 Pod 数量
     * @return count Pod 数量
     */
    function getWhitelistedPodCount() external view returns (uint256);
}
