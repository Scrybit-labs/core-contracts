// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/core/IEventManager.sol";
import "../interfaces/core/IOrderBookManager.sol";
import "../interfaces/oracle/IOracle.sol";

/**
 * @title EventManager
 * @notice 事件 Manager - 负责独立处理一组事件的执行单元
 * @dev 每个 EventManager 独立管理一组事件,实现事件隔离和横向扩展
 */
contract EventManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IEventManager,
    IOracleConsumer
{
    // ============ Modifiers ============

    /// forge-lint: disable-next-item(unwrapped-modifier-logic)
    /// @notice 仅事件创建者或所有者可调用
    modifier onlyEventCreator() {
        require(msg.sender == owner() || isEventCreator[msg.sender], "EventManager: not authorized");
        _;
    }

    /// forge-lint: disable-next-item(unwrapped-modifier-logic)
    /// @notice 仅授权的预言机适配器可调用
    modifier onlyAuthorizedOracleAdapter() {
        require(authorizedOracleAdapters[msg.sender], "EventManager: not authorized oracle adapter");
        _;
    }

    /// forge-lint: disable-next-item(unwrapped-modifier-logic)
    /// @notice 事件必须存在
    modifier eventMustExist(uint256 eventId) {
        require(eventId < events.length, "EventManager: event does not exist");
        _;
    }

    /// forge-lint: disable-next-item(unwrapped-modifier-logic)
    /// @notice 仅事件创建者或所有者可操作对应事件
    modifier onlyEventCreatorOrOwner(uint256 eventId) {
        require(msg.sender == owner() || events[eventId].creator == msg.sender, "EventManager: not event creator");
        _;
    }

    // ============ 状态变量 State Variables ============

    /// @notice OrderBookManager 合约地址(用于触发结算)
    address public orderBookManager;

    /// @notice 默认 OracleAdapter 合约地址(用于发起新请求)
    address public defaultOracleAdapter;

    /// @notice 事件存储数组
    Event[] internal events;

    /// @notice 事件创建者白名单
    mapping(address => bool) public isEventCreator;

    /// @notice Event type to oracle adapter mapping
    mapping(bytes32 => address) public eventTypeToOracleAdapter;

    /// @notice Authorized oracle adapters for callbacks
    mapping(address => bool) public authorizedOracleAdapters;

    /// @notice Event oracle request tracking: eventId => requestId
    mapping(uint256 => bytes32) public eventOracleRequests;

    // ===== Upgradeable storage gap =====
    uint256[50] private _gap;

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _defaultOracleAdapter 默认 OracleAdapter 合约地址
     */
    function initialize(address initialOwner, address _defaultOracleAdapter) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        defaultOracleAdapter = _defaultOracleAdapter;
        if (_defaultOracleAdapter != address(0)) {
            authorizedOracleAdapters[_defaultOracleAdapter] = true;
        }

        // Reserve eventId 0 as a dummy placeholder so real events start from 1.
        if (events.length == 0) {
            Event storage dummyEvent = events.push();
            dummyEvent.eventId = 0;
            dummyEvent.title = "DUMMY_EVENT";
            dummyEvent.description = "Placeholder event - do not use";
            dummyEvent.status = EventStatus.Cancelled;
            dummyEvent.creator = address(0);
            dummyEvent.eventType = bytes32(0);
            dummyEvent.winningOutcomeIndex = 0;
            dummyEvent.usedOracleAdapter = address(0);
        }

        // Owner is an event creator by default
        isEventCreator[initialOwner] = true;
    }

    // ============ 核心功能 Functions ============

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
    ) external onlyEventCreator nonReentrant returns (uint256 eventId) {
        // Validate parameters
        require(bytes(title).length > 0, "EventManager: empty title");
        require(deadline > block.timestamp, "EventManager: deadline must be in future");
        require(settlementTime > deadline, "EventManager: settlementTime must be after deadline");
        require(outcomes.length >= 2, "EventManager: at least 2 outcomes required");
        require(outcomes.length <= 32, "EventManager: max 32 outcomes");
        require(eventType != bytes32(0), "EventManager: event type cannot be empty");

        // Generate event ID
        eventId = events.length;

        // Create event
        Event memory newEvent;
        newEvent.eventId = eventId;
        newEvent.title = title;
        newEvent.description = description;
        newEvent.deadline = deadline;
        newEvent.settlementTime = settlementTime;
        newEvent.status = EventStatus.Created;
        newEvent.creator = msg.sender;
        newEvent.winningOutcomeIndex = 0;
        newEvent.eventType = eventType;
        newEvent.usedOracleAdapter = address(0);
        newEvent.outcomes = outcomes;
        events.push(newEvent);

        emit EventCreated(eventId, title, deadline, outcomes.length);
    }

    /**
     * @notice 请求预言机结果 (Event creator direct call)
     * @param eventId 事件 ID
     * @return requestId 预言机请求 ID
     * @dev TODO: Implement oracle submission logic
     */
    function requestOracleResult(
        uint256 eventId
    ) external eventMustExist(eventId) onlyEventCreatorOrOwner(eventId) nonReentrant returns (bytes32 requestId) {
        Event storage evt = events[eventId];
        require(evt.status == EventStatus.Active, "EventManager: event not active");
        require(block.timestamp >= evt.deadline, "EventManager: deadline not reached");

        require(evt.usedOracleAdapter == address(0), "EventManager: oracle adapter already recorded");

        address targetOracleAdapter = _getOracleAdapterForEventType(evt.eventType);
        require(targetOracleAdapter != address(0), "EventManager: no oracle adapter configured");

        evt.usedOracleAdapter = targetOracleAdapter;

        requestId = IOracle(targetOracleAdapter).requestEventResult(eventId, evt.description);

        // Store request mapping
        eventOracleRequests[eventId] = requestId;

        emit OracleAdapterUsed(eventId, targetOracleAdapter, evt.eventType);
    }

    /**
     * @notice 获取事件类型对应的 OracleAdapter (带默认回退)
     * @param eventType 事件类型标识
     * @return OracleAdapter 地址
     */
    function _getOracleAdapterForEventType(bytes32 eventType) internal view returns (address) {
        address typeSpecificOracle = eventTypeToOracleAdapter[eventType];
        if (typeSpecificOracle != address(0)) {
            return typeSpecificOracle;
        }

        return defaultOracleAdapter;
    }

    /**
     * @notice 获取事件将使用的 OracleAdapter (带路由逻辑)
     * @param eventId 事件 ID
     * @return OracleAdapter 地址
     */
    function getOracleAdapterForEvent(uint256 eventId) external view eventMustExist(eventId) returns (address) {
        Event storage evt = events[eventId];
        return _getOracleAdapterForEventType(evt.eventType);
    }

    /**
     * @notice 获取事件实际使用的 OracleAdapter
     * @param eventId 事件 ID
     * @return OracleAdapter 地址 (未请求结果则为 address(0))
     */
    function getEventOracleAdapter(uint256 eventId) external view eventMustExist(eventId) returns (address) {
        return events[eventId].usedOracleAdapter;
    }

    /**
     * @notice 更新事件状态
     * @param eventId 事件 ID
     * @param newStatus 新状态
     */
    function updateEventStatus(
        uint256 eventId,
        EventStatus newStatus
    ) external eventMustExist(eventId) onlyEventCreatorOrOwner(eventId) nonReentrant {
        Event storage evt = events[eventId];
        EventStatus oldStatus = evt.status;

        // 状态机验证
        require(_isValidStatusTransition(oldStatus, newStatus), "EventManager: invalid status transition");

        evt.status = newStatus;

        if (newStatus == EventStatus.Active) {
            require(orderBookManager != address(0), "EventManager: orderBookManager not set");
            IOrderBookManager(orderBookManager).registerEvent(eventId, uint8(evt.outcomes.length));
        } else if (newStatus == EventStatus.Cancelled) {
            require(orderBookManager != address(0), "EventManager: orderBookManager not set");
            IOrderBookManager(orderBookManager).deactivateEvent(eventId);
        }

        emit EventStatusChanged(eventId, oldStatus, newStatus);
    }

    /**
     * @notice 接收预言机结果并结算事件 (实现 IOracleConsumer 接口)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据 (可为空)
     */
    function fulfillResult(
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyAuthorizedOracleAdapter eventMustExist(eventId) nonReentrant {
        _settleEvent(eventId, winningOutcomeIndex, proof);
    }

    /**
     * @notice 结算事件 (实现 IEventManager 接口,兼容层)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据 (可为空)
     */
    function settleEvent(
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyAuthorizedOracleAdapter eventMustExist(eventId) nonReentrant {
        _settleEvent(eventId, winningOutcomeIndex, proof);
    }

    /**
     * @notice 内部函数: 结算事件逻辑
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据 (可为空,当前不做验证)
     */
    function _settleEvent(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof) internal {
        Event storage evt = events[eventId];

        require(evt.status == EventStatus.Active, "EventManager: event not active");
        require(block.timestamp >= evt.settlementTime, "EventManager: settlement time not reached");

        // 验证 winningOutcomeIndex 是否有效
        require(winningOutcomeIndex < uint8(evt.outcomes.length), "EventManager: invalid winning outcome index");
        proof;

        // 更新事件状态
        evt.status = EventStatus.Settled;
        evt.winningOutcomeIndex = winningOutcomeIndex;

        require(orderBookManager != address(0), "EventManager: orderBookManager not set");
        IOrderBookManager orderBookManagerInstance = IOrderBookManager(orderBookManager);
        orderBookManagerInstance.settleEvent(eventId, winningOutcomeIndex);

        emit EventSettled(eventId, winningOutcomeIndex, block.timestamp);
        emit OracleResultReceived(eventId, winningOutcomeIndex, msg.sender);
    }

    /**
     * @notice 取消事件
     * @param eventId 事件 ID
     * @param reason 取消原因
     */
    function cancelEvent(
        uint256 eventId,
        string calldata reason
    ) external eventMustExist(eventId) onlyEventCreatorOrOwner(eventId) nonReentrant {
        Event storage evt = events[eventId];

        require(
            evt.status == EventStatus.Created || evt.status == EventStatus.Active,
            "EventManager: cannot cancel settled event"
        );

        EventStatus oldStatus = evt.status;
        evt.status = EventStatus.Cancelled;

        if (oldStatus == EventStatus.Active) {
            require(orderBookManager != address(0), "EventManager: orderBookManager not set");
            IOrderBookManager(orderBookManager).deactivateEvent(eventId);
        }

        emit EventCancelled(eventId, reason);
    }

    // ============ 内部函数 Internal Functions ===========


    /**
     * @notice 验证状态转换是否合法
     * @param oldStatus 旧状态
     * @param newStatus 新状态
     * @return valid 是否合法
     */
    function _isValidStatusTransition(EventStatus oldStatus, EventStatus newStatus) internal pure returns (bool) {
        // 状态机规则:
        // Created -> Active
        // Active -> Cancelled
        // Settled/Cancelled -> (终态,不可转换)

        if (oldStatus == EventStatus.Created) {
            return newStatus == EventStatus.Active;
        } else if (oldStatus == EventStatus.Active) {
            return newStatus == EventStatus.Cancelled;
        }

        return false; // Settled 和 Cancelled 是终态
    }

    // ============ 查询功能 View Functions ============

    function getEvents() external view returns (Event[] memory _events) {
        _events = events;
    }

    /**
     * @notice 获取下一个事件 ID（即当前事件总数）
     * @return 下一个事件 ID
     */
    function nextEventId() external view returns (uint256) {
        return events.length;
    }

    /**
     * @notice 获取事件详情
     * @param eventId 事件 ID
     * @return event 事件信息
     */
    function getEvent(uint256 eventId) external view eventMustExist(eventId) returns (Event memory) {
        return events[eventId];
    }

    /**
     * @notice 获取事件状态
     * @param eventId 事件 ID
     * @return status 事件状态
     */
    function getEventStatus(uint256 eventId) external view eventMustExist(eventId) returns (EventStatus) {
        return events[eventId].status;
    }

    function getOutcomes(uint256 eventId) external view eventMustExist(eventId) returns (Outcome[] memory) {
        Event storage evt = events[eventId];
        return evt.outcomes;
    }

    /**
     * @notice 获取事件结果选项
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引 (0-based)
     * @return outcome 结果选项信息
     */
    function getOutcome(
        uint256 eventId,
        uint8 outcomeIndex
    ) external view eventMustExist(eventId) returns (Outcome memory) {
        Event storage evt = events[eventId];
        require(outcomeIndex < uint8(evt.outcomes.length), "EventManager: outcome index out of bounds");
        return evt.outcomes[outcomeIndex];
    }

    /**
     * @notice 列出所有活跃事件 ID
     * @return eventIds 活跃事件 ID 数组
     */

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 添加事件创建者
     * @param creator 创建者地址
     */
    function addEventCreator(address creator) external onlyOwner nonReentrant {
        require(creator != address(0), "EventManager: invalid address");
        isEventCreator[creator] = true;
        emit EventCreatorAdded(creator);
    }

    /**
     * @notice 移除事件创建者
     * @param creator 创建者地址
     */
    function removeEventCreator(address creator) external onlyOwner nonReentrant {
        require(isEventCreator[creator], "EventManager: not an event creator");
        isEventCreator[creator] = false;
        emit EventCreatorRemoved(creator);
    }

    /**
     * @notice 更新 OrderBookManager 地址
     * @param _orderBookManager 新地址
     */
    function setOrderBookManager(address _orderBookManager) external onlyOwner nonReentrant {
        require(orderBookManager == address(0), "EventManager: already set");
        require(_orderBookManager != address(0), "EventManager: invalid address");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 设置默认 OracleAdapter 地址
     * @param _defaultOracleAdapter 默认 OracleAdapter 地址
     */
    function setDefaultOracleAdapter(address _defaultOracleAdapter) external onlyOwner nonReentrant {
        require(_defaultOracleAdapter != address(0), "EventManager: invalid address");
        defaultOracleAdapter = _defaultOracleAdapter;
        authorizedOracleAdapters[_defaultOracleAdapter] = true;
        emit OracleAdapterUpdated(_defaultOracleAdapter);
    }

    /**
     * @notice 设置事件类型对应的 OracleAdapter
     * @param eventType 事件类型标识
     * @param _oracleAdapter OracleAdapter 地址
     */
    function setEventTypeOracleAdapter(bytes32 eventType, address _oracleAdapter) external onlyOwner nonReentrant {
        require(eventType != bytes32(0), "EventManager: event type cannot be empty");
        require(_oracleAdapter != address(0), "EventManager: invalid address");

        eventTypeToOracleAdapter[eventType] = _oracleAdapter;
        authorizedOracleAdapters[_oracleAdapter] = true;

        emit EventTypeOracleSet(eventType, _oracleAdapter);
    }

    /**
     * @notice 移除事件类型对应的 OracleAdapter
     * @param eventType 事件类型标识
     */
    function removeEventTypeOracleAdapter(bytes32 eventType) external onlyOwner nonReentrant {
        require(eventType != bytes32(0), "EventManager: event type cannot be empty");

        delete eventTypeToOracleAdapter[eventType];

        emit EventTypeOracleRemoved(eventType);
    }

    /**
     * @notice 获取事件类型对应的 OracleAdapter
     * @param eventType 事件类型标识
     * @return OracleAdapter 地址
     */
    function getEventTypeOracleAdapter(bytes32 eventType) external view returns (address) {
        return eventTypeToOracleAdapter[eventType];
    }

    /**
     * @notice 添加授权预言机适配器
     * @param oracleAdapter 预言机适配器地址
     */
    function addAuthorizedOracleAdapter(address oracleAdapter) external onlyOwner nonReentrant {
        require(oracleAdapter != address(0), "EventManager: invalid address");
        authorizedOracleAdapters[oracleAdapter] = true;
        emit OracleAdapterAuthorized(oracleAdapter);
    }

    /**
     * @notice 移除授权预言机适配器
     * @param oracleAdapter 预言机适配器地址
     */
    function removeAuthorizedOracleAdapter(address oracleAdapter) external onlyOwner nonReentrant {
        authorizedOracleAdapters[oracleAdapter] = false;
        emit OracleAdapterDeauthorized(oracleAdapter);
    }
}
