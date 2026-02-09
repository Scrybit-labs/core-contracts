// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IEventManager
 * @notice 事件 Manager 接口 - 负责独立处理一组事件的执行单元
 * @dev 每个 EventManager 独立管理一组事件,实现事件隔离和横向扩展
 */
interface IEventManager {
    /// @notice 事件状态枚举
    enum EventStatus {
        Created, // 已创建
        Active, // 进行中(可下注)
        Settled, // 已结算
        Cancelled // 已取消
    }

    /// @notice 事件结果选项结构体
    struct Outcome {
        string name; // 结果名称
        string description; // 结果描述
    }

    /// @notice 事件信息结构体
    struct Event {
        uint256 eventId; // 事件 ID
        string title; // 事件标题
        string description; // 事件描述
        bytes32 eventType; // 事件类型标识 (用于预言机路由)
        uint256 deadline; // 下注截止时间戳
        uint256 settlementTime; // 预计结算时间戳
        EventStatus status; // 事件状态
        address creator; // 创建者地址
        Outcome[] outcomes; // 所有结果选项列表 (0-indexed)
        uint8 winningOutcomeIndex; // 获胜结果索引 (结算后设置)
        address usedOracleAdapter; // 实际使用的预言机适配器 (requestOracleResult 时记录)
    }

    // ============ 事件 Events ============

    /// @notice 事件创建事件
    event EventCreated(uint256 indexed eventId, string title, uint256 deadline, uint256 outcomeCount);

    /// @notice 事件状态变更事件
    event EventStatusChanged(uint256 indexed eventId, EventStatus oldStatus, EventStatus newStatus);

    /// @notice 事件结算事件
    event EventSettled(uint256 indexed eventId, uint8 winningOutcomeIndex, uint256 settlementTime);

    /// @notice 事件取消事件
    event EventCancelled(uint256 indexed eventId, string reason);

    /// @notice 预言机结果接收事件
    event OracleResultReceived(uint256 indexed eventId, uint8 winningOutcomeIndex, address indexed oracle);

    /// @notice 事件创建者添加事件
    event EventCreatorAdded(address indexed creator);

    /// @notice 事件创建者移除事件
    event EventCreatorRemoved(address indexed creator);

    /// @notice 事件类型对应预言机适配器设置
    event EventTypeOracleSet(bytes32 indexed eventType, address indexed oracleAdapter);

    /// @notice 事件类型对应预言机适配器移除
    event EventTypeOracleRemoved(bytes32 indexed eventType);

    /// @notice 事件使用的预言机适配器 (requestOracleResult 时触发)
    event OracleAdapterUsed(uint256 indexed eventId, address indexed oracleAdapter, bytes32 indexed eventType);

    /// @notice 预言机适配器授权
    event OracleAdapterAuthorized(address indexed oracleAdapter);

    /// @notice 预言机适配器撤销授权
    event OracleAdapterDeauthorized(address indexed oracleAdapter);

    /// @notice 默认预言机适配器更新
    event OracleAdapterUpdated(address indexed newAdapter);

    // ============ 核心功能 Functions ============

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _defaultOracleAdapter 默认 OracleAdapter 合约地址
     */
    function initialize(address initialOwner, address _defaultOracleAdapter) external;

    /**
     * @notice 暂停合约
     */
    function pause() external;

    /**
     * @notice 恢复合约
     */
    function unpause() external;

    /**
     * @notice 创建事件 (Event creator direct call)
     * @param title 事件标题
     * @param description 事件描述
     * @param deadline 下注截止时间
     * @param settlementTime 预计结算时间
     * @param outcomes 结果选项数组
     * @param eventType 事件类型标识
     * @return eventId 生成的事件 ID
     */
    function createEvent(
        string calldata title,
        string calldata description,
        uint256 deadline,
        uint256 settlementTime,
        Outcome[] calldata outcomes,
        bytes32 eventType
    ) external returns (uint256 eventId);

    /**
     * @notice 请求预言机结果 (Event creator direct call)
     * @param eventId 事件 ID
     * @return requestId 预言机请求 ID
     */
    function requestOracleResult(uint256 eventId) external returns (bytes32 requestId);

    /**
     * @notice 更新事件状态
     * @param eventId 事件 ID
     * @param newStatus 新状态
     */
    function updateEventStatus(uint256 eventId, EventStatus newStatus) external;

    /**
     * @notice 接收预言机结果并结算事件
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据
     */
    function settleEvent(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof) external;

    /**
     * @notice 取消事件
     * @param eventId 事件 ID
     * @param reason 取消原因
     */
    function cancelEvent(uint256 eventId, string calldata reason) external;

    /**
     * @notice 添加事件创建者
     * @param creator 创建者地址
     */
    function addEventCreator(address creator) external;

    /**
     * @notice 移除事件创建者
     * @param creator 创建者地址
     */
    function removeEventCreator(address creator) external;

    /**
     * @notice 更新 OrderBookManager 地址
     * @param _orderBookManager 新地址
     */
    function setOrderBookManager(address _orderBookManager) external;

    /**
     * @notice 设置默认 OracleAdapter 地址
     * @param _defaultOracleAdapter 默认 OracleAdapter 地址
     */
    function setDefaultOracleAdapter(address _defaultOracleAdapter) external;

    /**
     * @notice 设置事件类型对应的 OracleAdapter
     * @param eventType 事件类型标识 (例如 keccak256("SPORTS"))
     * @param oracleAdapter OracleAdapter 地址
     */
    function setEventTypeOracleAdapter(bytes32 eventType, address oracleAdapter) external;

    /**
     * @notice 移除事件类型对应的 OracleAdapter (回退到默认适配器)
     * @param eventType 事件类型标识
     */
    function removeEventTypeOracleAdapter(bytes32 eventType) external;

    /**
     * @notice 获取事件类型对应的 OracleAdapter
     * @param eventType 事件类型标识
     * @return OracleAdapter 地址 (未设置则为 address(0))
     */
    function getEventTypeOracleAdapter(bytes32 eventType) external view returns (address);

    /**
     * @notice 获取事件将使用的 OracleAdapter (带路由逻辑)
     * @param eventId 事件 ID
     * @return OracleAdapter 地址 (按类型映射或默认适配器)
     */
    function getOracleAdapterForEvent(uint256 eventId) external view returns (address);

    /**
     * @notice 获取事件实际使用的 OracleAdapter
     * @param eventId 事件 ID
     * @return OracleAdapter 地址 (未请求结果则为 address(0))
     */
    function getEventOracleAdapter(uint256 eventId) external view returns (address);

    /**
     * @notice 添加授权预言机适配器
     * @param oracleAdapter 预言机适配器地址
     */
    function addAuthorizedOracleAdapter(address oracleAdapter) external;

    /**
     * @notice 移除授权预言机适配器
     * @param oracleAdapter 预言机适配器地址
     */
    function removeAuthorizedOracleAdapter(address oracleAdapter) external;

    // ============ 查询功能 View Functions ============

    function getEvents() external view returns (Event[] memory);

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

    function getOutcomes(uint256 eventId) external view returns (Outcome[] memory);

    /**
     * @notice 获取事件结果选项
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引 (0-based)
     * @return outcome 结果选项信息
     */
    function getOutcome(uint256 eventId, uint8 outcomeIndex) external view returns (Outcome memory);

    /**
     * @notice 获取 OrderBookManager 地址
     */
    function orderBookManager() external view returns (address);

    /**
     * @notice 获取默认 OracleAdapter 地址
     */
    function defaultOracleAdapter() external view returns (address);

    /**
     * @notice 查询是否为事件创建者
     */
    function isEventCreator(address creator) external view returns (bool);

    /**
     * @notice 获取下一个事件 ID
     */
    function nextEventId() external view returns (uint256);

    /**
     * @notice 获取事件对应的预言机请求 ID
     */
    function eventOracleRequests(uint256 eventId) external view returns (bytes32);

    /**
     * @notice 查询预言机适配器是否授权
     */
    function authorizedOracleAdapters(address oracleAdapter) external view returns (bool);
}
