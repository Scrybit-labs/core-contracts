// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/core/IFeeVaultManager.sol";
import "../interfaces/core/IFundingManager.sol";

/**
 * @title FeeVaultManager
 * @notice 手续费金库 Manager - 负责手续费收取、存储和分配
 * @dev 每个 FeeVaultManager 独立管理一组事件的手续费
 */
contract FeeVaultManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IFeeVaultManager
{
    // ============ Modifiers ============

    /// @notice 仅 OrderBookManager 可调用
    modifier onlyOrderBookManager() {
        require(msg.sender == orderBookManager, "FeeVaultManager: only orderBookManager");
        _;
    }

    // ============ 合约地址 Contract Addresses ============

    /// @notice OrderBookManager 合约地址
    address public orderBookManager;

    /// @notice FundingManager 合约地址
    address public fundingManager;

    // ============ 手续费配置 Fee Configuration ============

    /// @notice 手续费率映射: feeType => rate (basis points)
    /// @dev 例如: feeRates["placement"] = 10 表示 0.1% 下单手续费
    mapping(bytes32 => uint256) internal feeRates;

    /// @notice 手续费率键列表(用于遍历)
    bytes32[] internal feeRateKeys;

    /// @notice 手续费率键是否存在
    mapping(bytes32 => bool) internal feeRateKeyExists;

    // ============ 手续费余额管理 Fee Balance Management ============

    /// @notice 协议统一 USD 手续费余额 (1e18)
    uint256 public protocolUsdFeeBalance;

    /// @notice 总手续费收取(USD): token => totalCollectedUsd
    mapping(address => uint256) public totalFeesCollected;

    /// @notice 总手续费提取(USD): token => totalWithdrawnUsd
    mapping(address => uint256) public totalFeesWithdrawn;

    // ============ 手续费统计 Fee Statistics ============

    /// @notice 事件手续费统计(USD): eventId => token => amount
    mapping(uint256 => mapping(address => uint256)) public eventFees;

    /// @notice 用户支付的手续费(USD): user => token => amount
    mapping(address => mapping(address => uint256)) public userPaidFees;

    // ============ 常量 Constants ============

    /// @notice 费率精度(基点)
    uint256 public constant FEE_PRECISION = 10000;

    /// @notice 最大费率(10%)
    uint256 public constant MAX_FEE_RATE = 1000;

    // ===== Upgradeable storage gap =====
    uint256[41] private __gap;

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
     * @param _orderBookManager OrderBookManager 合约地址
     */
    function initialize(address initialOwner, address _orderBookManager) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        orderBookManager = _orderBookManager;

        // 设置默认手续费率
        _setFeeRate("placement", 10); // 0.1% 下单手续费
        _setFeeRate("execution", 20); // 0.2% 撮合手续费
    }

    // ============ 核心功能 Core Functions ============

    /**
     * @notice 收取交易手续费
     * @param token Token 地址
     * @param payer 支付者地址
     * @param amount 手续费金额 (USD, 1e18)
     * @param eventId 事件 ID
     * @param feeType 手续费类型
     */
    function collectFee(
        address token,
        address payer,
        uint256 amount,
        uint256 eventId,
        string calldata feeType
    ) external whenNotPaused onlyOrderBookManager nonReentrant {
        if (amount == 0) revert InvalidAmount(amount);
        require(fundingManager != address(0), "FeeVaultManager: fundingManager not set");

        // 扣减用户 USD 余额
        IFundingManager(fundingManager).collectProtocolFee(payer, amount);

        // 更新余额 (USD)
        protocolUsdFeeBalance += amount;
        totalFeesCollected[token] += amount;

        // 统计
        eventFees[eventId][token] += amount;
        userPaidFees[payer][token] += amount;

        emit FeeCollected(token, payer, amount, eventId, feeType);
    }

    /**
     * @notice 提取手续费
     * @param token Token 地址
     * @param amount 提取金额 (USD, 1e18)
     */
    function withdrawFee(address token, uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount(amount);
        require(fundingManager != address(0), "FeeVaultManager: fundingManager not set");

        uint256 available = protocolUsdFeeBalance;
        if (available < amount) {
            revert InsufficientFeeBalance(token, amount, available);
        }

        // 更新余额 (USD)
        protocolUsdFeeBalance -= amount;
        totalFeesWithdrawn[token] += amount;

        // 转账 (由 FundingManager 提取流动性)
        uint256 tokenAmount = IFundingManager(fundingManager).denormalizeFromUsd(token, amount);
        IFundingManager(fundingManager).withdrawLiquidity(token, tokenAmount, owner());

        emit FeeWithdrawn(token, owner(), amount);
    }

    /**
     * @notice 设置手续费率
     * @param feeType 手续费类型
     * @param rate 费率(基点, 1-10000)
     */
    function setFeeRate(string calldata feeType, uint256 rate) external onlyOwner nonReentrant {
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

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取协议 USD 手续费余额
     * @return balance 手续费余额 (USD, 1e18)
     */
    function getFeeBalance(address /*token*/) external view returns (uint256 balance) {
        return protocolUsdFeeBalance;
    }

    /**
     * @notice 获取协议 USD 手续费余额
     */
    function getProtocolUsdFeeBalance() external view returns (uint256) {
        return protocolUsdFeeBalance;
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
     * @notice 计算手续费
     * @param amount 交易金额 (USD, 1e18)
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
     * @notice 设置 OrderBookManager 地址
     * @param _orderBookManager OrderBookManager 地址
     */
    function setOrderBookManager(address _orderBookManager) external onlyOwner nonReentrant {
        require(_orderBookManager != address(0), "FeeVaultManager: invalid address");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 设置 FundingManager 地址
     * @param _fundingManager FundingManager 地址
     */
    function setFundingManager(address _fundingManager) external onlyOwner nonReentrant {
        require(_fundingManager != address(0), "FeeVaultManager: invalid address");
        fundingManager = _fundingManager;
    }

    // ============ 接收 ETH ============

    receive() external payable {}
}
