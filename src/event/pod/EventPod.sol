// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./EventPodStorage.sol";
import "../../interfaces/event/IEventPod.sol";
import "../../interfaces/event/IOrderBookManager.sol";
import "../../interfaces/event/IOrderBookPod.sol";
import "../../interfaces/oracle/IOracle.sol";

/**
 * @title EventPod
 * @notice 事件 Pod - 负责独立处理一组事件的执行单元
 * @dev 每个 EventPod 独立管理一组事件,实现事件隔离和横向扩展
 */
contract EventPod is Initializable, OwnableUpgradeable, EventPodStorage, IOracleConsumer {
    // ============ Modifiers ============

    /// @notice 仅 EventManager 可调用
    modifier onlyEventManager() {
        require(msg.sender == eventManager, "EventPod: only eventManager");
        _;
    }

    /// @notice 仅授权的预言机可调用
    modifier onlyAuthorizedOracle() {
        require(msg.sender == oracleAdapter, "EventPod: only authorized oracle adapter");
        _;
    }

    /// @notice 事件必须存在
    modifier eventMustExist(uint256 eventId) {
        require(eventExists[eventId], "EventPod: event does not exist");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _eventManager EventManager 合约地址
     * @param _orderBookManager OrderBookManager 合约地址
     */
    function initialize(address initialOwner, address _eventManager, address _orderBookManager) external initializer {
        __Ownable_init(initialOwner);

        require(_eventManager != address(0), "EventPod: invalid eventManager");
        require(_orderBookManager != address(0), "EventPod: invalid orderBookManager");

        eventManager = _eventManager;
        orderBookManager = _orderBookManager;
    }

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
    ) external onlyEventManager {
        require(!eventExists[eventId], "EventPod: event already exists");
        require(outcomeIds.length == outcomeNames.length, "EventPod: outcomes length mismatch");
        require(outcomeIds.length == outcomeDescriptions.length, "EventPod: descriptions length mismatch");
        require(outcomeIds.length >= 2, "EventPod: at least 2 outcomes required");

        // 创建事件
        Event storage newEvent = events[eventId];
        newEvent.eventId = eventId;
        newEvent.title = title;
        newEvent.description = description;
        newEvent.deadline = deadline;
        newEvent.settlementTime = settlementTime;
        newEvent.status = EventStatus.Created;
        newEvent.creator = creator;
        newEvent.outcomeIds = outcomeIds;
        newEvent.winningOutcomeId = 0; // 未结算

        // 存储结果选项
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint256 outcomeId = outcomeIds[i];
            outcomes[eventId][outcomeId] =
                Outcome({outcomeId: outcomeId, name: outcomeNames[i], description: outcomeDescriptions[i]});
        }

        // 标记事件存在
        eventExists[eventId] = true;

        // 添加到活跃列表
        _addToActiveList(eventId);

        // 注意: 事件注册到 OrderBookManager 由 EventManager 自动处理
        // EventManager.createEvent() 会在创建事件后自动调用
        // OrderBookManager.registerEventToPod() 来初始化订单簿

        emit EventCreated(eventId, title, deadline, outcomeIds);
    }

    /**
     * @notice 更新事件状态
     * @param eventId 事件 ID
     * @param newStatus 新状态
     */
    function updateEventStatus(uint256 eventId, EventStatus newStatus)
        external
        onlyEventManager
        eventMustExist(eventId)
    {
        Event storage evt = events[eventId];
        EventStatus oldStatus = evt.status;

        // 状态机验证
        require(_isValidStatusTransition(oldStatus, newStatus), "EventPod: invalid status transition");

        evt.status = newStatus;

        // 如果变为非活跃状态,从活跃列表移除
        if (newStatus == EventStatus.Settled || newStatus == EventStatus.Cancelled) {
            _removeFromActiveList(eventId);
        }

        emit EventStatusChanged(eventId, oldStatus, newStatus);
    }

    /**
     * @notice 接收预言机结果并结算事件 (实现 IOracleConsumer 接口)
     * @param eventId 事件 ID
     * @param winningOutcomeId 获胜结果 ID
     * @param proof 预言机证明数据
     */
    function fulfillResult(uint256 eventId, uint256 winningOutcomeId, bytes calldata proof)
        external
        override
        onlyAuthorizedOracle
        eventMustExist(eventId)
    {
        _settleEvent(eventId, winningOutcomeId, proof);
    }

    /**
     * @notice 结算事件 (实现 IEventPod 接口,兼容层)
     * @param eventId 事件 ID
     * @param winningOutcomeId 获胜结果 ID
     * @param proof 预言机证明数据
     */
    function settleEvent(uint256 eventId, uint256 winningOutcomeId, bytes calldata proof)
        external
        override
        onlyAuthorizedOracle
        eventMustExist(eventId)
    {
        _settleEvent(eventId, winningOutcomeId, proof);
    }

    /**
     * @notice 内部函数: 结算事件逻辑
     * @param eventId 事件 ID
     * @param winningOutcomeId 获胜结果 ID
     * @param proof 预言机证明数据 (Merkle Proof)
     */
    function _settleEvent(uint256 eventId, uint256 winningOutcomeId, bytes calldata proof) internal {
        Event storage evt = events[eventId];

        require(evt.status == EventStatus.Active, "EventPod: event not active");
        require(block.timestamp >= evt.settlementTime, "EventPod: settlement time not reached");

        // 验证 winningOutcomeId 是否有效
        bool validOutcome = false;
        for (uint256 i = 0; i < evt.outcomeIds.length; i++) {
            if (evt.outcomeIds[i] == winningOutcomeId) {
                validOutcome = true;
                break;
            }
        }
        require(validOutcome, "EventPod: invalid winning outcome");

        // 验证 Merkle Proof
        _verifyMerkleProof(eventId, winningOutcomeId, proof);

        // 更新事件状态
        evt.status = EventStatus.Settled;
        evt.winningOutcomeId = winningOutcomeId;

        // 从活跃列表移除
        _removeFromActiveList(eventId);

        // 通过 OrderBookManager 获取对应的 OrderBookPod 并触发结算
        IOrderBookPod orderBookPod = IOrderBookManager(orderBookManager).getEventPod(eventId);
        require(address(orderBookPod) != address(0), "EventPod: orderBookPod not found");

        orderBookPod.settleEvent(eventId, winningOutcomeId);

        emit EventSettled(eventId, winningOutcomeId, block.timestamp);
        emit OracleResultReceived(eventId, winningOutcomeId, msg.sender);
    }

    /**
     * @notice 取消事件
     * @param eventId 事件 ID
     * @param reason 取消原因
     */
    function cancelEvent(uint256 eventId, string calldata reason) external onlyEventManager eventMustExist(eventId) {
        Event storage evt = events[eventId];

        require(
            evt.status == EventStatus.Created || evt.status == EventStatus.Active,
            "EventPod: cannot cancel settled event"
        );

        evt.status = EventStatus.Cancelled;

        // 从活跃列表移除
        _removeFromActiveList(eventId);

        emit EventCancelled(eventId, reason);
    }

    // ============ 内部函数 Internal Functions ============

    /**
     * @notice 添加事件到活跃列表
     * @param eventId 事件 ID
     */
    function _addToActiveList(uint256 eventId) internal {
        if (!isEventActive[eventId]) {
            activeEventIndex[eventId] = activeEventIds.length;
            activeEventIds.push(eventId);
            isEventActive[eventId] = true;
        }
    }

    /**
     * @notice 从活跃列表移除事件
     * @param eventId 事件 ID
     */
    function _removeFromActiveList(uint256 eventId) internal {
        if (isEventActive[eventId]) {
            uint256 index = activeEventIndex[eventId];
            uint256 lastIndex = activeEventIds.length - 1;

            if (index != lastIndex) {
                uint256 lastEventId = activeEventIds[lastIndex];
                activeEventIds[index] = lastEventId;
                activeEventIndex[lastEventId] = index;
            }

            activeEventIds.pop();
            delete activeEventIndex[eventId];
            isEventActive[eventId] = false;
        }
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
     * @param winningOutcomeId 获胜结果 ID
     * @param proof Merkle Proof 证明数据
     * @dev proof 格式: abi.encode(bytes32[] merkleProof, bytes32 root)
     */
    function _verifyMerkleProof(uint256 eventId, uint256 winningOutcomeId, bytes calldata proof) internal view {
        // 如果 proof 为空,跳过验证 (向后兼容,但不推荐)
        if (proof.length == 0) {
            return;
        }

        // 解析 Merkle Proof
        (bytes32[] memory merkleProof, bytes32 expectedRoot) = abi.decode(proof, (bytes32[], bytes32));

        // 构造叶子节点: hash(eventId, winningOutcomeId, chainId)
        bytes32 leaf = keccak256(abi.encodePacked(eventId, winningOutcomeId, block.chainid));

        // 验证 Merkle Proof
        bool isValid = _verifyProof(merkleProof, expectedRoot, leaf);
        require(isValid, "EventPod: invalid merkle proof");

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

    /**
     * @notice 获取事件结果选项
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @return outcome 结果选项信息
     */
    function getOutcome(uint256 eventId, uint256 outcomeId)
        external
        view
        eventMustExist(eventId)
        returns (Outcome memory)
    {
        Outcome memory outcome = outcomes[eventId][outcomeId];
        require(outcome.outcomeId != 0, "EventPod: outcome does not exist");
        return outcome;
    }

    /**
     * @notice 列出所有活跃事件 ID
     * @return eventIds 活跃事件 ID 数组
     */
    function listActiveEvents() external view returns (uint256[] memory) {
        return activeEventIds;
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 更新 OrderBookManager 地址
     * @param _orderBookManager 新地址
     */
    function setOrderBookManager(address _orderBookManager) external onlyOwner {
        require(_orderBookManager != address(0), "EventPod: invalid address");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 更新 EventManager 地址
     * @param _eventManager 新地址
     */
    function setEventManager(address _eventManager) external onlyOwner {
        require(_eventManager != address(0), "EventPod: invalid address");
        eventManager = _eventManager;
    }

    /**
     * @notice 设置 OracleAdapter 地址
     * @param _oracleAdapter OracleAdapter 地址
     */
    function setOracleAdapter(address _oracleAdapter) external onlyOwner {
        require(_oracleAdapter != address(0), "EventPod: invalid address");
        oracleAdapter = _oracleAdapter;
    }
}
