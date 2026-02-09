// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IFundingManager
 * @notice 资金 Manager 接口 - 负责资金管理、锁定和结算
 * @dev 每个 FundingManager 独立管理一组事件的资金
 */
interface IFundingManager {
    // ============ 常量 Constants ============

    /// @notice ETH 地址表示
    function NATIVE_TOKEN() external view returns (address);

    /// @notice USD 统一精度(1e18 = 1 USD)
    function USD_PRECISION() external view returns (uint256);

    // ============ 事件 Events ============

    /// @notice 用户入金事件
    event DepositToken(address indexed tokenAddress, address indexed sender, uint256 amount);

    /// @notice 用户提现事件
    event WithdrawToken(address indexed tokenAddress, address indexed sender, address withdrawAddress, uint256 amount);

    /// @notice Token 配置事件
    event TokenConfigured(address indexed token, uint8 decimals, bool enabled, uint256 chainId);

    /// @notice 资金锁定事件
    event FundsLocked(address indexed user, uint256 amount, uint256 indexed eventId, uint8 outcomeIndex);

    /// @notice 资金解锁事件
    event FundsUnlocked(address indexed user, uint256 amount, uint256 indexed eventId, uint8 outcomeIndex);

    /// @notice 订单结算事件
    event OrderSettled(uint256 indexed buyOrderId, uint256 indexed sellOrderId, uint256 amount);

    /// @notice 事件标记已结算事件
    event EventMarkedSettled(uint256 indexed eventId, uint8 winningOutcomeIndex, uint256 prizePool);

    /// @notice 用户领取奖金事件
    event WinningsRedeemed(address indexed user, uint256 indexed eventId, uint8 winningOutcomeIndex, uint256 amount);

    /// @notice 完整集合铸造事件
    event CompleteSetMinted(address indexed user, uint256 indexed eventId, uint256 amount);

    /// @notice 完整集合销毁事件
    event CompleteSetBurned(address indexed user, uint256 indexed eventId, uint256 amount);

    /// @notice 单笔入金最低金额更新事件
    event MinDepositPerTxnUsdUpdated(uint256 newMinDeposit);

    /// @notice Token 可用最低余额更新事件
    event MinTokenBalanceUsdUpdated(uint256 newMinBalance);

    // ============ 错误 Errors ============

    error LessThanZero(uint256 amount);
    error TokenIsNotSupported(address tokenAddress);
    error InvalidTokenDecimals(uint8 decimals);
    error InsufficientUsdBalance(address user, uint256 required, uint256 available);
    error InsufficientTokenLiquidity(address token, uint256 required, uint256 available);
    error InsufficientLongPosition(address user, uint256 eventId, uint8 outcomeIndex);

    // ============ 基础功能 Basic Functions ============

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     */
    function initialize(address initialOwner) external;

    /**
     * @notice 暂停合约
     */
    function pause() external;

    /**
     * @notice 恢复合约
     */
    function unpause() external;

    /**
     * @notice 用户入金 (Public - users can call directly)
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function deposit(address tokenAddress, uint256 amount) external payable;

    /**
     * @notice 用户直接 ETH 入金
     */
    function depositEth() external payable;

    /**
     * @notice 用户直接 ERC20 入金
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function depositErc20(IERC20 tokenAddress, uint256 amount) external;

    /**
     * @notice 用户直接提现
     * @param tokenAddress Token 地址
     * @param usdAmount USD 数量 (1e18)
     */
    function withdrawDirect(address tokenAddress, uint256 usdAmount) external;

    /**
     * @notice 用户按 Token 数量直接提现
     * @param tokenAddress Token 地址
     * @param tokenAmount Token 数量
     */
    function withdrawTokenAmount(address tokenAddress, uint256 tokenAmount) external;

    /**
     * @notice 配置支持的 Token
     * @param token Token 地址
     * @param decimals Token decimals
     * @param enabled 是否启用
     */
    function configureToken(address token, uint8 decimals, bool enabled) external;

    /**
     * @notice 将 Token 数量归一化为 USD (1e18)
     * @param token Token 地址
     * @param rawAmount Token 数量
     */
    function normalizeToUsd(address token, uint256 rawAmount) external view returns (uint256);

    /**
     * @notice 将 USD 数量反归一化为 Token 数量
     * @param token Token 地址
     * @param usdAmount USD 数量 (1e18)
     */
    function denormalizeFromUsd(address token, uint256 usdAmount) external view returns (uint256);

    /**
     * @notice 获取 Token 价格 (USD, 1e18)
     */
    function getTokenPrice(address token) external view returns (uint256);

    /**
     * @notice 获取单笔入金最低金额 (USD, 1e18)
     */
    function getMinDepositPerTxnUsd() external view returns (uint256);

    /**
     * @notice 设置单笔入金最低金额 (USD, 1e18)
     */
    function setMinDepositPerTxnUsd(uint256 newMin) external;

    /**
     * @notice 获取用户钱包最低余额要求 (USD, 1e18)
     */
    function getMinTokenBalanceUsd() external view returns (uint256);

    /**
     * @notice 设置用户钱包最低余额要求 (USD, 1e18)
     */
    function setMinTokenBalanceUsd(uint256 newMin) external;

    /**
     * @notice 获取用户钱包在所有支持 Token 上的余额
     * @param user 用户地址
     * @return tokens Token 地址数组
     * @return balances Token 数量数组 (按 Token 原始精度,等同于 token.balanceOf(user))
     */
    function getAllTokenBalances(
        address user
    ) external view returns (address[] memory tokens, uint256[] memory balances);

    /**
     * @notice FeeVaultManager 收取协议费用(扣减用户 USD 余额)
     * @param payer 支付者地址
     * @param usdAmount USD 数量 (1e18)
     */
    function collectProtocolFee(address payer, uint256 usdAmount) external;

    /**
     * @notice FeeVaultManager 提取协议流动性
     * @param token Token 地址
     * @param amount Token 数量
     * @param recipient 接收地址
     */
    function withdrawLiquidity(address token, uint256 amount, address recipient) external;

    // ============ 核心资金管理 Core Funding Functions ============

    /**
     * @notice 注册事件的结果选项
     * @param eventId 事件 ID
     * @param outcomeCount 结果数量
     */
    function registerEvent(uint256 eventId, uint8 outcomeCount) external;

    /**
     * @notice 用户直接铸造完整集合
     * @param eventId 事件 ID
     * @param usdAmount 铸造数量 (USD, 1e18)
     */
    function mintCompleteSetDirect(uint256 eventId, uint256 usdAmount) external;

    /**
     * @notice 用户直接销毁完整集合
     * @param eventId 事件 ID
     * @param usdAmount 销毁数量 (USD, 1e18)
     */
    function burnCompleteSetDirect(uint256 eventId, uint256 usdAmount) external;

    /**
     * @notice 下单时锁定资金或 Long Token
     * @param user 用户地址
     * @param orderId 订单 ID
     * @param isBuyOrder 是否为买单
     * @param amount 锁定数量 (买单锁 USD,卖单锁 Long)
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     */
    function lockForOrder(
        address user,
        uint256 orderId,
        bool isBuyOrder,
        uint256 amount,
        uint256 eventId,
        uint8 outcomeIndex
    ) external;

    /**
     * @notice 撤单时解锁资金或 Long Token
     * @param user 用户地址
     * @param orderId 订单 ID
     * @param isBuyOrder 是否为买单
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     */
    function unlockForOrder(
        address user,
        uint256 orderId,
        bool isBuyOrder,
        uint256 eventId,
        uint8 outcomeIndex
    ) external;

    /**
     * @notice 撮合成交时结算资金 (买家用 USD 换 Long,卖家用 Long 换 USD)
     * @param buyOrderId 买单 ID
     * @param sellOrderId 卖单 ID
     * @param buyer 买家地址
     * @param seller 卖家地址
     * @param matchAmount 成交数量
     * @param matchPrice 成交价格 (basis points, 1-10000)
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     */
    function settleMatchedOrder(
        uint256 buyOrderId,
        uint256 sellOrderId,
        address buyer,
        address seller,
        uint256 matchAmount,
        uint256 matchPrice,
        uint256 eventId,
        uint8 outcomeIndex
    ) external;

    /**
     * @notice 标记事件已结算
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引
     */
    function markEventSettled(uint256 eventId, uint8 winningOutcomeIndex) external;

    /**
     * @notice 用户领取获胜奖金
     * @param eventId 事件 ID
     */
    function redeemWinnings(uint256 eventId) external;

    /**
     * @notice 检查用户是否可以领取奖金
     * @param eventId 事件 ID
     * @param user 用户地址
     * @return canRedeem 是否可领取
     * @return winningPosition 获胜持仓数量
     */
    function canRedeemWinnings(
        uint256 eventId,
        address user
    ) external view returns (bool canRedeem, uint256 winningPosition);

    /**
     * @notice 检查用户是否已领取
     * @param eventId 事件 ID
     * @param user 用户地址
     * @return 是否已领取
     */
    function userHasRedeemed(uint256 eventId, address user) external view returns (bool);

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取用户统一 USD 余额
     * @param user 用户地址
     * @return balance USD 余额 (1e18)
     */
    function getUserUsdBalance(address user) external view returns (uint256);

    /**
     * @notice 获取用户 Long Token 持仓
     * @param user 用户地址
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @return position Long Token 数量
     */
    function getLongPosition(address user, uint256 eventId, uint8 outcomeIndex) external view returns (uint256);

    /**
     * @notice 获取订单锁定的 USD
     * @param orderId 订单 ID
     * @return locked 锁定的 USD 数量
     */
    function getOrderLockedUsd(uint256 orderId) external view returns (uint256);

    /**
     * @notice 获取订单锁定的 Long Token
     * @param orderId 订单 ID
     * @return locked 锁定的 Long Token 数量
     */
    function getOrderLockedLong(uint256 orderId) external view returns (uint256);

    /**
     * @notice 获取事件奖金池
     * @param eventId 事件 ID
     * @return pool 奖金池金额
     */
    function getEventPrizePool(uint256 eventId) external view returns (uint256);

    /**
     * @notice 获取 Token 流动性
     * @param token Token 地址
     * @return liquidity Token 流动性
     */
    function getTokenLiquidity(address token) external view returns (uint256);

    /**
     * @notice 获取支持的 Token 列表
     */
    function getSupportedTokens() external view returns (address[] memory);

    /**
     * @notice 检查是否可提现指定 USD 数量
     * @param token Token 地址
     * @param usdAmount USD 数量 (1e18)
     * @return can 是否可提现
     */
    function canWithdraw(address token, uint256 usdAmount) external view returns (bool);

    /**
     * @notice 检查事件是否已结算
     * @param eventId 事件 ID
     * @return settled 是否已结算
     */
    function isEventSettled(uint256 eventId) external view returns (bool);

    /**
     * @notice 获取 Token 配置
     * @param token Token 地址
     * @return decimals Token decimals
     * @return isEnabled 是否启用
     */
    function tokenConfigs(address token) external view returns (uint8 decimals, bool isEnabled);

    /**
     * @notice 获取 OrderBookManager 地址
     */
    function orderBookManager() external view returns (address);

    /**
     * @notice 获取 EventManager 地址
     */
    function eventManager() external view returns (address);

    /**
     * @notice 获取 FeeVaultManager 地址
     */
    function feeVaultManager() external view returns (address);

    /**
     * @notice 更新 OrderBookManager 地址
     * @param _orderBookManager 新地址
     */
    function setOrderBookManager(address _orderBookManager) external;

    /**
     * @notice 更新 EventManager 地址
     * @param _eventManager 新地址
     */
    function setEventManager(address _eventManager) external;

    /**
     * @notice 更新 FeeVaultManager 地址
     * @param _feeVaultManager 新地址
     */
    function setFeeVaultManager(address _feeVaultManager) external;
}
