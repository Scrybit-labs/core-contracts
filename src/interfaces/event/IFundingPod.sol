// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IFundingPod
 * @notice 资金 Pod 接口 - 负责资金管理、锁定和结算
 * @dev 每个 FundingPod 独立管理一组事件的资金
 */
interface IFundingPod {
    // ============ 常量 Constants ============

    /// @notice ETH 地址表示
    function ETHAddress() external view returns (address);

    // ============ 事件 Events ============

    /// @notice 用户入金事件
    event DepositToken(address indexed tokenAddress, address indexed sender, uint256 amount);

    /// @notice 用户提现事件
    event WithdrawToken(address indexed tokenAddress, address indexed sender, address withdrawAddress, uint256 amount);

    /// @notice Token 支持状态变更事件
    event SetSupportTokenEvent(address indexed token, bool isSupport, uint256 chainId);

    /// @notice 资金锁定事件
    event FundsLocked(
        address indexed user, address indexed token, uint256 amount, uint256 indexed eventId, uint256 outcomeId
    );

    /// @notice 资金解锁事件
    event FundsUnlocked(
        address indexed user, address indexed token, uint256 amount, uint256 indexed eventId, uint256 outcomeId
    );

    /// @notice 订单结算事件
    event OrderSettled(uint256 indexed buyOrderId, uint256 indexed sellOrderId, uint256 amount, address indexed token);

    /// @notice 事件结算事件
    event EventSettled(
        uint256 indexed eventId,
        uint256 winningOutcomeId,
        address indexed token,
        uint256 prizePool,
        uint256 winnersCount
    );

    // ============ 错误 Errors ============

    error LessThanZero(uint256 amount);
    error TokenIsNotSupported(address ERC20Address);
    error InsufficientBalance(address user, address token, uint256 required, uint256 available);
    error InsufficientLockedBalance(address user, address token, uint256 eventId, uint256 outcomeId);
    error EventAlreadySettled(uint256 eventId);
    error InvalidWinningOutcome(uint256 eventId, uint256 outcomeId);

    // ============ 基础功能 Basic Functions ============

    /**
     * @notice 用户入金
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function deposit(address tokenAddress, uint256 amount) external;

    /**
     * @notice 用户提现
     * @param tokenAddress Token 地址
     * @param withdrawAddress 提现目标地址
     * @param amount 金额
     */
    function withdraw(address tokenAddress, address payable withdrawAddress, uint256 amount) external;

    /**
     * @notice 设置支持的 ERC20 Token
     * @param ERC20Address Token 地址
     * @param isValid 是否支持
     */
    function setSupportERC20Token(address ERC20Address, bool isValid) external;

    // ============ 核心资金管理 Core Funding Functions ============

    /**
     * @notice 下单时锁定资金
     * @param user 用户地址
     * @param token Token 地址
     * @param amount 锁定金额
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     */
    function lockOnOrderPlaced(address user, address token, uint256 amount, uint256 eventId, uint256 outcomeId) external;

    /**
     * @notice 撤单时解锁资金
     * @param user 用户地址
     * @param token Token 地址
     * @param amount 解锁金额
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     */
    function unlockOnOrderCancelled(address user, address token, uint256 amount, uint256 eventId, uint256 outcomeId)
        external;

    /**
     * @notice 撮合成交时结算资金
     * @param buyer 买家地址
     * @param seller 卖家地址
     * @param token Token 地址
     * @param amount 成交数量
     * @param price 成交价格 (basis points, 1-10000)
     * @param eventId 事件 ID
     * @param buyOutcomeId 买家购买的结果 ID
     * @param sellOutcomeId 卖家出售的结果 ID
     */
    function settleMatchedOrder(
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint256 price,
        uint256 eventId,
        uint256 buyOutcomeId,
        uint256 sellOutcomeId
    ) external;

    /**
     * @notice 事件结算时分配奖金
     * @param eventId 事件 ID
     * @param winningOutcomeId 获胜结果 ID
     * @param token Token 地址
     * @param winners 获胜者地址列表
     * @param positions 获胜者持仓列表
     */
    function settleEvent(
        uint256 eventId,
        uint256 winningOutcomeId,
        address token,
        address[] calldata winners,
        uint256[] calldata positions
    ) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取 Pod 总 Token 余额
     * @param token Token 地址
     * @return balance Token 总余额
     */
    function tokenBalances(address token) external view returns (uint256);

    /**
     * @notice 获取用户可用余额
     * @param user 用户地址
     * @param token Token 地址
     * @return balance 可用余额
     */
    function getUserBalance(address user, address token) external view returns (uint256);

    /**
     * @notice 获取用户在某事件某结果的锁定余额
     * @param user 用户地址
     * @param token Token 地址
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @return locked 锁定金额
     */
    function getLockedBalance(address user, address token, uint256 eventId, uint256 outcomeId)
        external
        view
        returns (uint256);

    /**
     * @notice 获取事件奖金池
     * @param eventId 事件 ID
     * @param token Token 地址
     * @return pool 奖金池金额
     */
    function getEventPrizePool(uint256 eventId, address token) external view returns (uint256);

    /**
     * @notice 检查事件是否已结算
     * @param eventId 事件 ID
     * @return settled 是否已结算
     */
    function isEventSettled(uint256 eventId) external view returns (bool);
}
