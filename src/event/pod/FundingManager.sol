// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/event/IFundingManager.sol";

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

    // ============ 基础状态变量 Basic State Variables ============

    /// @notice OrderBookManager 合约地址(用于调用权限控制)
    address public orderBookManager;

    /// @notice EventManager 合约地址(用于调用权限控制)
    address public eventManager;

    /// @notice 支持的 Token 列表
    address[] public SupportTokens;

    /// @notice Token 是否支持映射
    mapping(address => bool) public IsSupportToken;

    // ============ 余额管理 Balance Management ============

    /// @notice Manager 总 Token 余额: token => totalBalance
    mapping(address => uint256) public tokenBalances;

    /// @notice 用户可用余额: user => token => balance
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    // ============ 虚拟 Long Token 持仓 Virtual Long Token Positions ============

    /// @notice 用户虚拟 Long Token 持仓: user => token => eventId => outcomeIndex => longBalance
    /// @dev 代表用户持有的某个结果的 Long token 数量
    mapping(address => mapping(address => mapping(uint256 => mapping(uint8 => uint256)))) public longPositions;

    /// @notice 订单锁定的 USDT: orderId => lockedUSDT
    /// @dev 买单锁定 USDT,撮合时释放
    mapping(uint256 => uint256) public orderLockedUSDT;

    /// @notice 订单锁定的 Long Token: orderId => eventId => outcomeIndex => lockedLong
    /// @dev 卖单锁定 Long token,撮合时释放
    mapping(uint256 => mapping(uint256 => mapping(uint8 => uint256))) public orderLockedLong;

    // ============ 事件奖金池管理 Event Prize Pool ============

    /// @notice 事件奖金池: eventId => token => prizePool
    mapping(uint256 => mapping(address => uint256)) public eventPrizePool;

    /// @notice 事件结算状态: eventId => settled
    mapping(uint256 => bool) public eventSettled;

    /// @notice 事件获胜结果: eventId => winningOutcomeIndex
    mapping(uint256 => uint8) public eventWinningOutcome;

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

    /**
     * @notice Authorizes upgrade to new implementation
     * @dev Only owner can upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ 基础功能 Basic Functions ============

    /**
     * @notice 用户入金 (Public - users can call directly)
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function deposit(address tokenAddress, uint256 amount) external payable whenNotPaused nonReentrant {
        _deposit(msg.sender, tokenAddress, amount, msg.value);
    }

    /**
     * @notice 用户直接 ETH 入金
     */
    function depositEth() external payable whenNotPaused nonReentrant {
        _deposit(msg.sender, ETHAddress, msg.value, msg.value);
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
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        // Handle token transfer
        if (tokenAddress == ETHAddress) {
            require(ethValue == amount, "FundingManager: ETH amount mismatch");
        } else {
            IERC20(tokenAddress).safeTransferFrom(user, address(this), amount);
        }

        // 更新余额
        userTokenBalances[user][tokenAddress] += amount;
        tokenBalances[tokenAddress] += amount;
        totalDeposited[tokenAddress] += amount;

        emit DepositToken(tokenAddress, user, amount);
    }

    /**
     * @notice 用户直接提现
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function withdrawDirect(address tokenAddress, uint256 amount) external whenNotPaused nonReentrant {
        _withdraw(msg.sender, tokenAddress, payable(msg.sender), amount);
    }

    function _withdraw(address user, address tokenAddress, address payable withdrawAddress, uint256 amount) internal {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        uint256 availableBalance = userTokenBalances[user][tokenAddress];

        if (availableBalance < amount) {
            revert InsufficientBalance(user, tokenAddress, amount, availableBalance);
        }

        // 更新余额
        userTokenBalances[user][tokenAddress] -= amount;
        tokenBalances[tokenAddress] -= amount;
        totalWithdrawn[tokenAddress] += amount;

        // 转账
        if (tokenAddress == ETHAddress) {
            (bool sent, ) = withdrawAddress.call{value: amount}("");
            require(sent, "FundingManager: failed to send ETH");
        } else {
            IERC20(tokenAddress).safeTransfer(withdrawAddress, amount);
        }

        emit WithdrawToken(tokenAddress, user, withdrawAddress, amount);
    }

    /**
     * @notice 设置支持的 ERC20 Token
     * @param ERC20Address Token 地址
     * @param isValid 是否支持
     */
    function setSupportERC20Token(address ERC20Address, bool isValid) external onlyOwner nonReentrant {
        IsSupportToken[ERC20Address] = isValid;

        if (isValid) {
            // 检查是否已存在,避免重复添加
            bool exists = false;
            for (uint256 i = 0; i < SupportTokens.length; i++) {
                if (SupportTokens[i] == ERC20Address) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                SupportTokens.push(ERC20Address);
            }
        }

        emit SetSupportTokenEvent(ERC20Address, isValid, block.chainid);
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
     * @notice 铸造完整集合 (用户支付 amount USDT,获得所有结果各 amount 份 Long)
     * @param user 用户地址
     * @param eventId 事件 ID
     * @param token Token 地址
     * @param amount 铸造数量
     */
    /**
     * @notice 用户直接铸造完整集合
     * @param eventId 事件 ID
     * @param token Token 地址
     * @param amount 铸造数量
     */
    function mintCompleteSetDirect(uint256 eventId, address token, uint256 amount) external whenNotPaused nonReentrant {
        _mintCompleteSet(msg.sender, eventId, token, amount);
    }

    function _mintCompleteSet(address user, uint256 eventId, address token, uint256 amount) internal {
        require(amount > 0, "FundingManager: amount must be greater than zero");
        require(eventOutcomes[eventId].length > 0, "FundingManager: event not registered");

        uint256 availableBalance = userTokenBalances[user][token];
        if (availableBalance < amount) {
            revert InsufficientBalance(user, token, amount, availableBalance);
        }

        // 扣除 USDT
        userTokenBalances[user][token] -= amount;

        // 为每个 outcome 铸造 Long token
        uint8[] storage outcomes = eventOutcomes[eventId];
        for (uint8 i = 0; i < outcomes.length; i++) {
            longPositions[user][token][eventId][outcomes[i]] += amount;
        }

        // 增加奖金池 (铸造时锁定的 USDT 进入奖金池)
        eventPrizePool[eventId][token] += amount;

        emit CompleteSetMinted(user, eventId, token, amount);
    }

    /**
     * @notice 销毁完整集合 (用户销毁所有结果各 amount 份 Long,获得 amount USDT)
     * @param user 用户地址
     * @param eventId 事件 ID
     * @param token Token 地址
     * @param amount 销毁数量
     */
    /**
     * @notice 用户直接销毁完整集合
     * @param eventId 事件 ID
     * @param token Token 地址
     * @param amount 销毁数量
     */
    function burnCompleteSetDirect(uint256 eventId, address token, uint256 amount) external whenNotPaused nonReentrant {
        _burnCompleteSet(msg.sender, eventId, token, amount);
    }

    function _burnCompleteSet(address user, uint256 eventId, address token, uint256 amount) internal {
        require(amount > 0, "FundingManager: amount must be greater than zero");
        require(eventOutcomes[eventId].length > 0, "FundingManager: event not registered");

        // 检查并销毁每个 outcome 的 Long token
        uint8[] storage outcomes = eventOutcomes[eventId];
        for (uint8 i = 0; i < outcomes.length; i++) {
            uint256 position = longPositions[user][token][eventId][outcomes[i]];
            if (position < amount) {
                revert InsufficientLongPosition(user, token, eventId, outcomes[i]);
            }
            longPositions[user][token][eventId][outcomes[i]] -= amount;
        }

        // 返还 USDT
        userTokenBalances[user][token] += amount;

        // 减少奖金池 (销毁时 USDT 从奖金池返还给用户)
        eventPrizePool[eventId][token] -= amount;

        emit CompleteSetBurned(user, eventId, token, amount);
    }

    // ============ 订单资金管理 Order Funding Management ============

    /**
     * @notice 下单时锁定资金或 Long Token
     * @param user 用户地址
     * @param orderId 订单 ID
     * @param token Token 地址
     * @param isBuyOrder 是否为买单
     * @param amount 锁定数量 (买单锁 USDT,卖单锁 Long)
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     */
    function lockForOrder(
        address user,
        uint256 orderId,
        address token,
        bool isBuyOrder,
        uint256 amount,
        uint256 eventId,
        uint8 outcomeIndex
    ) external onlyOrderBookManager nonReentrant {
        require(amount > 0, "FundingManager: amount must be greater than zero");

        if (isBuyOrder) {
            // 买单: 锁定 USDT
            uint256 availableBalance = userTokenBalances[user][token];
            if (availableBalance < amount) {
                revert InsufficientBalance(user, token, amount, availableBalance);
            }

            userTokenBalances[user][token] -= amount;
            orderLockedUSDT[orderId] = amount;

            emit FundsLocked(user, token, amount, eventId, outcomeIndex);
        } else {
            // 卖单: 锁定 Long Token
            uint256 position = longPositions[user][token][eventId][outcomeIndex];
            if (position < amount) {
                revert InsufficientLongPosition(user, token, eventId, outcomeIndex);
            }

            longPositions[user][token][eventId][outcomeIndex] -= amount;
            orderLockedLong[orderId][eventId][outcomeIndex] = amount;

            emit FundsLocked(user, token, amount, eventId, outcomeIndex);
        }
    }

    /**
     * @notice 撤单时解锁资金或 Long Token
     * @param user 用户地址
     * @param orderId 订单 ID
     * @param token Token 地址
     * @param isBuyOrder 是否为买单
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     */
    function unlockForOrder(
        address user,
        uint256 orderId,
        address token,
        bool isBuyOrder,
        uint256 eventId,
        uint8 outcomeIndex
    ) external onlyOrderBookManager nonReentrant {
        if (isBuyOrder) {
            // 买单: 解锁 USDT
            uint256 lockedAmount = orderLockedUSDT[orderId];
            require(lockedAmount > 0, "FundingManager: no locked USDT");

            userTokenBalances[user][token] += lockedAmount;
            orderLockedUSDT[orderId] = 0;

            emit FundsUnlocked(user, token, lockedAmount, eventId, outcomeIndex);
        } else {
            // 卖单: 解锁 Long Token
            uint256 lockedAmount = orderLockedLong[orderId][eventId][outcomeIndex];
            require(lockedAmount > 0, "FundingManager: no locked Long");

            longPositions[user][token][eventId][outcomeIndex] += lockedAmount;
            orderLockedLong[orderId][eventId][outcomeIndex] = 0;

            emit FundsUnlocked(user, token, lockedAmount, eventId, outcomeIndex);
        }
    }

    /**
     * @notice 撮合成交时结算资金 (买家用 USDT 换 Long,卖家用 Long 换 USDT)
     * @param buyOrderId 买单 ID
     * @param sellOrderId 卖单 ID
     * @param buyer 买家地址
     * @param seller 卖家地址
     * @param token Token 地址
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
        address token,
        uint256 matchAmount,
        uint256 matchPrice,
        uint256 eventId,
        uint8 outcomeIndex
    ) external onlyOrderBookManager nonReentrant {
        // 计算买家支付金额
        uint256 payment = (matchAmount * matchPrice) / PRICE_PRECISION;

        // 买家: 消耗锁定的 USDT,获得 Long Token
        require(orderLockedUSDT[buyOrderId] >= payment, "FundingManager: insufficient locked USDT");
        orderLockedUSDT[buyOrderId] -= payment;
        longPositions[buyer][token][eventId][outcomeIndex] += matchAmount;

        // 卖家: 消耗锁定的 Long Token,获得 USDT
        require(
            orderLockedLong[sellOrderId][eventId][outcomeIndex] >= matchAmount,
            "FundingManager: insufficient locked Long"
        );
        orderLockedLong[sellOrderId][eventId][outcomeIndex] -= matchAmount;
        userTokenBalances[seller][token] += payment;

        // 注意: 撮合交易不改变奖金池
        // 奖金池只在 mintCompleteSet (增加) 和 burnCompleteSet (减少) 时变化
        // 因为奖金池 = 所有流通的完整集合价值总和

        emit OrderSettled(buyOrderId, sellOrderId, matchAmount, token);
    }

    // ============ 事件结算 Event Settlement ============

    /**
     * @notice 事件结算时分配奖金 (虚拟 Long Token 模型)
     * @param eventId 事件 ID
     * @param winningOutcomeIndex 获胜结果索引
     * @param token Token 地址
     * @param winners 获胜者地址列表
     * @param positions 获胜者 Long Token 持仓列表
     */
    function settleEvent(
        uint256 eventId,
        uint8 winningOutcomeIndex,
        address token,
        address[] calldata winners,
        uint256[] calldata positions
    ) external onlyEventManager nonReentrant {
        require(winners.length == positions.length, "FundingManager: length mismatch");
        require(!eventSettled[eventId], "FundingManager: event already settled");

        // 标记事件已结算
        eventSettled[eventId] = true;
        eventWinningOutcome[eventId] = winningOutcomeIndex;

        // 获取奖金池总额
        uint256 prizePool = eventPrizePool[eventId][token];
        require(prizePool > 0, "FundingManager: no prize pool");

        // 计算总获胜 Long Token 持仓
        uint256 totalWinningLongPositions = 0;
        for (uint256 i = 0; i < positions.length; i++) {
            totalWinningLongPositions += positions[i];
        }

        require(totalWinningLongPositions > 0, "FundingManager: no winning positions");

        // 按比例分配奖金给获胜者
        // 在虚拟 Long Token 模型中: 1 Long Token = 1 份奖金池份额
        // 奖金池 = 所有撮合成交的完整集合价值总和
        // 每个获胜者获得: (prizePool * 持有的Long) / 总获胜Long
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 longPosition = positions[i];

            if (longPosition == 0) continue;

            // 计算该获胜者应得的奖金
            uint256 reward = (prizePool * longPosition) / totalWinningLongPositions;

            // 销毁获胜者的 Long Token (已兑换为 USDT)
            longPositions[winner][token][eventId][winningOutcomeIndex] = 0;

            // 将奖金转入可用余额
            userTokenBalances[winner][token] += reward;
        }

        // 清零奖金池
        eventPrizePool[eventId][token] = 0;

        emit EventSettled(eventId, winningOutcomeIndex, token, prizePool, winners.length);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取用户可用余额
     * @param user 用户地址
     * @param token Token 地址
     * @return balance 可用余额
     */
    function getUserBalance(address user, address token) external view returns (uint256) {
        return userTokenBalances[user][token];
    }

    /**
     * @notice 获取用户 Long Token 持仓
     * @param user 用户地址
     * @param token Token 地址
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @return position Long Token 数量
     */
    function getLongPosition(
        address user,
        address token,
        uint256 eventId,
        uint8 outcomeIndex
    ) external view returns (uint256) {
        return longPositions[user][token][eventId][outcomeIndex];
    }

    /**
     * @notice 获取订单锁定的 USDT
     * @param orderId 订单 ID
     * @return locked 锁定的 USDT 数量
     */
    function getOrderLockedUSDT(uint256 orderId) external view returns (uint256) {
        return orderLockedUSDT[orderId];
    }

    /**
     * @notice 获取订单锁定的 Long Token
     * @param orderId 订单 ID
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @return locked 锁定的 Long Token 数量
     */
    function getOrderLockedLong(uint256 orderId, uint256 eventId, uint8 outcomeIndex) external view returns (uint256) {
        return orderLockedLong[orderId][eventId][outcomeIndex];
    }

    /**
     * @notice 获取事件奖金池
     * @param eventId 事件 ID
     * @param token Token 地址
     * @return pool 奖金池金额
     */
    function getEventPrizePool(uint256 eventId, address token) external view returns (uint256) {
        return eventPrizePool[eventId][token];
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

    // ============ 紧急控制 Emergency Control ============

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
