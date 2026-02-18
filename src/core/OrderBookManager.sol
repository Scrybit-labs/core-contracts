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
import "../interfaces/core/IOrderStorage.sol";
import {OrderStruct, OrderKey} from "../library/OrderStruct.sol";
import {OrderValidator} from "./OrderValidator.sol";

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
    OrderValidator,
    IOrderBookManager
{
    // ============ Modifiers ============

    /// forge-lint: disable-next-item(unwrapped-modifier-logic)
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

    /// @notice OrderStorage 合约地址
    address public orderStorage;

    // ============ 事件与结果管理 Event & Outcome Management ============

    /// @notice 事件结果数量: eventId => outcomeCount (0 means not registered)
    mapping(uint256 => uint8) public eventOutcomeCount;

    // ============ 订单管理 Order Management ============

    /// @notice 下一个订单 ID
    uint256 public nextOrderId;

    /// @notice 订单映射: orderId => Order
    mapping(uint256 => OrderStruct.Order) public orders;

    /// @notice OrderKey to orderId mapping for new storage layer
    mapping(OrderKey => uint256) public orderKeyToId;

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

    // ============ 事件结算 Event Settlement ============

    /// @notice 事件结算状态: eventId => settled
    mapping(uint256 => bool) public eventSettled;

    /// @notice 事件结果: eventId => winningOutcomeIndex
    mapping(uint256 => uint8) public eventResults;

    // ===== Upgradeable storage gap =====
    uint256[50] private _gap;

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
        __EIP712_init("OrderBookManager", "1");
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
        OrderStruct.Side side,
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

        // Use OrderValidator for comprehensive validation
        (bool valid, string memory reason) = this.validateOrderParams(
            user,
            eventId,
            outcomeIndex,
            uint128(price),
            uint128(amount),
            0 // expiry: 0 means no expiry for now
        );
        require(valid, reason);

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
        uint256 requiredAmount = side == OrderStruct.Side.Buy ? tradeUsd : amount;

        IFundingManager(fundingManager).lockForOrder(
            user, // 用户地址
            nextOrderId, // 订单 ID
            side == OrderStruct.Side.Buy, // 是否为买单
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
        orders[orderId] = OrderStruct.Order({
            orderId: orderId,
            eventId: eventId,
            maker: user, // 使用传入的真实用户地址
            outcomeIndex: outcomeIndex,
            side: side,
            price: uint128(price),
            amount: uint128(amount),
            filledAmount: 0,
            remainingAmount: uint128(amount),
            status: OrderStruct.OrderStatus.Pending,
            timestamp: uint64(block.timestamp),
            expiry: 0,
            salt: 0,
            tokenAddress: tokenAddress
        });
        userOrders[user].push(orderId);

        _matchOrder(orderId);

        if (orders[orderId].status == OrderStruct.OrderStatus.Pending || orders[orderId].status == OrderStruct.OrderStatus.Partial) {
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
        OrderStruct.Order storage order = orders[orderId];

        if (_msgSender() != order.maker) {
            revert("OrderBookManager: Invalid user");
        }

        if (eventSettled[order.eventId]) {
            revert EventAlreadySettled(order.eventId);
        }
        if (order.status != OrderStruct.OrderStatus.Pending && order.status != OrderStruct.OrderStatus.Partial) {
            revert CannotCancelOrder(orderId);
        }

        _removeFromOrderBook(orderId);

        order.status = OrderStruct.OrderStatus.Cancelled;

        if (order.remainingAmount > 0) {
            // 集成 FundingManager: 解锁剩余未成交资金或 Long Token
            IFundingManager(fundingManager).unlockForOrder(
                order.maker,
                orderId,
                order.side == OrderStruct.Side.Buy, // 是否为买单
                order.eventId,
                order.outcomeIndex
            );
        }

        emit OrderCancelled(orderId, order.maker, order.remainingAmount);
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
        if (orderStorage == address(0)) {
            return (0, 0);
        }

        // Get best bid price (highest buy price) from OrderStorage - O(log n)
        uint128 bestBid = IOrderStorage(orderStorage).getBestPrice(eventId, outcomeIndex, true);

        if (bestBid == 0) {
            return (0, 0);
        }

        price = uint256(bestBid);
        amount = _totalAtPriceFromStorage(eventId, outcomeIndex, true, bestBid);
    }

    function getBestAsk(uint256 eventId, uint8 outcomeIndex) external view returns (uint256 price, uint256 amount) {
        if (orderStorage == address(0)) {
            return (0, 0);
        }

        // Get best ask price (lowest sell price) from OrderStorage - O(log n)
        uint128 bestAsk = IOrderStorage(orderStorage).getBestPrice(eventId, outcomeIndex, false);

        if (bestAsk == 0) {
            return (0, 0);
        }

        price = uint256(bestAsk);
        amount = _totalAtPriceFromStorage(eventId, outcomeIndex, false, bestAsk);
    }

    // ------------------------------------------------------------
    // Internal: matching 撮合
    // ------------------------------------------------------------
    function _matchOrder(uint256 orderId) internal {
        OrderStruct.Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook.outcomeOrderBooks[order.outcomeIndex];

        if (order.side == OrderStruct.Side.Buy) {
            _matchBuy(orderId, outcomeOrderBook);
        } else {
            _matchSell(orderId, outcomeOrderBook);
        }
    }

    function _matchBuy(uint256 buyOrderId, OutcomeOrderBook storage book) internal {
        OrderStruct.Order storage buyOrder = orders[buyOrderId];

        require(orderStorage != address(0), "OrderStorage not set");

        // Get best ask price (lowest sell price) - O(log n)
        uint128 bestAsk = IOrderStorage(orderStorage).getBestPrice(
            buyOrder.eventId,
            buyOrder.outcomeIndex,
            false // isBuy = false for sell orders
        );

        // Iterate through price levels while match is possible
        while (bestAsk != 0 && bestAsk <= uint128(buyOrder.price) && buyOrder.remainingAmount > 0) {
            // Get first order at this price (O(1))
            OrderKey sellKey = IOrderStorage(orderStorage).peekOrder(
                buyOrder.eventId,
                buyOrder.outcomeIndex,
                false, // isBuy = false
                bestAsk
            );

            // Iterate through orders at this price level (linked list)
            while (OrderStruct.isNotSentinel(sellKey) && buyOrder.remainingAmount > 0) {
                uint256 sellOrderId = orderKeyToId[sellKey];
                OrderStruct.Order storage sellOrder = orders[sellOrderId];

                // Skip invalid orders
                if (
                    sellOrder.status != OrderStruct.OrderStatus.Cancelled &&
                    sellOrder.status != OrderStruct.OrderStatus.Filled &&
                    sellOrder.remainingAmount > 0
                ) {
                    // Validate event and outcome match
                    if (buyOrder.eventId != sellOrder.eventId) {
                        revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                    }
                    if (buyOrder.outcomeIndex != sellOrder.outcomeIndex) {
                        revert OutcomeMismatch(buyOrder.outcomeIndex, sellOrder.outcomeIndex);
                    }

                    // Execute the match (buyer is Taker)
                    _executeMatch(buyOrderId, sellOrderId, true);
                }

                // Get next order in the linked list
                OrderStruct.DBOrder memory dbOrder = IOrderStorage(orderStorage).getOrder(sellKey);
                sellKey = dbOrder.next;
            }

            // Get next price level (next higher sell price) - O(log n)
            bestAsk = IOrderStorage(orderStorage).getNextPrice(
                buyOrder.eventId,
                buyOrder.outcomeIndex,
                false, // isBuy = false
                bestAsk
            );
        }
    }

    function _matchSell(uint256 sellOrderId, OutcomeOrderBook storage book) internal {
        OrderStruct.Order storage sellOrder = orders[sellOrderId];

        require(orderStorage != address(0), "OrderStorage not set");

        // Get best bid price (highest buy price) - O(log n)
        uint128 bestBid = IOrderStorage(orderStorage).getBestPrice(
            sellOrder.eventId,
            sellOrder.outcomeIndex,
            true // isBuy = true for buy orders
        );

        // Iterate through price levels while match is possible
        while (bestBid != 0 && bestBid >= uint128(sellOrder.price) && sellOrder.remainingAmount > 0) {
            // Get first order at this price (O(1))
            OrderKey buyKey = IOrderStorage(orderStorage).peekOrder(
                sellOrder.eventId,
                sellOrder.outcomeIndex,
                true, // isBuy = true
                bestBid
            );

            // Iterate through orders at this price level (linked list)
            while (OrderStruct.isNotSentinel(buyKey) && sellOrder.remainingAmount > 0) {
                uint256 buyOrderId = orderKeyToId[buyKey];
                OrderStruct.Order storage buyOrder = orders[buyOrderId];

                // Skip invalid orders
                if (
                    buyOrder.status != OrderStruct.OrderStatus.Cancelled &&
                    buyOrder.status != OrderStruct.OrderStatus.Filled &&
                    buyOrder.remainingAmount > 0
                ) {
                    // Validate event and outcome match
                    if (buyOrder.eventId != sellOrder.eventId) {
                        revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                    }
                    if (buyOrder.outcomeIndex != sellOrder.outcomeIndex) {
                        revert OutcomeMismatch(buyOrder.outcomeIndex, sellOrder.outcomeIndex);
                    }

                    // Execute the match (seller is Taker)
                    _executeMatch(buyOrderId, sellOrderId, false);
                }

                // Get next order in the linked list
                OrderStruct.DBOrder memory dbOrder = IOrderStorage(orderStorage).getOrder(buyKey);
                buyKey = dbOrder.next;
            }

            // Get next price level (next lower buy price) - O(log n)
            bestBid = IOrderStorage(orderStorage).getNextPrice(
                sellOrder.eventId,
                sellOrder.outcomeIndex,
                true, // isBuy = true
                bestBid
            );
        }
    }

    function _executeMatch(uint256 buyOrderId, uint256 sellOrderId, bool buyerIsTaker) internal {
        OrderStruct.Order storage buyOrder = orders[buyOrderId];
        OrderStruct.Order storage sellOrder = orders[sellOrderId];

        uint128 matchAmount = buyOrder.remainingAmount < sellOrder.remainingAmount
            ? buyOrder.remainingAmount
            : sellOrder.remainingAmount;

        // Correct match price: Taker accepts Maker's price
        // If buyer is Taker (new buy order): use sell order price (maker's price)
        // If seller is Taker (new sell order): use buy order price (maker's price)
        uint128 matchPrice = buyerIsTaker ? sellOrder.price : buyOrder.price;

        buyOrder.filledAmount += matchAmount;
        buyOrder.remainingAmount -= matchAmount;
        sellOrder.filledAmount += matchAmount;
        sellOrder.remainingAmount -= matchAmount;

        // Calculate match value in USD
        uint256 matchUsd = (uint256(matchAmount) * uint256(matchPrice)) / MAX_PRICE;

        // Implement maker-taker fee structure
        uint256 takerFee = 0;
        uint256 makerFee = 0;
        if (feeVaultManager != address(0)) {
            // Taker pays 0.25% (25 basis points)
            takerFee = IFeeVaultManager(feeVaultManager).calculateMakerTakerFee(matchUsd, false);
            // Maker pays 0.05% (5 basis points)
            makerFee = IFeeVaultManager(feeVaultManager).calculateMakerTakerFee(matchUsd, true);
        }

        // ✅ 持仓管理: 记录买家持仓增加
        positions[buyOrder.eventId][buyOrder.outcomeIndex][buyOrder.maker] += matchAmount;
        _recordPositionHolder(buyOrder.eventId, buyOrder.outcomeIndex, buyOrder.maker);

        // ✅ 持仓管理: 卖家持仓减少(卖出做空)
        if (positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.maker] >= matchAmount) {
            positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.maker] -= matchAmount;
        } else {
            positions[sellOrder.eventId][sellOrder.outcomeIndex][sellOrder.maker] = 0;
        }

        // 集成 FundingManager: 资金结算 (虚拟 Long Token 模型)
        IFundingManager(fundingManager).settleMatchedOrder(
            buyOrderId, // 买单 ID
            sellOrderId, // 卖单 ID
            buyOrder.maker, // 买家地址
            sellOrder.maker, // 卖家地址
            matchAmount, // 成交数量
            matchPrice, // 成交价格
            buyOrder.eventId, // 事件 ID
            buyOrder.outcomeIndex // 结果索引 (买卖同一 outcome)
        );

        // ✅ 收取 Maker-Taker 手续费
        if (feeVaultManager != address(0)) {
            // Collect taker fee
            if (takerFee > 0) {
                address taker = buyerIsTaker ? buyOrder.maker : sellOrder.maker;
                address takerToken = buyerIsTaker ? buyOrder.tokenAddress : sellOrder.tokenAddress;
                IFeeVaultManager(feeVaultManager).collectFee(
                    takerToken,
                    taker,
                    takerFee,
                    buyOrder.eventId,
                    "taker_execution"
                );
            }

            // Collect maker fee
            if (makerFee > 0) {
                address maker = buyerIsTaker ? sellOrder.maker : buyOrder.maker;
                address makerToken = buyerIsTaker ? sellOrder.tokenAddress : buyOrder.tokenAddress;
                IFeeVaultManager(feeVaultManager).collectFee(
                    makerToken,
                    maker,
                    makerFee,
                    buyOrder.eventId,
                    "maker_execution"
                );
            }
        }

        if (buyOrder.remainingAmount == 0) {
            buyOrder.status = OrderStruct.OrderStatus.Filled;
            _removeFromOrderBook(buyOrderId);
        } else if (buyOrder.filledAmount > 0) {
            buyOrder.status = OrderStruct.OrderStatus.Partial;
        }

        if (sellOrder.remainingAmount == 0) {
            sellOrder.status = OrderStruct.OrderStatus.Filled;
            _removeFromOrderBook(sellOrderId);
        } else if (sellOrder.filledAmount > 0) {
            sellOrder.status = OrderStruct.OrderStatus.Partial;
        }

        emit OrderMatched(buyOrderId, sellOrderId, buyOrder.eventId, buyOrder.outcomeIndex, matchPrice, matchAmount);
    }

    // ------------------------------------------------------------
    // Internal: orderbook ops 订单簿操作
    // ------------------------------------------------------------
    function _addToOrderBook(uint256 orderId) internal {
        OrderStruct.Order storage order = orders[orderId];

        // Generate OrderKey from the order
        OrderKey key = OrderStruct.hash(order);
        orderKeyToId[key] = orderId;

        // Convert to DBOrder for storage
        OrderStruct.DBOrder memory dbOrder = OrderStruct.DBOrder({
            order: order,
            next: OrderStruct.ORDERKEY_SENTINEL
        });

        // Store order in OrderStorage (Layer 3)
        require(orderStorage != address(0), "OrderStorage not set");
        IOrderStorage(orderStorage).storeOrder(key, dbOrder);

        // Insert price level if new (Layer 1) - O(log n)
        IOrderStorage(orderStorage).insertPrice(
            order.eventId,
            order.outcomeIndex,
            order.side == OrderStruct.Side.Buy,
            uint128(order.price)
        );

        // Enqueue order at price level (Layer 2) - O(1)
        IOrderStorage(orderStorage).enqueueOrder(
            order.eventId,
            order.outcomeIndex,
            order.side == OrderStruct.Side.Buy,
            uint128(order.price),
            key
        );
    }

    /**
     * @notice 从订单簿移除订单
     * @dev 检查队列是否为空，如果为空则从树中移除价格档位
     * @param orderId 订单 ID
     */
    function _removeFromOrderBook(uint256 orderId) internal {
        OrderStruct.Order storage order = orders[orderId];

        require(orderStorage != address(0), "OrderStorage not set");

        // Check if queue is empty at this price level
        bool isEmpty = IOrderStorage(orderStorage).isQueueEmpty(
            order.eventId,
            order.outcomeIndex,
            order.side == OrderStruct.Side.Buy,
            uint128(order.price)
        );

        // If queue is empty, remove price level from tree (O(log n))
        if (isEmpty) {
            IOrderStorage(orderStorage).removePrice(
                order.eventId,
                order.outcomeIndex,
                order.side == OrderStruct.Side.Buy,
                uint128(order.price)
            );
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
            OrderStruct.Order storage order = orders[orderIds[i]];
            if (order.status == OrderStruct.OrderStatus.Pending || order.status == OrderStruct.OrderStatus.Partial) {
                total += order.remainingAmount;
            }
        }
    }

    /**
     * @notice Calculate total amount at a specific price using OrderStorage
     * @dev Iterates through the linked list of orders at the given price
     * @param eventId Event ID
     * @param outcomeIndex Outcome index
     * @param isBuy Whether this is for buy orders (true) or sell orders (false)
     * @param price The price level
     * @return total Total remaining amount at this price
     */
    function _totalAtPriceFromStorage(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price)
        internal
        view
        returns (uint256 total)
    {
        if (orderStorage == address(0)) {
            return 0;
        }

        // Get first order at this price
        OrderKey key = IOrderStorage(orderStorage).peekOrder(eventId, outcomeIndex, isBuy, price);

        // Iterate through linked list
        while (OrderStruct.isNotSentinel(key)) {
            uint256 orderId = orderKeyToId[key];
            OrderStruct.Order storage order = orders[orderId];

            // Sum up remaining amount for valid orders
            if (
                (order.status == OrderStruct.OrderStatus.Pending || order.status == OrderStruct.OrderStatus.Partial)
                    && order.remainingAmount > 0
            ) {
                total += order.remainingAmount;
            }

            // Get next order in linked list
            OrderStruct.DBOrder memory dbOrder = IOrderStorage(orderStorage).getOrder(key);
            key = dbOrder.next;
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
            OrderStruct.Order storage order = orders[orderIds[i]];
            // 如果存在任何未完成的订单，返回 false
            if (
                (order.status == OrderStruct.OrderStatus.Pending || order.status == OrderStruct.OrderStatus.Partial) &&
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
                    OrderStruct.Order storage order = orders[ids[j]];
                if (order.status == OrderStruct.OrderStatus.Pending || order.status == OrderStruct.OrderStatus.Partial) {
                    order.status = OrderStruct.OrderStatus.Cancelled;

                    // 集成 FundingManager: 批量撤单解锁资金或 Long Token
                    if (order.remainingAmount > 0) {
                        IFundingManager(fundingManager).unlockForOrder(
                            order.maker,
                            ids[j], // orderId
                            order.side == OrderStruct.Side.Buy, // 是否为买单
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
                    OrderStruct.Order storage order = orders[ids[j]];
                if (order.status == OrderStruct.OrderStatus.Pending || order.status == OrderStruct.OrderStatus.Partial) {
                    order.status = OrderStruct.OrderStatus.Cancelled;

                    // 集成 FundingManager: 批量撤单解锁资金或 Long Token
                    if (order.remainingAmount > 0) {
                        IFundingManager(fundingManager).unlockForOrder(
                            order.maker,
                            ids[j], // orderId
                            order.side == OrderStruct.Side.Buy, // 是否为买单
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
    function getOrder(uint256 orderId) external view returns (OrderStruct.Order memory order) {
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

    /**
     * @notice 设置 OrderStorage 地址
     * @param _orderStorage OrderStorage 地址
     */
    function setOrderStorage(address _orderStorage) external onlyOwner nonReentrant {
        require(orderStorage == address(0), "OrderBookManager: already set");
        require(_orderStorage != address(0), "OrderBookManager: invalid address");
        orderStorage = _orderStorage;
    }
}
