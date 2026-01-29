// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/core/IFundingManager.sol";

/**
 * @title FundingManager
 * @notice 资金 Manager - 负责资金管理、锁定和结算
 * @dev 每个 FundingManager 独立管理一组事件的资金
 */
contract FundingManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IFundingManager
{
    using SafeERC20 for IERC20;

    // ============ 常量 Constants ============

    /// @notice ETH 地址表示
    address public constant ETHAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice 价格精度(基点)
    uint256 public constant PRICE_PRECISION = 10000;

    /// @notice USD 统一精度(1e18 = 1 USD)
    uint256 public constant USD_PRECISION = 1e18;

    // ============ Modifiers ============

    /// @notice 仅 OrderBookManager 可调用
    modifier onlyOrderBookManager() {
        require(msg.sender == orderBookManager, "FundingManager: only orderBookManager");
        _;
    }

    /// @notice 仅 EventManager 可调用
    modifier onlyEventManager() {
        require(msg.sender == eventManager, "FundingManager: only eventManager");
        _;
    }

    /// @notice 仅 FeeVaultManager 可调用
    modifier onlyFeeVaultManager() {
        require(msg.sender == feeVaultManager, "FundingManager: only feeVaultManager");
        _;
    }

    // ============ 基础状态变量 Basic State Variables ============

    /// @notice OrderBookManager 合约地址(用于调用权限控制)
    address public orderBookManager;

    /// @notice EventManager 合约地址(用于调用权限控制)
    address public eventManager;

    /// @notice FeeVaultManager 合约地址(用于调用权限控制)
    address public feeVaultManager;

    /// @notice Token 配置
    struct TokenConfig {
        uint8 decimals;
        bool isEnabled;
    }

    /// @notice Token 配置映射
    mapping(address => TokenConfig) public tokenConfigs;

    /// @notice 支持的 Token 列表
    address[] public supportedTokens;

    // ============ 余额管理 Balance Management ============

    /// @notice Manager 实际持有 Token 流动性: token => amount
    mapping(address => uint256) public tokenLiquidity;

    /// @notice 用户统一 USD 余额: user => usdBalance (1e18)
    mapping(address => uint256) public userUsdBalances;

    // ============ 虚拟 Long Token 持仓 Virtual Long Token Positions ============

    /// @notice 用户虚拟 Long Token 持仓: user => eventId => outcomeIndex => longBalance
    /// @dev 代表用户持有的某个结果的 Long token 数量
    mapping(address => mapping(uint256 => mapping(uint8 => uint256))) public longPositions;

    /// @notice 订单锁定的 USD: orderId => lockedUSD
    /// @dev 买单锁定 USD,撮合时释放
    mapping(uint256 => uint256) public orderLockedUSD;

    /// @notice 订单锁定的 Long Token: orderId => lockedLong
    /// @dev 卖单锁定 Long token,撮合时释放
    mapping(uint256 => uint256) public orderLockedLong;

    // ============ 事件奖金池管理 Event Prize Pool ============

    /// @notice 事件奖金池: eventId => prizePool (统一 USD)
    mapping(uint256 => uint256) public eventPrizePool;

    /// @notice 事件结算状态: eventId => settled
    mapping(uint256 => bool) public eventSettled;

    /// @notice 事件获胜结果: eventId => winningOutcomeIndex
    mapping(uint256 => uint8) public eventWinningOutcome;

    /// @notice 用户领取状态: eventId => user => hasRedeemed
    mapping(uint256 => mapping(address => bool)) public userHasRedeemed;

    // ============ 统计信息 Statistics ============

    /// @notice 总入金量: token => totalDeposited
    mapping(address => uint256) public totalDeposited;

    /// @notice 总提现量: token => totalWithdrawn
    mapping(address => uint256) public totalWithdrawn;

    // ============ 事件结果信息 Event Outcome Info ============

    /// @notice 事件的所有结果索引: eventId => outcomeIndices[]
    /// @dev 用于铸造完整集合时遍历所有结果
    mapping(uint256 => uint8[]) public eventOutcomes;

    // ===== Upgradeable storage gap =====
    uint256[35] private __gap;

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
     * @param _eventManager EventManager 合约地址
     */
    function initialize(address initialOwner, address _orderBookManager, address _eventManager) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        orderBookManager = _orderBookManager;
        eventManager = _eventManager;
    }

    // ============ 基础功能 Basic Functions ============

    /**
     * @notice 用户入金 (Public - users can call directly)
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function deposit(address tokenAddress, uint256 amount) external payable whenNotPaused nonReentrant {
        // TEMP: disable ETH deposit entry; remove to re-enable
        require(tokenAddress != ETHAddress, "FundingManager: ETH deposits disabled");
        _deposit(msg.sender, tokenAddress, amount, msg.value);
    }

    /**
     * @notice 用户直接 ETH 入金
     */
    function depositEth() external payable whenNotPaused nonReentrant {
        revert("native token not supported yet");
        // _deposit(msg.sender, ETHAddress, msg.value, msg.value);
    }

    /**
     * @notice 用户直接 ERC20 入金
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function depositErc20(IERC20 tokenAddress, uint256 amount) external whenNotPaused nonReentrant {
        _deposit(msg.sender, address(tokenAddress), amount, 0);
    }

    function _deposit(address user, address tokenAddress, uint256 amount, uint256 ethValue) internal {
        TokenConfig memory config = tokenConfigs[tokenAddress];
        if (!config.isEnabled) revert TokenIsNotSupported(tokenAddress);
        if (amount == 0) revert LessThanZero(amount);

        // Handle token transfer
        if (tokenAddress == ETHAddress) {
            require(ethValue == amount, "FundingManager: ETH amount mismatch");
        } else {
            IERC20(tokenAddress).safeTransferFrom(user, address(this), amount);
        }

        // 更新余额 (统一 USD)
        uint256 usdAmount = _normalizeToUsd(tokenAddress, amount);
        userUsdBalances[user] += usdAmount;
        tokenLiquidity[tokenAddress] += amount;
        totalDeposited[tokenAddress] += amount;

        emit DepositToken(tokenAddress, user, amount);
    }

    /**
     * @notice 用户直接提现
     * @param tokenAddress Token 地址
     * @param usdAmount USD 数量 (1e18)
     */
    function withdrawDirect(address tokenAddress, uint256 usdAmount) external whenNotPaused nonReentrant {
        // TEMP: disable ETH withdraw entry; remove to re-enable
        require(tokenAddress != ETHAddress, "FundingManager: ETH withdrawals disabled");
        _withdraw(msg.sender, tokenAddress, payable(msg.sender), usdAmount);
    }

    /**
     * @notice 用户按 Token 数量直接提现
     * @param tokenAddress Token 地址
     * @param tokenAmount Token 数量
     */
    function withdrawTokenAmount(address tokenAddress, uint256 tokenAmount) external whenNotPaused nonReentrant {
        // TEMP: disable ETH withdraw entry; remove to re-enable
        require(tokenAddress != ETHAddress, "FundingManager: ETH withdrawals disabled");
        uint256 usdAmount = _normalizeToUsd(tokenAddress, tokenAmount);
        _withdraw(msg.sender, tokenAddress, payable(msg.sender), usdAmount);
    }

    function _withdraw(
        address user,
        address tokenAddress,
        address payable withdrawAddress,
        uint256 usdAmount
    ) internal {
        TokenConfig memory config = tokenConfigs[tokenAddress];
        if (!config.isEnabled) revert TokenIsNotSupported(tokenAddress);
        if (usdAmount == 0) revert LessThanZero(usdAmount);

        uint256 availableBalance = userUsdBalances[user];
        if (availableBalance < usdAmount) {
            revert InsufficientUsdBalance(user, usdAmount, availableBalance);
        }

        uint256 tokenAmount = _denormalizeFromUsd(tokenAddress, usdAmount);
        uint256 availableLiquidity = tokenLiquidity[tokenAddress];
        if (availableLiquidity < tokenAmount) {
            revert InsufficientTokenLiquidity(tokenAddress, tokenAmount, availableLiquidity);
        }

        // 更新余额
        userUsdBalances[user] -= usdAmount;
        tokenLiquidity[tokenAddress] -= tokenAmount;
        totalWithdrawn[tokenAddress] += tokenAmount;

        // 转账
        if (tokenAddress == ETHAddress) {
            (bool sent, ) = withdrawAddress.call{value: tokenAmount}("");
            require(sent, "FundingManager: failed to send ETH");
        } else {
            IERC20(tokenAddress).safeTransfer(withdrawAddress, tokenAmount);
        }

        emit WithdrawToken(tokenAddress, user, withdrawAddress, tokenAmount);
    }

    /**
     * @notice 配置支持的 Token
     * @param token Token 地址
     * @param decimals Token decimals
     * @param enabled 是否启用
     */
    function configureToken(address token, uint8 decimals, bool enabled) external onlyOwner nonReentrant {
        require(token != address(0), "FundingManager: invalid token");
        if (decimals > 18) revert InvalidTokenDecimals(decimals);

        TokenConfig storage config = tokenConfigs[token];
        config.decimals = decimals;
        config.isEnabled = enabled;

        if (enabled) {
            // 检查是否已存在,避免重复添加
            bool exists = false;
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                if (supportedTokens[i] == token) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                supportedTokens.push(token);
            }
        }

        emit TokenConfigured(token, decimals, enabled, block.chainid);
    }

    function _normalizeToUsd(address token, uint256 rawAmount) internal view returns (uint256) {
        TokenConfig memory config = tokenConfigs[token];
        if (!config.isEnabled) revert TokenIsNotSupported(token);
        if (config.decimals > 18) revert InvalidTokenDecimals(config.decimals);

        uint256 factor = 10 ** (18 - config.decimals);
        return rawAmount * factor;
    }

    function _denormalizeFromUsd(address token, uint256 usdAmount) internal view returns (uint256) {
        TokenConfig memory config = tokenConfigs[token];
        if (!config.isEnabled) revert TokenIsNotSupported(token);
        if (config.decimals > 18) revert InvalidTokenDecimals(config.decimals);

        uint256 factor = 10 ** (18 - config.decimals);
        return usdAmount / factor;
    }

    /**
     * @notice 将 Token 数量归一化为 USD (1e18)
     * @param token Token 地址
     * @param rawAmount Token 数量
     */
    function normalizeToUsd(address token, uint256 rawAmount) external view returns (uint256) {
        return _normalizeToUsd(token, rawAmount);
    }

    /**
     * @notice 将 USD 数量反归一化为 Token 数量
     * @param token Token 地址
     * @param usdAmount USD 数量 (1e18)
     */
    function denormalizeFromUsd(address token, uint256 usdAmount) external view returns (uint256) {
        return _denormalizeFromUsd(token, usdAmount);
    }

    /**
     * @notice FeeVaultManager 收取协议费用(扣减用户 USD 余额)
     * @param payer 支付者地址
     * @param usdAmount USD 数量 (1e18)
     */
    function collectProtocolFee(address payer, uint256 usdAmount) external onlyFeeVaultManager nonReentrant {
        if (usdAmount == 0) revert LessThanZero(usdAmount);
        uint256 availableBalance = userUsdBalances[payer];
        if (availableBalance < usdAmount) {
            revert InsufficientUsdBalance(payer, usdAmount, availableBalance);
        }
        userUsdBalances[payer] -= usdAmount;
    }

    /**
     * @notice FeeVaultManager 提取协议流动性
     * @param token Token 地址
     * @param amount Token 数量
     * @param recipient 接收地址
     */
    function withdrawLiquidity(
        address token,
        uint256 amount,
        address recipient
    ) external onlyFeeVaultManager nonReentrant {
        if (amount == 0) revert LessThanZero(amount);
        TokenConfig memory config = tokenConfigs[token];
        if (!config.isEnabled) revert TokenIsNotSupported(token);

        uint256 availableLiquidity = tokenLiquidity[token];
        if (availableLiquidity < amount) {
            revert InsufficientTokenLiquidity(token, amount, availableLiquidity);
        }

        tokenLiquidity[token] -= amount;

        if (token == ETHAddress) {
            (bool sent, ) = payable(recipient).call{value: amount}("");
            require(sent, "FundingManager: failed to send ETH");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    // ============ 核心资金管理 Core Funding Functions ============

    // ============ 虚拟 Long Token 管理 Virtual Long Token Management ============

    /**
     * @notice 注册事件的结果选项
     * @param eventId 事件 ID
     * @param outcomeCount 结果数量
     */
    function registerEvent(uint256 eventId, uint8 outcomeCount) external onlyOrderBookManager nonReentrant {
        require(eventOutcomes[eventId].length == 0, "FundingManager: event already registered");
        require(outcomeCount > 0, "FundingManager: empty outcomes");

        for (uint8 i = 0; i < outcomeCount; i++) {
            eventOutcomes[eventId].push(i);
        }
    }

    /**
     * @notice 用户直接铸造完整集合
     * @param eventId 事件 ID
     * @param usdAmount 铸造数量 (USD, 1e18)
     */
    function mintCompleteSetDirect(uint256 eventId, uint256 usdAmount) external whenNotPaused nonReentrant {
        _mintCompleteSet(msg.sender, eventId, usdAmount);
    }

    function _mintCompleteSet(address user, uint256 eventId, uint256 usdAmount) internal {
        require(usdAmount > 0, "FundingManager: amount must be greater than zero");
        require(eventOutcomes[eventId].length > 0, "FundingManager: event not registered");

        uint256 availableBalance = userUsdBalances[user];
        if (availableBalance < usdAmount) {
            revert InsufficientUsdBalance(user, usdAmount, availableBalance);
        }

        // 扣除 USD
        userUsdBalances[user] -= usdAmount;

        // 为每个 outcome 铸造 Long token
        uint8[] memory outcomes = eventOutcomes[eventId];
        for (uint8 i = 0; i < outcomes.length; i++) {
            longPositions[user][eventId][i] += usdAmount;
        }

        // 增加奖金池 (铸造时锁定的 USD 进入奖金池)
        eventPrizePool[eventId] += usdAmount;

        emit CompleteSetMinted(user, eventId, usdAmount);
    }

    /**
     * @notice 用户直接销毁完整集合
     * @param eventId 事件 ID
     * @param usdAmount 销毁数量 (USD, 1e18)
     */
    function burnCompleteSetDirect(uint256 eventId, uint256 usdAmount) external whenNotPaused nonReentrant {
        _burnCompleteSet(msg.sender, eventId, usdAmount);
    }

    function _burnCompleteSet(address user, uint256 eventId, uint256 usdAmount) internal {
        require(usdAmount > 0, "FundingManager: amount must be greater than zero");
        require(eventOutcomes[eventId].length > 0, "FundingManager: event not registered");

        // 检查并销毁每个 outcome 的 Long token
        uint8[] storage outcomes = eventOutcomes[eventId];
        for (uint8 i = 0; i < outcomes.length; i++) {
            uint256 position = longPositions[user][eventId][i];
            if (position < usdAmount) {
                revert InsufficientLongPosition(user, eventId, i);
            }
            longPositions[user][eventId][i] -= usdAmount;
        }

        // 返还 USD
        userUsdBalances[user] += usdAmount;

        // 减少奖金池 (销毁时 USD 从奖金池返还给用户)
        eventPrizePool[eventId] -= usdAmount;

        emit CompleteSetBurned(user, eventId, usdAmount);
    }

    // ============ 订单资金管理 Order Funding Management ============

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
    ) external onlyOrderBookManager nonReentrant {
        require(amount > 0, "FundingManager: amount must be greater than zero");

        if (isBuyOrder) {
            // 买单: 锁定 USD
            uint256 availableBalance = userUsdBalances[user];
            if (availableBalance < amount) {
                revert InsufficientUsdBalance(user, amount, availableBalance);
            }

            userUsdBalances[user] -= amount;
            orderLockedUSD[orderId] = amount;

            emit FundsLocked(user, amount, eventId, outcomeIndex);
        } else {
            // 卖单: 锁定 Long Token
            uint256 position = longPositions[user][eventId][outcomeIndex];
            if (position < amount) {
                revert InsufficientLongPosition(user, eventId, outcomeIndex);
            }

            longPositions[user][eventId][outcomeIndex] -= amount;
            orderLockedLong[orderId] = amount;

            emit FundsLocked(user, amount, eventId, outcomeIndex);
        }
    }

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
    ) external onlyOrderBookManager nonReentrant {
        if (isBuyOrder) {
            // 买单: 解锁 USD
            uint256 lockedAmount = orderLockedUSD[orderId];
            require(lockedAmount > 0, "FundingManager: no locked USD");

            userUsdBalances[user] += lockedAmount;
            orderLockedUSD[orderId] = 0;

            emit FundsUnlocked(user, lockedAmount, eventId, outcomeIndex);
        } else {
            // 卖单: 解锁 Long Token
            uint256 lockedAmount = orderLockedLong[orderId];
            require(lockedAmount > 0, "FundingManager: no locked Long");

            longPositions[user][eventId][outcomeIndex] += lockedAmount;
            orderLockedLong[orderId] = 0;

            emit FundsUnlocked(user, lockedAmount, eventId, outcomeIndex);
        }
    }

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
    ) external onlyOrderBookManager nonReentrant {
        // 计算买家支付金额
        uint256 payment = (matchAmount * matchPrice) / PRICE_PRECISION;

        // 买家: 消耗锁定的 USD,获得 Long Token
        require(orderLockedUSD[buyOrderId] >= payment, "FundingManager: insufficient locked USD");
        orderLockedUSD[buyOrderId] -= payment;
        longPositions[buyer][eventId][outcomeIndex] += matchAmount;

        // 卖家: 消耗锁定的 Long Token,获得 USD
        require(orderLockedLong[sellOrderId] >= matchAmount, "FundingManager: insufficient locked Long");
        orderLockedLong[sellOrderId] -= matchAmount;
        userUsdBalances[seller] += payment;

        // 注意: 撮合交易不改变奖金池
        // 奖金池只在 mintCompleteSet (增加) 和 burnCompleteSet (减少) 时变化
        // 因为奖金池 = 所有流通的完整集合价值总和

        emit OrderSettled(buyOrderId, sellOrderId, matchAmount);
    }

    // ============ 事件结算 Event Settlement ============

    /**
     * @notice 标记事件已结算 (由 OrderBookManager 调用)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引
     */
    function markEventSettled(uint256 eventId, uint8 winningOutcomeIndex) external onlyEventManager nonReentrant {
        require(!eventSettled[eventId], "FundingManager: event already settled");

        eventSettled[eventId] = true;
        eventWinningOutcome[eventId] = winningOutcomeIndex;

        emit EventMarkedSettled(eventId, winningOutcomeIndex, eventPrizePool[eventId]);
    }

    /**
     * @notice 用户领取获胜奖金 (1 Long = 1 USD)
     * @param eventId 事件 ID
     */
    function redeemWinnings(uint256 eventId) external whenNotPaused nonReentrant {
        require(eventSettled[eventId], "FundingManager: event not settled");
        require(!userHasRedeemed[eventId][msg.sender], "FundingManager: already redeemed");

        uint8 winningOutcome = eventWinningOutcome[eventId];
        uint256 userPosition = longPositions[msg.sender][eventId][winningOutcome];
        require(userPosition > 0, "FundingManager: no winning position");

        userHasRedeemed[eventId][msg.sender] = true;
        longPositions[msg.sender][eventId][winningOutcome] = 0;
        userUsdBalances[msg.sender] += userPosition;
        eventPrizePool[eventId] -= userPosition;

        emit WinningsRedeemed(msg.sender, eventId, winningOutcome, userPosition);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取用户统一 USD 余额
     * @param user 用户地址
     * @return balance USD 余额 (1e18)
     */
    function getUserUsdBalance(address user) external view returns (uint256) {
        return userUsdBalances[user];
    }

    /**
     * @notice 获取用户 Long Token 持仓
     * @param user 用户地址
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @return position Long Token 数量
     */
    function getLongPosition(address user, uint256 eventId, uint8 outcomeIndex) external view returns (uint256) {
        return longPositions[user][eventId][outcomeIndex];
    }

    /**
     * @notice 获取订单锁定的 USD
     * @param orderId 订单 ID
     * @return locked 锁定的 USD 数量
     */
    function getOrderLockedUSD(uint256 orderId) external view returns (uint256) {
        return orderLockedUSD[orderId];
    }

    /**
     * @notice 获取订单锁定的 Long Token
     * @param orderId 订单 ID
     * @return locked 锁定的 Long Token 数量
     */
    function getOrderLockedLong(uint256 orderId) external view returns (uint256) {
        return orderLockedLong[orderId];
    }

    /**
     * @notice 获取事件奖金池
     * @param eventId 事件 ID
     * @return pool 奖金池金额
     */
    function getEventPrizePool(uint256 eventId) external view returns (uint256) {
        return eventPrizePool[eventId];
    }

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
    ) external view returns (bool canRedeem, uint256 winningPosition) {
        if (!eventSettled[eventId]) return (false, 0);
        if (userHasRedeemed[eventId][user]) return (false, 0);

        uint8 winningOutcome = eventWinningOutcome[eventId];
        winningPosition = longPositions[user][eventId][winningOutcome];
        canRedeem = winningPosition > 0;
    }

    /**
     * @notice 获取 Token 流动性
     * @param token Token 地址
     * @return liquidity Token 流动性
     */
    function getTokenLiquidity(address token) external view returns (uint256) {
        return tokenLiquidity[token];
    }

    /**
     * @notice 获取支持的 Token 列表
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice 检查是否可提现指定 USD 数量
     * @param token Token 地址
     * @param usdAmount USD 数量 (1e18)
     * @return can 是否可提现
     */
    function canWithdraw(address token, uint256 usdAmount) external view returns (bool) {
        uint256 tokenAmount = _denormalizeFromUsd(token, usdAmount);
        return tokenLiquidity[token] >= tokenAmount;
    }

    /**
     * @notice 检查事件是否已结算
     * @param eventId 事件 ID
     * @return settled 是否已结算
     */
    function isEventSettled(uint256 eventId) external view returns (bool) {
        return eventSettled[eventId];
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 更新 OrderBookManager 地址
     * @param _orderBookManager 新地址
     */
    function setOrderBookManager(address _orderBookManager) external onlyOwner nonReentrant {
        require(_orderBookManager != address(0), "FundingManager: invalid address");
        orderBookManager = _orderBookManager;
    }

    /**
     * @notice 更新 EventManager 地址
     * @param _eventManager 新地址
     */
    function setEventManager(address _eventManager) external onlyOwner nonReentrant {
        require(_eventManager != address(0), "FundingManager: invalid address");
        eventManager = _eventManager;
    }

    /**
     * @notice 更新 FeeVaultManager 地址
     * @param _feeVaultManager 新地址
     */
    function setFeeVaultManager(address _feeVaultManager) external onlyOwner nonReentrant {
        require(_feeVaultManager != address(0), "FundingManager: invalid address");
        feeVaultManager = _feeVaultManager;
    }

    // ============ 紧急控制 Emergency Control ============

    /**
     * @notice 暂停合约
     */
    // ============ 接收 ETH ============

    receive() external payable {}
}
