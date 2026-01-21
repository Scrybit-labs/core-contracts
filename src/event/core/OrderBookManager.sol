// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./OrderBookManagerStorage.sol";
import "../../interfaces/event/IOrderBookPod.sol";

/**
 * @title OrderBookManager
 * @notice 订单簿管理器 - 负责 Pod 路由和订单管理
 * @dev Manager 层负责协调,Pod 层负责执行
 */
contract OrderBookManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    OrderBookManagerStorage
{
    // ============ Modifiers ============

    /// @notice 仅白名单 Pod 可调用
    modifier onlyWhitelistedPod(IOrderBookPod pod) {
        require(podIsWhitelisted[pod], "OrderBookManager: pod not whitelisted");
        _;
    }

    /// @notice 仅授权调用者 (owner 或授权的合约如 EventManager/EventPod)
    modifier onlyAuthorizedCaller() {
        require(
            authorizedCallers[msg.sender] || msg.sender == owner(),
            "OrderBookManager: caller not authorized"
        );
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
    }

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param pod Pod 地址
     */
    function addPodToWhitelist(IOrderBookPod pod) external onlyOwner {
        require(address(pod) != address(0), "OrderBookManager: invalid pod address");
        require(!podIsWhitelisted[pod], "OrderBookManager: pod already whitelisted");

        podIsWhitelisted[pod] = true;
        emit PodWhitelisted(address(pod));
    }

    /**
     * @notice 从白名单移除 Pod
     * @param pod Pod 地址
     */
    function removePodFromWhitelist(IOrderBookPod pod) external onlyOwner {
        require(podIsWhitelisted[pod], "OrderBookManager: pod not whitelisted");

        podIsWhitelisted[pod] = false;
        emit PodRemovedFromWhitelist(address(pod));
    }

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
    ) external onlyAuthorizedCaller onlyWhitelistedPod(pod) {
        require(
            address(eventIdToPod[eventId]) == address(0),
            "OrderBookManager: event already registered"
        );
        require(outcomeIds.length > 0, "OrderBookManager: empty outcomes");

        eventIdToPod[eventId] = pod;
        pod.addEvent(eventId, outcomeIds);

        emit EventRegisteredToPod(eventId, address(pod));
    }

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
    ) external whenNotPaused returns (uint256 orderId) {
        IOrderBookPod pod = eventIdToPod[eventId];
        require(
            address(pod) != address(0),
            "OrderBookManager: event not mapped"
        );
        require(podIsWhitelisted[pod], "OrderBookManager: pod not whitelisted");

        orderId = pod.placeOrder(
            eventId,
            outcomeId,
            side,
            price,
            amount,
            tokenAddress
        );
    }

    /**
     * @notice 撤单
     * @param eventId 事件 ID
     * @param orderId 订单 ID
     */
    function cancelOrder(
        uint256 eventId,
        uint256 orderId
    ) external whenNotPaused {
        IOrderBookPod pod = eventIdToPod[eventId];
        require(
            address(pod) != address(0),
            "OrderBookManager: event not mapped"
        );
        require(podIsWhitelisted[pod], "OrderBookManager: pod not whitelisted");

        pod.cancelOrder(orderId);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IOrderBookPod pod) external view returns (bool) {
        return podIsWhitelisted[pod];
    }

    /**
     * @notice 获取事件对应的 Pod
     * @param eventId 事件 ID
     * @return pod Pod 地址
     */
    function getEventPod(uint256 eventId) external view returns (IOrderBookPod pod) {
        return eventIdToPod[eventId];
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 添加授权调用者 (如 EventManager/EventPod)
     * @param caller 调用者地址
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        require(caller != address(0), "OrderBookManager: invalid caller address");
        require(!authorizedCallers[caller], "OrderBookManager: already authorized");

        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    /**
     * @notice 移除授权调用者
     * @param caller 调用者地址
     */
    function removeAuthorizedCaller(address caller) external onlyOwner {
        require(authorizedCallers[caller], "OrderBookManager: not authorized");

        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    /**
     * @notice 检查地址是否为授权调用者
     * @param caller 调用者地址
     * @return isAuthorized 是否授权
     */
    function isAuthorizedCaller(address caller) external view returns (bool) {
        return authorizedCallers[caller];
    }

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

    /// @notice 授权调用者添加事件
    event AuthorizedCallerAdded(address indexed caller);

    /// @notice 授权调用者移除事件
    event AuthorizedCallerRemoved(address indexed caller);
}
