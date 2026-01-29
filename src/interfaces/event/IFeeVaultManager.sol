// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IFeeVaultManager
 * @notice 手续费金库 Manager 接口 - 负责手续费收取和分配
 * @dev 每个 FeeVaultManager 独立管理一组事件的手续费
 */
interface IFeeVaultManager {
    // ============ 事件 Events ============

    /// @notice 手续费收取事件
    event FeeCollected(address indexed token, address indexed payer, uint256 amount, uint256 eventId, string feeType);

    /// @notice 手续费提取事件
    event FeeWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    /// @notice 手续费率更新事件
    event FeeRateUpdated(string indexed feeType, uint256 oldRate, uint256 newRate);

    // ============ 错误 Errors ============

    error InvalidFeeRate(uint256 rate);
    error InsufficientFeeBalance(address token, uint256 requested, uint256 available);
    error InvalidAmount(uint256 amount);

    // ============ 核心功能 Core Functions ============

    /**
     * @notice 收取交易手续费
     * @param token Token 地址
     * @param payer 支付者地址
     * @param amount 手续费金额 (USD, 1e18)
     * @param eventId 事件 ID
     * @param feeType 手续费类型("trade", "settlement", etc.)
     */
    function collectFee(
        address token,
        address payer,
        uint256 amount,
        uint256 eventId,
        string calldata feeType
    ) external;

    /**
     * @notice 提取手续费
     * @param token Token 地址
     * @param amount 提取金额 (USD, 1e18)
     */
    function withdrawFee(address token, uint256 amount) external;

    /**
     * @notice 设置手续费率
     * @param feeType 手续费类型
     * @param rate 费率(基点, 1-10000)
     */
    function setFeeRate(string calldata feeType, uint256 rate) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取协议 USD 手续费余额
     * @param token Token 地址 (保留参数以兼容旧接口)
     * @return balance 手续费余额 (USD, 1e18)
     */
    function getFeeBalance(address token) external view returns (uint256 balance);

    /**
     * @notice 获取协议 USD 手续费余额
     * @return balance 手续费余额 (USD, 1e18)
     */
    function getProtocolUsdFeeBalance() external view returns (uint256 balance);

    /**
     * @notice 获取手续费率
     * @param feeType 手续费类型
     * @return rate 费率(基点)
     */
    function getFeeRate(string calldata feeType) external view returns (uint256 rate);

    /**
     * @notice 计算手续费
     * @param amount 交易金额 (USD, 1e18)
     * @param feeType 手续费类型
     * @return fee 手续费金额
     */
    function calculateFee(uint256 amount, string calldata feeType) external view returns (uint256 fee);
}
