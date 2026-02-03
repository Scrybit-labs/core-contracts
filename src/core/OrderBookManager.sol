// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/core/IOrderBookManager.sol";
import "../interfaces/core/IFundingManager.sol";
import "../interfaces/core/IFeeVaultManager.sol";

/**
 * @title OrderBookManager
 * @notice 订单簿 Manager - 负责订单撮合和持仓管理
 * @dev 集成 FundingManager 进行资金管理
 */
contract OrderBookManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IOrderBookManager
{
    // ============ Modifiers ============

    modifier onlyEventManager() {
        require(msg.sender == eventManager, "OrderBookManager: only eventManager");
        _;
    }

    // ============ 合约地址 Contract Addresses ============

    /// @notice EventManager 合约地址
    address public eventManager;

    /// @notice FundingManager 合约地址
    address public fundingManager;

    /// @notice FeeVaultManager 合约地址
    address public feeVaultManager;

    // ============ 事件与结果管理 Event & Outcome Management ============

    /// @notice 事件结果数量: eventId => outcomeCount (0 means not registered)
    mapping(uint256 => uint8) public eventOutcomeCount;

    // ============ 订单管理 Order Management ============

    /// @notice 下一个订单 ID
    uint256 public nextOrderId;

    /// @notice 订单映射: orderId => Order
    mapping(uint256 => Order) public orders;

    /// @notice 用户订单列表: user => orderIds[]
    mapping(address => uint256[]) public userOrders;

    // ============ 订单簿结构 Order Book Structure ============

    /// @notice 结果订单簿(买单和卖单按价格分组)
    struct OutcomeOrderBook {
        mapping(uint256 => uint256[]) buyOrdersByPrice; // price => orderIds[]
        uint256[] buyPriceLevels; // 买单价格档位(降序)
        mapping(uint256 => uint256[]) sellOrdersByPrice; // price => orderIds[]
        uint256[] sellPriceLevels; // 卖单价格档位(升序)
    }

    /// @notice 事件订单簿(每个结果一个订单簿)
    struct EventOrderBook {
        mapping(uint8 => OutcomeOrderBook) outcomeOrderBooks;
    }

    /// @notice 事件订单簿映射: eventId => EventOrderBook
    mapping(uint256 => EventOrderBook) internal eventOrderBooks;

    // ============ 持仓管理 Position Management ============

    /// @notice 用户持仓: eventId => outcomeIndex => user => position
    mapping(uint256 => mapping(uint8 => mapping(address => uint256))) public positions;

    /// @notice 事件的所有持仓用户: eventId => outcomeIndex => users[]
    /// @dev 用于事件结算时遍历所有获胜者
    mapping(uint256 => mapping(uint8 => address[])) internal positionHolders;

    /// @notice 用户是否已记录为持仓者: eventId => outcomeIndex => user => isRecorded
    mapping(uint256 => mapping(uint8 => mapping(address => bool))) internal isPositionHolder;

    // ============ 常量 Constants ============

    /// @notice 价格精度(最小变动单位)
    uint256 public constant TICK_SIZE = 10;

    /// @notice 最大价格(基点)
    uint256 public constant MAX_PRICE = 10000;

    // ============ 事件结算 Event Settlement ============

    /// @notice 事件结算状态: eventId => settled
    mapping(uint256 => bool) public eventSettled;

    /// @notice 事件结果: eventId => winningOutcomeIndex
    mapping(uint256 => uint8) public eventResults;

    // ===== Upgradeable storage gap =====
    uint256[50] private __gap;

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

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        nextOrderId = 1; // Start from 1
    }

    // ============ 外部函数 External Functions ============

    /**
     * @notice 下单 (Public - users can call directly)
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @param side 买卖方向
     * @param price 价格
     * @param amount 数量
     * @param tokenAddress Token 地址
     * @return orderId 订单 ID
     */
    function placeOrder(
        uint256 eventId,
        uint8 outcomeIndex,
        OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external whenNotPaused nonReentrant returns (uint256 orderId) {
        address user = msg.sender; // Direct caller

        uint8 outcomeCount = eventOutcomeCount[eventId];
        if (outcomeCount == 0) revert EventNotSupported(eventId);
        if (outcomeIndex >= outcomeCount) {
            revert OutcomeNotSupported(eventId, outcomeIndex);
        }
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (price == 0 || price > MAX_PRICE) revert InvalidPrice(price);
        if (price % TICK_SIZE != 0) revert PriceNotAlignedWithTickSize(price);
        if (amount == 0) revert InvalidAmount(amount);

        // 计算下单金额 (USD)
        uint256 tradeUsd = (amount * price) / MAX_PRICE;

        // 计算下单手续费 (USD)
        uint256 placementFee = 0;
        if (feeVaultManager != address(0)) {
            placementFee = IFeeVaultManager(feeVaultManager).calculateFee(tradeUsd, "placement");
        }

        // 集成 FundingManager: 锁定下单所需资金或 Long Token
        // 买单锁定 USD (不含手续费): amount * price / MAX_PRICE
        // 卖单锁定 Long Token: amount
        uint256 requiredAmount = side == OrderSide.Buy ? tradeUsd : amount;

        IFundingManager(fundingManager).lockForOrder(
            user, // 用户地址
            nextOrderId, // 订单 ID
            side == OrderSide.Buy, // 是否为买单
            requiredAmount, // 锁定数量
            eventId, // 事件 ID
            outcomeIndex // 结果索引
        );

        // 收取手续费
        if (placementFee > 0 && feeVaultManager != address(0)) {
            IFeeVaultManager(feeVaultManager).collectFee(
                tokenAddress,
                user, // 使用传入的真实用户地址
                placementFee,
                eventId,
                "placement"
            );
        }

        orderId = nextOrderId++;
        orders[orderId] = Order({
            orderId: orderId,
            user: user, // 使用传入的真实用户地址
            eventId: eventId,
            outcomeIndex: outcomeIndex,
            side: side,
            price: price,
            amount: amount,
            filledAmount: 0,
            remainingAmount: amount,
            status: OrderStatus.Pending,
            timestamp: block.timestamp,
            tokenAddress: tokenAddress
        });
        userOrders[user].push(orderId);

        _matchOrder(orderId);

        if (orders[orderId].status == OrderStatus.Pending || orders[orderId].status == OrderStatus.Partial) {
            _addToOrderBook(orderId);
        }

        emit OrderPlaced(
            orderId,
            user, // 使用传入的真实用户地址
            eventId,
            outcomeIndex,
            side,
            price,
            amount
        );
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];

        if (_msgSender() != order.user) {
            revert("OrderBookManager: Invalid user");
        }

        if (eventSettled[order.eventId]) {
            revert EventAlreadySettled(order.eventId);
        }
        if (order.status != OrderStatus.Pending && order.status != OrderStatus.Partial) {
            revert CannotCancelOrder(orderId);
        }

        _removeFromOrderBook(orderId);

        order.status = OrderStatus.Cancelled;

        if (order.remainingAmount > 0) {
            // 集成 FundingManager: 解锁剩余未成交资金或 Long Token
            IFundingManager(fundingManager).unlockForOrder(
                order.user,
                orderId,
                order.side == OrderSide.Buy, // 是否为买单
                order.eventId,
                order.outcomeIndex
            );
        }

        emit OrderCancelled(orderId, order.user, order.remainingAmount);
    }

    function settleEvent(uint256 eventId, uint8 winningOutcomeIndex) external onlyEventManager nonReentrant {
        uint8 outcomeCount = eventOutcomeCount[eventId];
        if (outcomeCount == 0) revert EventNotSupported(eventId);
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (winningOutcomeIndex >= outcomeCount) revert OutcomeNotSupported(eventId, winningOutcomeIndex);

        eventSettled[eventId] = true;
        eventResults[eventId] = winningOutcomeIndex;

        _cancelAllPendingOrders(eventId);
        _settlePositions(eventId, winningOutcomeIndex);

        emit EventSettled(eventId, winningOutcomeIndex);
    }

    function registerEvent(uint256 eventId, uint8 outcomeCount) external onlyEventManager nonReentrant {
        require(eventOutcomeCount[eventId] == 0, "OrderBookManager: event already registered");
        require(outcomeCount >= 2 && outcomeCount <= 32, "OrderBookManager: invalid outcomeCount");
        eventOutcomeCount[eventId] = outcomeCount;

        // 集成 FundingManager: 注册事件的结果选项 (用于完整集合铸造)
        IFundingManager(fundingManager).registerEvent(eventId, outcomeCount);

        emit EventAdded(eventId, outcomeCount);
    }

    function deactivateEvent(uint256 eventId) external onlyEventManager nonReentrant {
        _cancelAllPendingOrders(eventId);
        eventOutcomeCount[eventId] = 0;
        emit EventDeactivated(eventId);
    }

    function getBestBid(uint256 eventId, uint8 outcomeIndex) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[outcomeIndex];

        if (outcomeOrderBook.buyPriceLevels.length > 0) {
            price = outcomeOrderBook.buyPriceLevels[0];
            amount = _totalAtPrice(outcomeOrderBook.buyOrdersByPrice[price]);
        }
    }

    function getBestAsk(uint256 eventId, uint8 outcomeIndex) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[outcomeIndex];

        if (outcomeOrderBook.sellPriceLevels.length > 0) {
            price = outcomeOrderBook.sellPriceLevels[0];
            amount = _totalAtPrice(outcomeOrderBook.sellOrdersByPrice[price]);
        }
    }

    // ------------------------------------------------------------
    // Internal: matching 撮合
    // ------------------------------------------------------------
    function _matchOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeIndex];

        if (order.side == OrderSide.Buy) {
            _matchBuy(orderId, outcomeOrderBook);
        } else {
            _matchSell(orderId, outcomeOrderBook);
        }
    }

    function _matchBuy(uint256 buyOrderId, OutcomeOrderBook storage book) internal {
        Order storage buyOrder = orders[buyOrderId];

        for (uint256 i = 0; i < book.sellPriceLevels.length && buyOrder.remainingAmount > 0; i++) {
            uint256 sellPrice = book.sellPriceLevels[i];
            if (sellPrice > buyOrder.price) break;

            uint256[] storage sellOrders = book.sellOrdersByPrice[sellPrice];
            for (uint256 j = 0; j < sellOrders.length && buyOrder.remainingAmount > 0; j++) {
                uint256 sellOrderId = sellOrders[j];
                Order storage sellOrder = orders[sellOrderId];

                // 跳过已完成/已取消的订单，保持数组顺序确保时间优先（FIFO）
                if (
                    sellOrder.status == OrderStatus.Cancelled ||
                    sellOrder.status == OrderStatus.Filled ||
                    sellOrder.remainingAmount == 0
                ) {
                    continue;
                }

                if (buyOrder.eventId != sellOrder.eventId) {
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                }
                if (buyOrder.outcomeIndex != sellOrder.outcomeIndex) {
                    revert OutcomeMismatch(buyOrder.outcomeIndex, sellOrder.outcomeIndex);
                }
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _matchSell(uint256 sellOrderId, OutcomeOrderBook storage book) internal {
        Order storage sellOrder = orders[sellOrderId];

        for (uint256 i = 0; i < book.buyPriceLevels.length && sellOrder.remainingAmount > 0; i++) {
            uint256 buyPrice = book.buyPriceLevels[i];
            if (buyPrice < sellOrder.price) break;

            uint256[] storage buyOrders = book.buyOrdersByPrice[buyPrice];
            for (uint256 j = 0; j < buyOrders.length && sellOrder.remainingAmount > 0; j++) {
                uint256 buyOrderId = buyOrders[j];
                Order storage buyOrder = orders[buyOrderId];

                // 跳过已完成/已取消的订单，保持数组顺序确保时间优先（FIFO）
                if (
                    buyOrder.status == OrderStatus.Cancelled ||
                    buyOrder.status == OrderStatus.Filled ||
                    buyOrder.remainingAmount == 0
                ) {
                    continue;
                }

                if (buyOrder.eventId != sellOrder.eventId) {
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                }
                if (buyOrder.outcomeIndex != sellOrder.outcomeIndex) {
                    revert OutcomeMismatch(buyOrder.outcomeIndex, sellOrder.outcomeIndex);
                }
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _executeMatch(uint256 buyOrderId, uint256 sellOrderId) internal {
        Order storage buyOrder = orders[buyOrderId];
        Order storage sellOrder = orders[sellOrderId];

        uint256 matchAmount = buyOrder.remainingAmount < sellOrder.remainingAmount
            ? buyOrder.remainingAmount
            : sellOrder.remainingAmount;

        uint256 matchPrice = sellOrder.price;

        buyOrder.filledAmount += matchAmount;
        buyOrder.remainingAmount -= matchAmount;
        sellOrder.filledAmount += matchAmount;
        sellOrder.remainingAmount -= matchAmount;

        // ✅ 计算撮合手续费 (USD)
        uint256 matchUsd = (matchAmount * matchPrice) / MAX_PRICE;
        uint256 matchFee = 0;
        if (feeVaultManager != address(0)) {
            matchFee = IFeeVaultManager(feeVaultManager).calculateFee(matchUsd, "execution");
        }

        // ✅ 持仓管理: 记录买家持仓增加
        positions[buyOrder.eventId][buyOrder.outcomeIndex][buyOrder.user] += matchAmount;
        _recordPositionHolder(buyOrder.eventId, buyOrder.outcomeIndex, buyOrder.user);

        // ✅ 持仓管理: 卖家持仓减少(卖出做空)
        if (positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.user] >= matchAmount) {
            positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.user] -= matchAmount;
        } else {
            positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.user] = 0;
        }

        // 集成 FundingManager: 资金结算 (虚拟 Long Token 模型)
        IFundingManager(fundingManager).settleMatchedOrder(
            buyOrderId, // 买单 ID
            sellOrderId, // 卖单 ID
            buyOrder.user, // 买家地址
            sellOrder.user, // 卖家地址
            matchAmount, // 成交数量
            matchPrice, // 成交价格
            buyOrder.eventId, // 事件 ID
            buyOrder.outcomeIndex // 结果索引 (买卖同一 outcome)
        );

        // ✅ 收取撮合手续费
        if (matchFee > 0 && feeVaultManager != address(0)) {
            // 买卖双方各支付一半手续费
            uint256 buyerFee = matchFee / 2;
            uint256 sellerFee = matchFee - buyerFee;

            if (buyerFee > 0) {
                IFeeVaultManager(feeVaultManager).collectFee(
                    buyOrder.tokenAddress,
                    buyOrder.user,
                    buyerFee,
                    buyOrder.eventId,
                    "execution"
                );
            }

            if (sellerFee > 0) {
                IFeeVaultManager(feeVaultManager).collectFee(
                    sellOrder.tokenAddress,
                    sellOrder.user,
                    sellerFee,
                    sellOrder.eventId,
                    "execution"
                );
            }
        }

        if (buyOrder.remainingAmount == 0) {
            buyOrder.status = OrderStatus.Filled;
            _removeFromOrderBook(buyOrderId);
        } else if (buyOrder.filledAmount > 0) {
            buyOrder.status = OrderStatus.Partial;
        }

        if (sellOrder.remainingAmount == 0) {
            sellOrder.status = OrderStatus.Filled;
            _removeFromOrderBook(sellOrderId);
        } else if (sellOrder.filledAmount > 0) {
            sellOrder.status = OrderStatus.Partial;
        }

        emit OrderMatched(buyOrderId, sellOrderId, buyOrder.eventId, buyOrder.outcomeIndex, matchPrice, matchAmount);
    }

    // ------------------------------------------------------------
    // Internal: orderbook ops 订单簿操作
    // ------------------------------------------------------------
    function _addToOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeIndex];

        if (order.side == OrderSide.Buy) {
            if (outcomeOrderBook.buyOrdersByPrice[order.price].length == 0) {
                _insertBuyPrice(outcomeOrderBook, order.price);
            }
            outcomeOrderBook.buyOrdersByPrice[order.price].push(orderId);
        } else {
            if (outcomeOrderBook.sellOrdersByPrice[order.price].length == 0) {
                _insertSellPrice(outcomeOrderBook, order.price);
            }
            outcomeOrderBook.sellOrdersByPrice[order.price].push(orderId);
        }
    }

    /**
     * @notice 从订单簿移除订单（使用标记删除策略保持时间优先）
     * @dev 不物理删除订单，保持数组顺序以确保 FIFO，仅在价格档位全部完成时删除价格档位
     * @param orderId 订单 ID
     */
    function _removeFromOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeIndex];

        if (order.side == OrderSide.Buy) {
            uint256[] storage priceOrders = outcomeOrderBook.buyOrdersByPrice[order.price];

            // 标记删除策略：不从数组中物理删除，保持顺序
            // 订单通过状态（Cancelled/Filled）和 remainingAmount == 0 标记为无效
            // 撮合时会自动跳过这些订单

            // 检查该价格档位是否所有订单都已完成（可以删除价格档位）
            bool allCompleted = _isAllOrdersCompleted(priceOrders);
            if (allCompleted && priceOrders.length > 0) {
                _removeBuyPrice(outcomeOrderBook, order.price);
                delete outcomeOrderBook.buyOrdersByPrice[order.price];
            }
        } else {
            uint256[] storage priceOrders = outcomeOrderBook.sellOrdersByPrice[order.price];

            // 标记删除策略：保持数组顺序
            bool allCompleted = _isAllOrdersCompleted(priceOrders);
            if (allCompleted && priceOrders.length > 0) {
                _removeSellPrice(outcomeOrderBook, order.price);
                delete outcomeOrderBook.sellOrdersByPrice[order.price];
            }
        }
    }

    function _insertBuyPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        uint256 i = 0;
        while (i < orderBook.buyPriceLevels.length && orderBook.buyPriceLevels[i] > price) {
            i++;
        }
        if (i < orderBook.buyPriceLevels.length && orderBook.buyPriceLevels[i] == price) return;

        orderBook.buyPriceLevels.push(0);
        for (uint256 j = orderBook.buyPriceLevels.length - 1; j > i; j--) {
            orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[j - 1];
        }
        orderBook.buyPriceLevels[i] = price;
    }

    function _insertSellPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        uint256 i = 0;
        while (i < orderBook.sellPriceLevels.length && orderBook.sellPriceLevels[i] < price) {
            i++;
        }
        if (i < orderBook.sellPriceLevels.length && orderBook.sellPriceLevels[i] == price) return;

        orderBook.sellPriceLevels.push(0);
        for (uint256 j = orderBook.sellPriceLevels.length - 1; j > i; j--) {
            orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[j - 1];
        }
        orderBook.sellPriceLevels[i] = price;
    }

    function _removeBuyPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        for (uint256 i = 0; i < orderBook.buyPriceLevels.length; i++) {
            if (orderBook.buyPriceLevels[i] == price) {
                for (uint256 j = i; j < orderBook.buyPriceLevels.length - 1; j++) {
                    orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[j + 1];
                }
                orderBook.buyPriceLevels.pop();
                break;
            }
        }
    }

    function _removeSellPrice(OutcomeOrderBook storage orderBook, uint256 price) internal {
        for (uint256 i = 0; i < orderBook.sellPriceLevels.length; i++) {
            if (orderBook.sellPriceLevels[i] == price) {
                for (uint256 j = i; j < orderBook.sellPriceLevels.length - 1; j++) {
                    orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[j + 1];
                }
                orderBook.sellPriceLevels.pop();
                break;
            }
        }
    }

    function _totalAtPrice(uint256[] storage orderIds) internal view returns (uint256 total) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                total += order.remainingAmount;
            }
        }
    }

    /**
     * @notice 检查价格档位的所有订单是否都已完成
     * @dev 用于判断是否可以删除价格档位
     * @param orderIds 订单 ID 数组
     * @return 如果所有订单都已完成（Filled/Cancelled 或 remainingAmount == 0），返回 true
     */
    function _isAllOrdersCompleted(uint256[] storage orderIds) internal view returns (bool) {
        if (orderIds.length == 0) return true;

        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            // 如果存在任何未完成的订单，返回 false
            if (
                (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) &&
                order.remainingAmount > 0
            ) {
                return false;
            }
        }
        return true;
    }

    // ------------------------------------------------------------
    // Internal: cancel & settle 撤单与结算
    // ------------------------------------------------------------
    function _cancelAllPendingOrders(uint256 eventId) internal {
        uint8 outcomeCount = eventOutcomeCount[eventId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        for (uint8 i = 0; i < outcomeCount; i++) {
            OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[i];
            _cancelMarketOrders(outcomeOrderBook);
        }
    }

    function _cancelMarketOrders(OutcomeOrderBook storage marketOrderBook) internal {
        for (uint256 i = 0; i < marketOrderBook.buyPriceLevels.length; i++) {
            uint256 price = marketOrderBook.buyPriceLevels[i];
            uint256[] storage ids = marketOrderBook.buyOrdersByPrice[price];
            for (uint256 j = 0; j < ids.length; j++) {
                Order storage order = orders[ids[j]];
                if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                    order.status = OrderStatus.Cancelled;

                    // 集成 FundingManager: 批量撤单解锁资金或 Long Token
                    if (order.remainingAmount > 0) {
                        IFundingManager(fundingManager).unlockForOrder(
                            order.user,
                            ids[j], // orderId
                            order.side == OrderSide.Buy, // 是否为买单
                            order.eventId,
                            order.outcomeIndex
                        );
                    }
                }
            }
        }

        for (uint256 i = 0; i < marketOrderBook.sellPriceLevels.length; i++) {
            uint256 price = marketOrderBook.sellPriceLevels[i];
            uint256[] storage ids = marketOrderBook.sellOrdersByPrice[price];
            for (uint256 j = 0; j < ids.length; j++) {
                Order storage order = orders[ids[j]];
                if (order.status == OrderStatus.Pending || order.status == OrderStatus.Partial) {
                    order.status = OrderStatus.Cancelled;

                    // 集成 FundingManager: 批量撤单解锁资金或 Long Token
                    if (order.remainingAmount > 0) {
                        IFundingManager(fundingManager).unlockForOrder(
                            order.user,
                            ids[j], // orderId
                            order.side == OrderSide.Buy, // 是否为买单
                            order.eventId,
                            order.outcomeIndex
                        );
                    }
                }
            }
        }
    }

    // ✅ 结算持仓 - 集成 FundingManager 标记事件已结算
    function _settlePositions(uint256 eventId, uint8 winningOutcomeIndex) internal {
        IFundingManager(fundingManager).markEventSettled(eventId, winningOutcomeIndex);
    }

    // ============ 持仓跟踪辅助函数 Position Tracking Helper ============

    /**
     * @notice 记录持仓者(避免重复记录)
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @param user 用户地址
     */
    function _recordPositionHolder(uint256 eventId, uint8 outcomeIndex, address user) internal {
        if (!isPositionHolder[eventId][outcomeIndex][user]) {
            positionHolders[eventId][outcomeIndex].push(user);
            isPositionHolder[eventId][outcomeIndex][user] = true;
        }
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取订单信息
     * @param orderId 订单 ID
     * @return order 订单详情
     */
    function getOrder(uint256 orderId) external view returns (Order memory order) {
        return orders[orderId];
    }

    /**
     * @notice 获取用户持仓
     * @param eventId 事件 ID
     * @param outcomeIndex 结果索引
     * @param user 用户地址
     * @return position 持仓数量
     */
    function getPosition(uint256 eventId, uint8 outcomeIndex, address user) external view returns (uint256 position) {
        return positions[eventId][outcomeIndex][user];
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 设置 EventManager 地址
     * @param _eventManager EventManager 地址
     */
    function setEventManager(address _eventManager) external onlyOwner nonReentrant {
        require(eventManager == address(0), "OrderBookManager: already set");
        require(_eventManager != address(0), "OrderBookManager: invalid address");
        eventManager = _eventManager;
    }

    /**
     * @notice 设置 FundingManager 地址
     * @param _fundingManager FundingManager 地址
     */
    function setFundingManager(address _fundingManager) external onlyOwner nonReentrant {
        require(fundingManager == address(0), "OrderBookManager: already set");
        require(_fundingManager != address(0), "OrderBookManager: invalid address");
        fundingManager = _fundingManager;
    }

    /**
     * @notice 设置 FeeVaultManager 地址
     * @param _feeVaultManager FeeVaultManager 地址
     */
    function setFeeVaultManager(address _feeVaultManager) external onlyOwner nonReentrant {
        require(feeVaultManager == address(0), "OrderBookManager: already set");
        require(_feeVaultManager != address(0), "OrderBookManager: invalid address");
        feeVaultManager = _feeVaultManager;
    }
}
