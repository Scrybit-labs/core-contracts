// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./FeeVaultManagerStorage.sol";
import "../../interfaces/event/IFeeVaultPod.sol";

/**
 * @title FeeVaultManager
 * @notice 手续费管理器 - 负责 Pod 路由和手续费管理
 * @dev Manager 层负责协调,Pod 层负责执行
 */
contract FeeVaultManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    FeeVaultManagerStorage
{
    // ============ Modifiers ============

    /// @notice 仅白名单 Pod 可调用
    modifier onlyWhitelistedPod(IFeeVaultPod pod) {
        require(podIsWhitelisted[pod], "FeeVaultManager: pod not whitelisted");
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
    function addPodToWhitelist(IFeeVaultPod pod) external onlyOwner {
        require(address(pod) != address(0), "FeeVaultManager: invalid pod address");
        require(!podIsWhitelisted[pod], "FeeVaultManager: pod already whitelisted");

        podIsWhitelisted[pod] = true;
        emit PodWhitelisted(address(pod));
    }

    /**
     * @notice 从白名单移除 Pod
     * @param pod Pod 地址
     */
    function removePodFromWhitelist(IFeeVaultPod pod) external onlyOwner {
        require(podIsWhitelisted[pod], "FeeVaultManager: pod not whitelisted");

        podIsWhitelisted[pod] = false;
        emit PodRemovedFromWhitelist(address(pod));
    }

    /**
     * @notice 注册事件到 Pod
     * @param pod Pod 地址
     * @param eventId 事件 ID
     */
    function registerEventToPod(
        IFeeVaultPod pod,
        uint256 eventId
    ) external onlyOwner onlyWhitelistedPod(pod) {
        require(
            address(eventIdToPod[eventId]) == address(0),
            "FeeVaultManager: event already registered"
        );

        eventIdToPod[eventId] = pod;
        emit EventRegisteredToPod(eventId, address(pod));
    }

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
    ) external whenNotPaused {
        IFeeVaultPod pod = eventIdToPod[eventId];
        require(
            address(pod) != address(0),
            "FeeVaultManager: event not mapped"
        );
        require(podIsWhitelisted[pod], "FeeVaultManager: pod not whitelisted");

        pod.collectFee(token, payer, amount, eventId, feeType);
    }

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
    ) external onlyOwner onlyWhitelistedPod(pod) {
        require(recipient != address(0), "FeeVaultManager: invalid recipient");
        require(amount > 0, "FeeVaultManager: invalid amount");

        pod.withdrawFee(token, recipient, amount);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param pod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IFeeVaultPod pod) external view returns (bool) {
        return podIsWhitelisted[pod];
    }

    /**
     * @notice 获取事件对应的 Pod
     * @param eventId 事件 ID
     * @return pod Pod 地址
     */
    function getEventPod(uint256 eventId) external view returns (IFeeVaultPod pod) {
        return eventIdToPod[eventId];
    }

    /**
     * @notice 获取 Pod 的手续费余额
     * @param pod Pod 地址
     * @param token Token 地址
     * @return balance 手续费余额
     */
    function getPodFeeBalance(
        IFeeVaultPod pod,
        address token
    ) external view returns (uint256 balance) {
        require(podIsWhitelisted[pod], "FeeVaultManager: pod not whitelisted");
        return pod.getFeeBalance(token);
    }

    // ============ 管理功能 Admin Functions ============

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
}
