// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./FeeVaultPodStorage.sol";
import "../../interfaces/event/IFeeVaultPod.sol";

/**
 * @title FeeVaultPod
 * @notice 手续费金库 Pod - 负责手续费收取、存储和分配
 * @dev 每个 FeeVaultPod 独立管理一组事件的手续费
 */
contract FeeVaultPod is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuard, FeeVaultPodStorage {
    using SafeERC20 for IERC20;

    // ============ Modifiers ============

    /// @notice 仅 FeeVaultManager 可调用
    modifier onlyFeeVaultManager() {
        require(msg.sender == feeVaultManager, "FeeVaultPod: only feeVaultManager");
        _;
    }

    /// @notice 仅 OrderBookPod 可调用
    modifier onlyOrderBookPod() {
        require(msg.sender == orderBookPod, "FeeVaultPod: only orderBookPod");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _feeVaultManager FeeVaultManager 合约地址
     * @param _orderBookPod OrderBookPod 合约地址
     * @param _feeRecipient 手续费接收者地址
     */
    function initialize(
        address initialOwner,
        address _feeVaultManager,
        address _orderBookPod,
        address _feeRecipient
    ) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        require(_feeVaultManager != address(0), "FeeVaultPod: invalid feeVaultManager");
        require(_feeRecipient != address(0), "FeeVaultPod: invalid feeRecipient");

        feeVaultManager = _feeVaultManager;
        orderBookPod = _orderBookPod;
        feeRecipient = _feeRecipient;

        // 设置默认手续费率
        _setFeeRate("trade", 30); // 0.3% 交易手续费
    }

    // ============ 核心功能 Core Functions ============

    /**
     * @notice 收取交易手续费
     * @param token Token 地址
     * @param payer 支付者地址
     * @param amount 手续费金额
     * @param eventId 事件 ID
     * @param feeType 手续费类型
     */
    function collectFee(
        address token,
        address payer,
        uint256 amount,
        uint256 eventId,
        string calldata feeType
    ) external whenNotPaused onlyOrderBookPod {
        if (amount == 0) revert InvalidAmount(amount);

        // 更新余额
        feeBalances[token] += amount;
        totalFeesCollected[token] += amount;

        // 统计
        eventFees[eventId][token] += amount;
        userPaidFees[payer][token] += amount;

        emit FeeCollected(token, payer, amount, eventId, feeType);
    }

    /**
     * @notice 提取手续费
     * @param token Token 地址
     * @param recipient 接收者地址
     * @param amount 提取金额
     */
    function withdrawFee(address token, address recipient, uint256 amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidRecipient(recipient);
        if (amount == 0) revert InvalidAmount(amount);

        uint256 available = feeBalances[token];
        if (available < amount) {
            revert InsufficientFeeBalance(token, amount, available);
        }

        // 更新余额
        feeBalances[token] -= amount;
        totalFeesWithdrawn[token] += amount;

        // 转账
        if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            // ETH
            (bool sent, ) = recipient.call{value: amount}("");
            require(sent, "FeeVaultPod: failed to send ETH");
        } else {
            // ERC20
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit FeeWithdrawn(token, recipient, amount);
    }

    /**
     * @notice 设置手续费率
     * @param feeType 手续费类型
     * @param rate 费率(基点, 1-10000)
     */
    function setFeeRate(string calldata feeType, uint256 rate) external onlyOwner {
        _setFeeRate(feeType, rate);
    }

    /**
     * @notice 内部函数: 设置手续费率
     * @param feeType 手续费类型
     * @param rate 费率(基点)
     */
    function _setFeeRate(string memory feeType, uint256 rate) internal {
        if (rate > MAX_FEE_RATE) revert InvalidFeeRate(rate);

        bytes32 key = keccak256(bytes(feeType));
        uint256 oldRate = feeRates[key];

        feeRates[key] = rate;

        // 记录键(用于遍历)
        if (!feeRateKeyExists[key]) {
            feeRateKeys.push(key);
            feeRateKeyExists[key] = true;
        }

        emit FeeRateUpdated(feeType, oldRate, rate);
    }

    /**
     * @notice 设置手续费接收者
     * @param recipient 接收者地址
     */
    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient(recipient);

        address oldRecipient = feeRecipient;
        feeRecipient = recipient;

        emit FeeRecipientUpdated(oldRecipient, recipient);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取手续费余额
     * @param token Token 地址
     * @return balance 手续费余额
     */
    function getFeeBalance(address token) external view returns (uint256 balance) {
        return feeBalances[token];
    }

    /**
     * @notice 获取手续费率
     * @param feeType 手续费类型
     * @return rate 费率(基点)
     */
    function getFeeRate(string calldata feeType) external view returns (uint256 rate) {
        bytes32 key = keccak256(bytes(feeType));
        return feeRates[key];
    }

    /**
     * @notice 获取手续费接收者
     * @return recipient 接收者地址
     */
    function getFeeRecipient() external view returns (address recipient) {
        return feeRecipient;
    }

    /**
     * @notice 计算手续费
     * @param amount 交易金额
     * @param feeType 手续费类型
     * @return fee 手续费金额
     */
    function calculateFee(uint256 amount, string calldata feeType) external view returns (uint256 fee) {
        bytes32 key = keccak256(bytes(feeType));
        uint256 rate = feeRates[key];

        if (rate == 0) return 0;

        fee = (amount * rate) / FEE_PRECISION;
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 设置 OrderBookPod 地址
     * @param _orderBookPod OrderBookPod 地址
     */
    function setOrderBookPod(address _orderBookPod) external onlyOwner {
        require(_orderBookPod != address(0), "FeeVaultPod: invalid address");
        orderBookPod = _orderBookPod;
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

    // ============ 接收 ETH ============

    receive() external payable {}
}
