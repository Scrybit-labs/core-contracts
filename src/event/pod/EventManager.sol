// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/event/IEventManager.sol";
import "../../interfaces/event/IOrderBookManager.sol";
import "../../interfaces/oracle/IOracle.sol";

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

    /// @notice 仅事件创建者或所有者可调用
    modifier onlyEventCreator() {
        require(msg.sender == owner() || isEventCreator[msg.sender], "EventManager: not authorized");
        _;
    }

    /// @notice 仅授权的预言机可调用
    modifier onlyAuthorizedOracle() {
        require(msg.sender == oracleAdapter, "EventManager: only authorized oracle adapter");
        _;
    }

    /// @notice 事件必须存在
    modifier eventMustExist(uint256 eventId) {
        require(eventId < events.length, "EventManager: event does not exist");
        _;
    }

    /// @notice 仅事件创建者或所有者可操作对应事件
    modifier onlyEventCreatorOrOwner(uint256 eventId) {
        require(msg.sender == owner() || events[eventId].creator == msg.sender, "EventManager: not event creator");
        _;
    }

    // ============ 状态变量 State Variables ============

    /// @notice 事件存储数组
    Event[] internal events;

    /// @notice 事件是否在活跃列表中
    mapping(uint256 => bool) internal isEventActive;

    /// @notice OrderBookManager 合约地址(用于触发结算)
    address public orderBookManager;

    /// @notice OracleAdapter 合约地址(用于验证预言机)
    address public oracleAdapter;

    /// @notice 事件创建者白名单
    mapping(address => bool) public isEventCreator;

    /// @notice Per-manager event counter
    uint256 public nextEventId;

    /// @notice Event oracle request tracking: eventId => requestId
    mapping(uint256 => bytes32) public eventOracleRequests;

    // ===== Upgradeable storage gap =====
    uint256[40] private __gap;

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _orderBookManager OrderBookManager 合约地址
     * @param _oracleAdapter OracleAdapter 合约地址
     */
    function initialize(address initialOwner, address _orderBookManager, address _oracleAdapter) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        orderBookManager = _orderBookManager;
        oracleAdapter = _oracleAdapter;

        // Owner is an event creator by default
        isEventCreator[initialOwner] = true;
    }

    /**
     * @notice Authorizes upgrade to new implementation
     * @dev Only owner can upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ 核心功能 Functions ============

    /**
     * @notice 创建事件 (Event creator direct call)
     * @param title 事件标题
     * @param description 事件描述
     * @param deadline 下注截止时间
     * @param settlementTime 预计结算时间
     * @param outcomes 结果选项数组
     * @return eventId 生成的事件 ID
     */
    function createEvent(
        string calldata title,
        string calldata description,
        uint256 deadline,
        uint256 settlementTime,
        Outcome[] calldata outcomes
    ) external onlyEventCreator nonReentrant returns (uint256 eventId) {
        // Validate parameters
        require(bytes(title).length > 0, "EventManager: empty title");
        require(deadline > block.timestamp, "EventManager: deadline must be in future");
        require(settlementTime > deadline, "EventManager: settlementTime must be after deadline");
        require(outcomes.length >= 2, "EventManager: at least 2 outcomes required");
        require(outcomes.length <= 32, "EventManager: max 32 outcomes");

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
        require(block.timestamp >= evt.settlementTime, "EventManager: settlement time not reached");

        require(oracleAdapter != address(0), "EventManager: oracleAdapter not set");

        requestId = IOracle(oracleAdapter).requestEventResult(eventId, evt.description);

        // Store request mapping
        eventOracleRequests[eventId] = requestId;
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

        emit EventStatusChanged(eventId, oldStatus, newStatus);
    }

    /**
     * @notice 接收预言机结果并结算事件 (实现 IOracleConsumer 接口)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据
     */
    function fulfillResult(
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyAuthorizedOracle eventMustExist(eventId) nonReentrant {
        _settleEvent(eventId, winningOutcomeIndex, proof);
    }

    /**
     * @notice 结算事件 (实现 IEventManager 接口,兼容层)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据
     */
    function settleEvent(
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyAuthorizedOracle eventMustExist(eventId) nonReentrant {
        _settleEvent(eventId, winningOutcomeIndex, proof);
    }

    /**
     * @notice 内部函数: 结算事件逻辑
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof 预言机证明数据 (Merkle Proof)
     */
    function _settleEvent(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof) internal {
        Event storage evt = events[eventId];

        require(evt.status == EventStatus.Active, "EventManager: event not active");
        require(block.timestamp >= evt.settlementTime, "EventManager: settlement time not reached");

        // 验证 winningOutcomeIndex 是否有效
        require(winningOutcomeIndex < uint8(evt.outcomes.length), "EventManager: invalid winning outcome index");

        // 验证 Merkle Proof
        _verifyMerkleProof(eventId, winningOutcomeIndex, proof);

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

        evt.status = EventStatus.Cancelled;

        emit EventCancelled(eventId, reason);
    }

    // ============ 内部函数 Internal Functions ===========

    function _isEventActive(uint256 eventId) internal view eventMustExist(eventId) returns (bool) {
        return events[eventId].status == EventStatus.Active;
    }

    /**
     * @notice 验证状态转换是否合法
     * @param oldStatus 旧状态
     * @param newStatus 新状态
     * @return valid 是否合法
     */
    function _isValidStatusTransition(EventStatus oldStatus, EventStatus newStatus) internal pure returns (bool) {
        // 状态机规则:
        // Created -> Active
        // Active -> Settled/Cancelled
        // Settled/Cancelled -> (终态,不可转换)

        if (oldStatus == EventStatus.Created) {
            return newStatus == EventStatus.Active;
        } else if (oldStatus == EventStatus.Active) {
            return newStatus == EventStatus.Settled || newStatus == EventStatus.Cancelled;
        }

        return false; // Settled 和 Cancelled 是终态
    }

    /**
     * @notice 验证 Merkle Proof
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引 (0-based)
     * @param proof Merkle Proof 证明数据
     * @dev proof 格式: abi.encode(bytes32[] merkleProof, bytes32 root)
     */
    function _verifyMerkleProof(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof) internal view {
        // 如果 proof 为空,跳过验证 (向后兼容,但不推荐)
        if (proof.length == 0) {
            return;
        }

        // 解析 Merkle Proof
        (bytes32[] memory merkleProof, bytes32 expectedRoot) = abi.decode(proof, (bytes32[], bytes32));

        // 构造叶子节点: hash(eventId, winningOutcomeIndex, chainId)
        bytes32 leaf = keccak256(abi.encodePacked(eventId, winningOutcomeIndex, block.chainid));

        // 验证 Merkle Proof
        bool isValid = _verifyProof(merkleProof, expectedRoot, leaf);
        require(isValid, "EventManager: invalid merkle proof");

        // 注意: 这里假设 OracleAdapter 已经验证了 root 的有效性
        // 在生产环境中,可以添加对 OracleAdapter.verifyRoot(expectedRoot) 的调用
    }

    /**
     * @notice 验证 Merkle Proof 是否有效
     * @param proof Merkle 证明路径
     * @param root Merkle 树根
     * @param leaf 叶子节点
     * @return valid 是否有效
     */
    function _verifyProof(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash < proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // 检查计算出的根是否匹配预期根
        return computedHash == root;
    }

    // ============ 查询功能 View Functions ============

    function getEvents() external view returns (Event[] memory _events) {
        _events = events;
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
        require(_orderBookManager != address(0), "EventManager: invalid address");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 设置 OracleAdapter 地址
     * @param _oracleAdapter OracleAdapter 地址
     */
    function setOracleAdapter(address _oracleAdapter) external onlyOwner nonReentrant {
        require(_oracleAdapter != address(0), "EventManager: invalid address");
        oracleAdapter = _oracleAdapter;
    }

    // ============ Pausable Admin ============

    function pause() external onlyOwner nonReentrant {
        _pause();
    }

    function unpause() external onlyOwner nonReentrant {
        _unpause();
    }
}
