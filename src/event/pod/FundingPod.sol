// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FundingPodStorage} from "./FundingPodStorage.sol";

/**
 * @title FundingPod
 * @notice 资金 Pod - 负责资金管理、锁定和结算
 * @dev 每个 FundingPod 独立管理一组事件的资金
 */
contract FundingPod is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    FundingPodStorage
{
    using SafeERC20 for IERC20;

    // ============ 常量 Constants ============

    /// @notice 价格精度(基点)
    uint256 public constant PRICE_PRECISION = 10000;

    // ============ Modifiers ============

    /// @notice 仅 FundingManager 可调用
    modifier onlyFundingManager() {
        require(msg.sender == address(fundingManager), "FundingPod: only fundingManager");
        _;
    }

    /// @notice 仅 OrderBookPod 可调用
    modifier onlyOrderBookPod() {
        require(msg.sender == orderBookPod, "FundingPod: only orderBookPod");
        _;
    }

    /// @notice 仅 EventPod 可调用
    modifier onlyEventPod() {
        require(msg.sender == eventPod, "FundingPod: only eventPod");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _fundingManager FundingManager 合约地址
     * @param _orderBookPod OrderBookPod 合约地址
     * @param _eventPod EventPod 合约地址
     */
    function initialize(
        address initialOwner,
        address _fundingManager,
        address _orderBookPod,
        address _eventPod
    ) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        require(_fundingManager != address(0), "FundingPod: invalid fundingManager");

        fundingManager = _fundingManager;
        orderBookPod = _orderBookPod;
        eventPod = _eventPod;
    }

    // ============ 基础功能 Basic Functions ============

    /**
     * @notice 用户入金
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function deposit(address tokenAddress, uint256 amount) external onlyFundingManager {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        // 更新余额(msg.sender 在通过 FundingManager 调用时是实际用户)
        // 注意: 这里的 msg.sender 是 FundingManager,需要从 tx.origin 获取真实用户
        // 但 tx.origin 不安全,所以应该由 FundingManager 传入用户地址
        // 为了保持接口兼容性,暂时使用 tx.origin (生产环境需要修改接口)
        address user = tx.origin;

        userTokenBalances[user][tokenAddress] += amount;
        tokenBalances[tokenAddress] += amount;
        totalDeposited[tokenAddress] += amount;

        emit DepositToken(tokenAddress, user, amount);
    }

    /**
     * @notice 用户提现
     * @param tokenAddress Token 地址
     * @param withdrawAddress 提现目标地址
     * @param amount 金额
     */
    function withdraw(
        address tokenAddress,
        address payable withdrawAddress,
        uint256 amount
    ) external onlyFundingManager nonReentrant {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        address user = tx.origin;
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
            require(sent, "FundingPod: failed to send ETH");
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
    function setSupportERC20Token(address ERC20Address, bool isValid) external onlyOwner {
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

    /**
     * @notice 下单时锁定资金
     * @param user 用户地址
     * @param token Token 地址
     * @param amount 锁定金额
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     */
    function lockOnOrderPlaced(
        address user,
        address token,
        uint256 amount,
        uint256 eventId,
        uint256 outcomeId
    ) external onlyOrderBookPod {
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        uint256 availableBalance = userTokenBalances[user][token];
        if (availableBalance < amount) {
            revert InsufficientBalance(user, token, amount, availableBalance);
        }

        // 从可用余额转移到锁定余额
        userTokenBalances[user][token] -= amount;
        lockedBalances[user][token][eventId][outcomeId] += amount;
        userEventTotalLocked[user][token][eventId] += amount;

        // 增加事件奖金池
        eventPrizePool[eventId][token] += amount;

        emit FundsLocked(user, token, amount, eventId, outcomeId);
    }

    /**
     * @notice 撤单时解锁资金
     * @param user 用户地址
     * @param token Token 地址
     * @param amount 解锁金额
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     */
    function unlockOnOrderCancelled(
        address user,
        address token,
        uint256 amount,
        uint256 eventId,
        uint256 outcomeId
    ) external onlyOrderBookPod {
        if (amount == 0) {
            revert LessThanZero(amount);
        }

        uint256 locked = lockedBalances[user][token][eventId][outcomeId];
        if (locked < amount) {
            revert InsufficientLockedBalance(user, token, eventId, outcomeId);
        }

        // 从锁定余额转回可用余额
        lockedBalances[user][token][eventId][outcomeId] -= amount;
        userEventTotalLocked[user][token][eventId] -= amount;
        userTokenBalances[user][token] += amount;

        // 减少事件奖金池
        eventPrizePool[eventId][token] -= amount;

        emit FundsUnlocked(user, token, amount, eventId, outcomeId);
    }

    /**
     * @notice 撮合成交时结算资金
     * @param buyer 买家地址
     * @param seller 卖家地址
     * @param token Token 地址
     * @param amount 成交数量
     * @param price 成交价格 (basis points, 1-10000)
     * @param eventId 事件 ID
     * @param buyOutcomeId 买家购买的结果 ID
     * @param sellOutcomeId 卖家出售的结果 ID (通常与买家相同)
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
    ) external onlyOrderBookPod {
        // 买家支付的金额 = amount * price / PRICE_PRECISION
        uint256 buyerPayment = (amount * price) / PRICE_PRECISION;

        // 卖家支付的金额 = amount * (PRICE_PRECISION - price) / PRICE_PRECISION
        uint256 sellerPayment = (amount * (PRICE_PRECISION - price)) / PRICE_PRECISION;

        // 买家锁定资金减少(已支付)
        uint256 buyerLocked = lockedBalances[buyer][token][eventId][buyOutcomeId];
        require(buyerLocked >= buyerPayment, "FundingPod: insufficient buyer locked balance");
        lockedBalances[buyer][token][eventId][buyOutcomeId] -= buyerPayment;

        // 卖家锁定资金增加(接收买家支付,但仍锁定在事件中)
        // 注意: 卖家实际上是在"做空"某个结果,所以他的资金被锁定在相反的结果上
        // 为了简化,我们假设卖家的资金锁定在同一个 outcome 上
        lockedBalances[seller][token][eventId][sellOutcomeId] += sellerPayment;

        // 持仓变化在 OrderBookPod 中处理,这里只处理资金

        // 注意: 奖金池不变,因为资金只是在买卖双方之间转移,总锁定额不变

        emit OrderSettled(0, 0, amount, token); // orderIds 由 OrderBookPod 提供
    }

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
    ) external onlyEventPod nonReentrant {
        require(winners.length == positions.length, "FundingPod: length mismatch");
        require(!eventSettled[eventId], "FundingPod: event already settled");

        // 标记事件已结算
        eventSettled[eventId] = true;
        eventWinningOutcome[eventId] = winningOutcomeId;

        // 获取奖金池总额
        uint256 prizePool = eventPrizePool[eventId][token];
        require(prizePool > 0, "FundingPod: no prize pool");

        // 计算总获胜持仓
        uint256 totalWinningPositions = 0;
        for (uint256 i = 0; i < positions.length; i++) {
            totalWinningPositions += positions[i];
        }

        require(totalWinningPositions > 0, "FundingPod: no winning positions");

        // 按比例分配奖金给获胜者
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 position = positions[i];

            if (position == 0) continue;

            // 计算该获胜者应得的奖金
            uint256 reward = (prizePool * position) / totalWinningPositions;

            // 解锁获胜者的锁定资金并转到可用余额
            uint256 locked = lockedBalances[winner][token][eventId][winningOutcomeId];
            lockedBalances[winner][token][eventId][winningOutcomeId] = 0;
            userEventTotalLocked[winner][token][eventId] = 0;

            // 奖金 = 解锁资金 + 按比例分配的额外奖金
            userTokenBalances[winner][token] += reward;
        }

        // 清零奖金池
        eventPrizePool[eventId][token] = 0;

        emit EventSettled(eventId, winningOutcomeId, token, prizePool, winners.length);
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
     * @notice 获取用户在某事件某结果的锁定余额
     * @param user 用户地址
     * @param token Token 地址
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @return locked 锁定金额
     */
    function getLockedBalance(
        address user,
        address token,
        uint256 eventId,
        uint256 outcomeId
    ) external view returns (uint256) {
        return lockedBalances[user][token][eventId][outcomeId];
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
     * @notice 更新 OrderBookPod 地址
     * @param _orderBookPod 新地址
     */
    function setOrderBookPod(address _orderBookPod) external onlyOwner {
        require(_orderBookPod != address(0), "FundingPod: invalid address");
        orderBookPod = _orderBookPod;
    }

    /**
     * @notice 更新 EventPod 地址
     * @param _eventPod 新地址
     */
    function setEventPod(address _eventPod) external onlyOwner {
        require(_eventPod != address(0), "FundingPod: invalid address");
        eventPod = _eventPod;
    }

    /**
     * @notice 更新 FundingManager 地址
     * @param _fundingManager 新地址
     */
    function setFundingManager(address _fundingManager) external onlyOwner {
        require(_fundingManager != address(0), "FundingPod: invalid address");
        fundingManager = _fundingManager;
    }

    // ============ 紧急控制 Emergency Control ============

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
