// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./EventManagerStorage.sol";
import "../../interfaces/event/IEventPod.sol";
import "../../interfaces/event/IOrderBookManager.sol";
import "../../interfaces/event/IOrderBookPod.sol";

/**
 * @title EventManager
 * @notice 事件管理器 - 负责事件生命周期管理和 Pod 路由
 * @dev Manager 层负责协调,Pod 层负责执行
 */
contract EventManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    EventManagerStorage
{
    // ============ Modifiers ============

    /// @notice 仅白名单 Pod 可调用
    modifier onlyWhitelistedPod(IEventPod pod) {
        require(podIsWhitelisted[pod], "EventManager: pod not whitelisted");
        _;
    }

    /// @notice 仅授权预言机可调用
    modifier onlyAuthorizedOracle() {
        require(authorizedOracles[msg.sender], "EventManager: caller not authorized oracle");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param _initialOwner 初始所有者地址
     */
    function initialize(address _initialOwner) external initializer {
        __Ownable_init(_initialOwner);
        __Pausable_init();

        // 初始化事件 ID 从 1 开始
        nextEventId = 1;
    }

    /**
     * @notice 设置 OrderBookManager 地址
     * @param _orderBookManager OrderBookManager 合约地址
     */
    function setOrderBookManager(address _orderBookManager) external onlyOwner {
        require(_orderBookManager != address(0), "EventManager: invalid orderBookManager");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 配置 EventPod 对应的 OrderBookPod
     * @param eventPod EventPod 地址
     * @param orderBookPod OrderBookPod 地址
     */
    function setEventPodOrderBookPod(IEventPod eventPod, address orderBookPod) external onlyOwner {
        require(address(eventPod) != address(0), "EventManager: invalid eventPod");
        require(orderBookPod != address(0), "EventManager: invalid orderBookPod");
        require(podIsWhitelisted[eventPod], "EventManager: eventPod not whitelisted");

        eventPodToOrderBookPod[eventPod] = orderBookPod;
        emit EventPodOrderBookPodMapped(address(eventPod), orderBookPod);
    }

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param pod EventPod 合约地址
     */
    function addPodToWhitelist(IEventPod pod) external onlyOwner {
        require(address(pod) != address(0), "EventManager: invalid pod address");
        require(!podIsWhitelisted[pod], "EventManager: pod already whitelisted");

        podIsWhitelisted[pod] = true;

        // 添加到数组并记录索引
        podIndex[pod] = whitelistedPods.length;
        whitelistedPods.push(pod);

        emit PodWhitelisted(address(pod));
    }

    /**
     * @notice 从白名单移除 Pod
     * @param pod EventPod 合约地址
     */
    function removePodFromWhitelist(IEventPod pod) external onlyOwner {
        require(podIsWhitelisted[pod], "EventManager: pod not whitelisted");

        podIsWhitelisted[pod] = false;

        // 从数组中删除(用最后一个元素替换,然后 pop)
        uint256 index = podIndex[pod];
        uint256 lastIndex = whitelistedPods.length - 1;

        if (index != lastIndex) {
            IEventPod lastPod = whitelistedPods[lastIndex];
            whitelistedPods[index] = lastPod;
            podIndex[lastPod] = index;
        }

        whitelistedPods.pop();
        delete podIndex[pod];

        emit PodRemovedFromWhitelist(address(pod));
    }

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod EventPod 合约地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IEventPod pod) external view returns (bool) {
        return podIsWhitelisted[pod];
    }

    // ============ 预言机管理功能 ============

    /**
     * @notice 注册预言机
     * @param oracle 预言机地址
     */
    function registerOracle(address oracle) external onlyOwner {
        require(oracle != address(0), "EventManager: invalid oracle address");
        require(!authorizedOracles[oracle], "EventManager: oracle already registered");

        authorizedOracles[oracle] = true;
        emit OracleRegistered(oracle);
    }

    /**
     * @notice 移除预言机
     * @param oracle 预言机地址
     */
    function removeOracle(address oracle) external onlyOwner {
        require(authorizedOracles[oracle], "EventManager: oracle not registered");

        authorizedOracles[oracle] = false;
        emit OracleRemoved(oracle);
    }

    /**
     * @notice 检查预言机是否已授权
     * @param oracle 预言机地址
     * @return isAuthorized 是否已授权
     */
    function isOracleAuthorized(address oracle) external view returns (bool) {
        return authorizedOracles[oracle];
    }

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
    ) external whenNotPaused onlyOwner returns (uint256 eventId, IEventPod assignedPod) {
        // 参数验证
        require(bytes(title).length > 0, "EventManager: title cannot be empty");
        require(outcomeNames.length >= 2, "EventManager: at least 2 outcomes required");
        require(
            outcomeNames.length == outcomeDescriptions.length,
            "EventManager: outcomes length mismatch"
        );
        require(deadline > block.timestamp, "EventManager: deadline must be in future");
        require(settlementTime > deadline, "EventManager: settlement must be after deadline");
        require(whitelistedPods.length > 0, "EventManager: no pods available");

        // 生成事件 ID
        eventId = nextEventId++;

        // 负载均衡: 轮询分配 Pod
        assignedPod = _selectPodForEvent();
        require(address(assignedPod) != address(0), "EventManager: failed to select pod");

        // 记录事件到 Pod 的映射
        eventIdToPod[eventId] = assignedPod;

        // 生成 outcome IDs (从 1 开始)
        uint256[] memory outcomeIds = new uint256[](outcomeNames.length);
        for (uint256 i = 0; i < outcomeNames.length; i++) {
            outcomeIds[i] = i + 1;
        }

        // 调用 Pod 添加事件
        assignedPod.addEvent(
            eventId,
            title,
            description,
            deadline,
            settlementTime,
            msg.sender,
            outcomeIds,
            outcomeNames,
            outcomeDescriptions
        );

        // 注册事件到 OrderBookManager (自动调用)
        if (orderBookManager != address(0)) {
            _registerEventToOrderBook(eventId, outcomeIds);
        }

        emit EventCreatedByManager(eventId, address(assignedPod), msg.sender, title);
    }

    // ============ 内部函数 Internal Functions ============

    /**
     * @notice 使用轮询算法选择 Pod
     * @return pod 选中的 Pod
     */
    function _selectPodForEvent() internal returns (IEventPod pod) {
        require(whitelistedPods.length > 0, "EventManager: no pods available");

        // 轮询选择下一个 Pod
        pod = whitelistedPods[currentPodIndex];

        // 更新索引(循环)
        currentPodIndex = (currentPodIndex + 1) % whitelistedPods.length;
    }

    /**
     * @notice 注册事件到 OrderBookManager
     * @param eventId 事件 ID
     * @param outcomeIds 结果 ID 列表
     */
    function _registerEventToOrderBook(uint256 eventId, uint256[] memory outcomeIds) internal {
        // 获取当前事件所属的 EventPod
        IEventPod eventPod = eventIdToPod[eventId];
        require(address(eventPod) != address(0), "EventManager: event not mapped to pod");

        // 获取对应的 OrderBookPod
        address orderBookPod = eventPodToOrderBookPod[eventPod];
        require(orderBookPod != address(0), "EventManager: OrderBookPod not configured for EventPod");

        // 调用 OrderBookManager 注册事件到 OrderBookPod
        IOrderBookManager(orderBookManager).registerEventToPod(
            IOrderBookPod(orderBookPod),
            eventId,
            outcomeIds
        );
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取事件所属的 Pod
     * @param eventId 事件 ID
     * @return pod EventPod 合约地址
     */
    function getEventPod(uint256 eventId) external view returns (IEventPod pod) {
        pod = eventIdToPod[eventId];
        require(address(pod) != address(0), "EventManager: event not found");
    }

    /**
     * @notice 获取下一个事件 ID
     * @return nextId 下一个事件 ID
     */
    function getNextEventId() external view returns (uint256) {
        return nextEventId;
    }

    /**
     * @notice 获取所有白名单 Pod 数量
     * @return count Pod 数量
     */
    function getWhitelistedPodCount() external view returns (uint256) {
        return whitelistedPods.length;
    }

    /**
     * @notice 获取指定索引的白名单 Pod
     * @param index Pod 索引
     * @return pod Pod 地址
     */
    function getWhitelistedPodAt(uint256 index) external view returns (IEventPod) {
        require(index < whitelistedPods.length, "EventManager: index out of bounds");
        return whitelistedPods[index];
    }

    // ============ 紧急控制 Emergency Control ============

    /**
     * @notice 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ 事件 Events ============

    /// @notice EventPod 映射到 OrderBookPod 事件
    event EventPodOrderBookPodMapped(address indexed eventPod, address indexed orderBookPod);
}
