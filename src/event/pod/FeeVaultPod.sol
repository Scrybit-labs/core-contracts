// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/event/IFeeVaultPod.sol";

/**
 * @title FeeVaultPod
 * @notice 手续费金库 Pod - 负责手续费收取、存储和分配
 * @dev 每个 FeeVaultPod 独立管理一组事件的手续费
 */
contract FeeVaultPod is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IFeeVaultPod
{
    using SafeERC20 for IERC20;

    // ============ Modifiers ============

    /// @notice 仅 OrderBookPod 可调用
    modifier onlyOrderBookPod() {
        require(msg.sender == orderBookPod, "FeeVaultPod: only orderBookPod");
        _;
    }

    // ============ 合约地址 Contract Addresses ============

    /// @notice OrderBookPod 合约地址
    address public orderBookPod;

    // ============ 手续费配置 Fee Configuration ============

    /// @notice 手续费率映射: feeType => rate (basis points)
    /// @dev 例如: feeRates["trade"] = 30 表示 0.3% 交易手续费
    mapping(bytes32 => uint256) internal feeRates;

    /// @notice 手续费率键列表(用于遍历)
    bytes32[] internal feeRateKeys;

    /// @notice 手续费率键是否存在
    mapping(bytes32 => bool) internal feeRateKeyExists;

    // ============ 手续费余额管理 Fee Balance Management ============

    /// @notice Token 手续费余额: token => balance
    mapping(address => uint256) public feeBalances;

    /// @notice 总手续费收取: token => totalCollected
    mapping(address => uint256) public totalFeesCollected;

    /// @notice 总手续费提取: token => totalWithdrawn
    mapping(address => uint256) public totalFeesWithdrawn;

    // ============ 手续费统计 Fee Statistics ============

    /// @notice 事件手续费统计: eventId => token => amount
    mapping(uint256 => mapping(address => uint256)) public eventFees;

    /// @notice 用户支付的手续费: user => token => amount
    mapping(address => mapping(address => uint256)) public userPaidFees;

    // ============ 常量 Constants ============

    /// @notice 费率精度(基点)
    uint256 public constant FEE_PRECISION = 10000;

    /// @notice 最大费率(10%)
    uint256 public constant MAX_FEE_RATE = 1000;

    // ===== Upgradeable storage gap =====
    uint256[41] private __gap;

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _orderBookPod OrderBookPod 合约地址
     */
    function initialize(address initialOwner, address _orderBookPod) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        orderBookPod = _orderBookPod;

        // 设置默认手续费率
        _setFeeRate("trade", 30); // 0.3% 交易手续费
    }

    /**
     * @notice Authorizes upgrade to new implementation
     * @dev Only owner can upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
    ) external whenNotPaused onlyOrderBookPod nonReentrant {
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
     * @param amount 提取金额
     */
    function withdrawFee(address token, uint256 amount) external onlyOwner nonReentrant {
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
            (bool sent, ) = owner().call{value: amount}("");
            require(sent, "FeeVaultPod: failed to send ETH");
        } else {
            // ERC20
            IERC20(token).safeTransfer(owner(), amount);
        }

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
    function setOrderBookPod(address _orderBookPod) external onlyOwner nonReentrant {
        require(_orderBookPod != address(0), "FeeVaultPod: invalid address");
        orderBookPod = _orderBookPod;
    }

    /**
     * @notice 暂停合约
     */
    function pause() external onlyOwner nonReentrant {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() external onlyOwner nonReentrant {
        _unpause();
    }

    // ============ 接收 ETH ============

    receive() external payable {}
}
