// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IEventPod
 * @notice 事件 Pod 接口 - 负责独立处理一组事件的执行单元
 * @dev 每个 EventPod 独立管理一组事件,实现事件隔离和横向扩展
 */
interface IEventPod {
    /// @notice 事件状态枚举
    enum EventStatus {
        Created,    // 已创建
        Active,     // 进行中(可下注)
        Settled,    // 已结算
        Cancelled   // 已取消
    }

    /// @notice 事件结果选项结构体
    struct Outcome {
        uint256 outcomeId;      // 结果 ID
        string name;            // 结果名称
        string description;     // 结果描述
    }

    /// @notice 事件信息结构体
    struct Event {
        uint256 eventId;            // 事件 ID
        string title;               // 事件标题
        string description;         // 事件描述
        uint256 deadline;           // 下注截止时间戳
        uint256 settlementTime;     // 预计结算时间戳
        EventStatus status;         // 事件状态
        address creator;            // 创建者地址
        uint256[] outcomeIds;       // 所有结果选项 ID 列表
        uint256 winningOutcomeId;   // 获胜结果 ID (结算后设置)
    }

    // ============ 事件 Events ============

    /// @notice 事件创建事件
    event EventCreated(
        uint256 indexed eventId,
        string title,
        uint256 deadline,
        uint256[] outcomeIds
    );

    /// @notice 事件状态变更事件
    event EventStatusChanged(
        uint256 indexed eventId,
        EventStatus oldStatus,
        EventStatus newStatus
    );

    /// @notice 事件结算事件
    event EventSettled(
        uint256 indexed eventId,
        uint256 winningOutcomeId,
        uint256 settlementTime
    );

    /// @notice 事件取消事件
    event EventCancelled(
        uint256 indexed eventId,
        string reason
    );

    /// @notice 预言机结果接收事件
    event OracleResultReceived(
        uint256 indexed eventId,
        uint256 winningOutcomeId,
        address indexed oracle
    );

    // ============ 核心功能 Functions ============

    /**
     * @notice 添加事件到 Pod
     * @param eventId 事件 ID
     * @param title 事件标题
     * @param description 事件描述
     * @param deadline 下注截止时间
     * @param settlementTime 预计结算时间
     * @param creator 创建者地址
     * @param outcomeIds 结果选项 ID 列表
     * @param outcomeNames 结果选项名称列表
     * @param outcomeDescriptions 结果选项描述列表
     */
    function addEvent(
        uint256 eventId,
        string calldata title,
        string calldata description,
        uint256 deadline,
        uint256 settlementTime,
        address creator,
        uint256[] calldata outcomeIds,
        string[] calldata outcomeNames,
        string[] calldata outcomeDescriptions
    ) external;

    /**
     * @notice 更新事件状态
     * @param eventId 事件 ID
     * @param newStatus 新状态
     */
    function updateEventStatus(uint256 eventId, EventStatus newStatus) external;

    /**
     * @notice 接收预言机结果并结算事件
     * @param eventId 事件 ID
     * @param winningOutcomeId 获胜结果 ID
     * @param proof 预言机证明数据
     */
    function settleEvent(
        uint256 eventId,
        uint256 winningOutcomeId,
        bytes calldata proof
    ) external;

    /**
     * @notice 取消事件
     * @param eventId 事件 ID
     * @param reason 取消原因
     */
    function cancelEvent(uint256 eventId, string calldata reason) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取事件详情
     * @param eventId 事件 ID
     * @return event 事件信息
     */
    function getEvent(uint256 eventId) external view returns (Event memory);

    /**
     * @notice 获取事件状态
     * @param eventId 事件 ID
     * @return status 事件状态
     */
    function getEventStatus(uint256 eventId) external view returns (EventStatus);

    /**
     * @notice 获取事件结果选项
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @return outcome 结果选项信息
     */
    function getOutcome(uint256 eventId, uint256 outcomeId) external view returns (Outcome memory);

    /**
     * @notice 列出所有活跃事件 ID
     * @return eventIds 活跃事件 ID 数组
     */
    function listActiveEvents() external view returns (uint256[] memory);
}
