// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./OrderBookPodStorage.sol";
import "../../interfaces/event/IOrderBookPod.sol";
import "../../interfaces/event/IFundingPod.sol";
import "../../interfaces/event/IFeeVaultPod.sol";

/**
 * @title OrderBookPod
 * @notice 订单簿 Pod - 负责订单撮合和持仓管理
 * @dev 集成 FundingPod 进行资金管理
 */
contract OrderBookPod is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    OrderBookPodStorage
{
    // ============ Modifiers ============

    modifier onlyOrderBookManager() {
        require(
            msg.sender == orderBookManager,
            "OrderBookPod: only orderBookManager"
        );
        _;
    }

    modifier onlyEventPod() {
        require(msg.sender == eventPod, "OrderBookPod: only eventPod");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _eventPod,
        address _fundingPod,
        address _feeVaultPod,
        address _orderBookManager
    ) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        eventPod = _eventPod;
        fundingPod = _fundingPod;
        feeVaultPod = _feeVaultPod;
        orderBookManager = _orderBookManager;
    }

    // ============ 外部函数 External Functions ============
    function placeOrder(
        address user,
        uint256 eventId,
        uint256 outcomeId,
        OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external whenNotPaused onlyOrderBookManager returns (uint256 orderId) {
        require(user != address(0), "OrderBookPod: invalid user address");
        if (!supportedEvents[eventId]) revert EventNotSupported(eventId);
        if (!supportedOutcomes[eventId][outcomeId])
            revert OutcomeNotSupported(eventId, outcomeId);
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (price == 0 || price > MAX_PRICE) revert InvalidPrice(price);
        if (price % TICK_SIZE != 0) revert PriceNotAlignedWithTickSize(price);
        if (amount == 0) revert InvalidAmount(amount);

        // ✅ 计算手续费
        uint256 fee = 0;
        if (feeVaultPod != address(0)) {
            fee = IFeeVaultPod(feeVaultPod).calculateFee(amount, "trade");
        }

        // ✅ 集成 FundingPod: 锁定下单所需资金 (包含手续费)
        uint256 requiredAmount = side == OrderSide.Buy
            ? ((amount + fee) * price) / MAX_PRICE  // 买单锁定: (amount + fee) * price
            : (amount + fee);                        // 卖单锁定: amount + fee

        IFundingPod(fundingPod).lockOnOrderPlaced(
            user,  // 使用传入的真实用户地址
            tokenAddress,
            requiredAmount,
            eventId,
            outcomeId
        );

        // ✅ 收取手续费
        if (fee > 0 && feeVaultPod != address(0)) {
            IFeeVaultPod(feeVaultPod).collectFee(
                tokenAddress,
                user,  // 使用传入的真实用户地址
                fee,
                eventId,
                "trade"
            );
        }

        orderId = nextOrderId++;
        orders[orderId] = Order({
            orderId: orderId,
            user: user,  // 使用传入的真实用户地址
            eventId: eventId,
            outcomeId: outcomeId,
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

        if (
            orders[orderId].status == OrderStatus.Pending ||
            orders[orderId].status == OrderStatus.Partial
        ) {
            _addToOrderBook(orderId);
        }

        emit OrderPlaced(
            orderId,
            user,  // 使用传入的真实用户地址
            eventId,
            outcomeId,
            side,
            price,
            amount
        );
    }

    function cancelOrder(uint256 orderId) external onlyOrderBookManager {
        Order storage order = orders[orderId];

        if (
            order.status != OrderStatus.Pending &&
            order.status != OrderStatus.Partial
        ) {
            revert CannotCancelOrder(orderId);
        }
        if (eventSettled[order.eventId])
            revert EventAlreadySettled(order.eventId);

        _removeFromOrderBook(orderId);

        order.status = OrderStatus.Cancelled;

        if (order.remainingAmount > 0) {
            // ✅ 集成 FundingPod: 解锁剩余未成交资金
            uint256 unlockedAmount = order.side == OrderSide.Buy
                ? (order.remainingAmount * order.price) / MAX_PRICE
                : order.remainingAmount;

            IFundingPod(fundingPod).unlockOnOrderCancelled(
                order.user,
                order.tokenAddress,
                unlockedAmount,
                order.eventId,
                order.outcomeId
            );
        }

        emit OrderCancelled(orderId, order.user, order.remainingAmount);
    }

    function settleEvent(
        uint256 eventId,
        uint256 winningOutcomeId
    ) external onlyEventPod {
        if (!supportedEvents[eventId]) revert EventNotSupported(eventId);
        if (eventSettled[eventId]) revert EventAlreadySettled(eventId);
        if (!supportedOutcomes[eventId][winningOutcomeId])
            revert OutcomeNotSupported(eventId, winningOutcomeId);

        eventSettled[eventId] = true;
        eventResults[eventId] = winningOutcomeId;

        _cancelAllPendingOrders(eventId);
        _settlePositions(eventId, winningOutcomeId);

        emit EventSettled(eventId, winningOutcomeId);
    }

    function addEvent(
        uint256 eventId,
        uint256[] calldata outcomeIds
    ) external onlyOrderBookManager {
        require(!supportedEvents[eventId], "OrderBookPod: event exists");
        supportedEvents[eventId] = true;

        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        for (uint256 i = 0; i < outcomeIds.length; i++) {
            uint256 outcomeId = outcomeIds[i];
            require(outcomeId > 0, "OrderBookPod: invalid outcome");
            supportedOutcomes[eventId][outcomeId] = true;
            eventOrderBook.supportedOutcomes.push(outcomeId);
        }

        emit EventAdded(eventId, outcomeIds);
    }

    function getBestBid(
        uint256 eventId,
        uint256 outcomeId
    ) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
            .outcomeOrderBooks[outcomeId];

        if (outcomeOrderBook.buyPriceLevels.length > 0) {
            price = outcomeOrderBook.buyPriceLevels[0];
            amount = _totalAtPrice(outcomeOrderBook.buyOrdersByPrice[price]);
        }
    }

    function getBestAsk(
        uint256 eventId,
        uint256 outcomeId
    ) external view returns (uint256 price, uint256 amount) {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
            .outcomeOrderBooks[outcomeId];

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
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
            .outcomeOrderBooks[order.outcomeId];

        if (order.side == OrderSide.Buy) {
            _matchBuy(orderId, outcomeOrderBook);
        } else {
            _matchSell(orderId, outcomeOrderBook);
        }
    }

    function _matchBuy(
        uint256 buyOrderId,
        OutcomeOrderBook storage book
    ) internal {
        Order storage buyOrder = orders[buyOrderId];

        for (
            uint256 i = 0;
            i < book.sellPriceLevels.length && buyOrder.remainingAmount > 0;
            i++
        ) {
            uint256 sellPrice = book.sellPriceLevels[i];
            if (sellPrice > buyOrder.price) break;

            uint256[] storage sellOrders = book.sellOrdersByPrice[sellPrice];
            for (
                uint256 j = 0;
                j < sellOrders.length && buyOrder.remainingAmount > 0;
                j++
            ) {
                uint256 sellOrderId = sellOrders[j];
                Order storage sellOrder = orders[sellOrderId];
                if (
                    sellOrder.status == OrderStatus.Cancelled ||
                    sellOrder.remainingAmount == 0
                ) continue;
                if (buyOrder.eventId != sellOrder.eventId)
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                if (buyOrder.outcomeId != sellOrder.outcomeId)
                    revert OutcomeMismatch(
                        buyOrder.outcomeId,
                        sellOrder.outcomeId
                    );
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _matchSell(
        uint256 sellOrderId,
        OutcomeOrderBook storage book
    ) internal {
        Order storage sellOrder = orders[sellOrderId];

        for (
            uint256 i = 0;
            i < book.buyPriceLevels.length && sellOrder.remainingAmount > 0;
            i++
        ) {
            uint256 buyPrice = book.buyPriceLevels[i];
            if (buyPrice < sellOrder.price) break;

            uint256[] storage buyOrders = book.buyOrdersByPrice[buyPrice];
            for (
                uint256 j = 0;
                j < buyOrders.length && sellOrder.remainingAmount > 0;
                j++
            ) {
                uint256 buyOrderId = buyOrders[j];
                Order storage buyOrder = orders[buyOrderId];
                if (
                    buyOrder.status == OrderStatus.Cancelled ||
                    buyOrder.remainingAmount == 0
                ) continue;
                if (buyOrder.eventId != sellOrder.eventId)
                    revert EventMismatch(buyOrder.eventId, sellOrder.eventId);
                if (buyOrder.outcomeId != sellOrder.outcomeId)
                    revert OutcomeMismatch(
                        buyOrder.outcomeId,
                        sellOrder.outcomeId
                    );
                _executeMatch(buyOrderId, sellOrderId);
            }
        }
    }

    function _executeMatch(uint256 buyOrderId, uint256 sellOrderId) internal {
        Order storage buyOrder = orders[buyOrderId];
        Order storage sellOrder = orders[sellOrderId];

        uint256 matchAmount = buyOrder.remainingAmount <
            sellOrder.remainingAmount
            ? buyOrder.remainingAmount
            : sellOrder.remainingAmount;

        uint256 matchPrice = sellOrder.price;

        buyOrder.filledAmount += matchAmount;
        buyOrder.remainingAmount -= matchAmount;
        sellOrder.filledAmount += matchAmount;
        sellOrder.remainingAmount -= matchAmount;

        // ✅ 计算撮合手续费
        uint256 matchFee = 0;
        if (feeVaultPod != address(0)) {
            matchFee = IFeeVaultPod(feeVaultPod).calculateFee(matchAmount, "trade");
        }

        // ✅ 持仓管理: 记录买家持仓增加
        positions[buyOrder.eventId][buyOrder.outcomeId][buyOrder.user] += matchAmount;
        _recordPositionHolder(buyOrder.eventId, buyOrder.outcomeId, buyOrder.user);

        // ✅ 持仓管理: 卖家持仓减少(卖出做空)
        if (
            positions[sellOrder.eventId][sellOrder.outcomeId][sellOrder.user] >=
            matchAmount
        ) {
            positions[sellOrder.eventId][sellOrder.outcomeId][
                sellOrder.user
            ] -= matchAmount;
        } else {
            positions[sellOrder.eventId][sellOrder.outcomeId][
                sellOrder.user
            ] = 0;
        }

        // ✅ 集成 FundingPod: 资金结算
        IFundingPod(fundingPod).settleMatchedOrder(
            buyOrder.user,
            sellOrder.user,
            buyOrder.tokenAddress,
            matchAmount,
            matchPrice,
            buyOrder.eventId,
            buyOrder.outcomeId,
            sellOrder.outcomeId
        );

        // ✅ 收取撮合手续费
        if (matchFee > 0 && feeVaultPod != address(0)) {
            // 买卖双方各支付一半手续费
            uint256 buyerFee = matchFee / 2;
            uint256 sellerFee = matchFee - buyerFee;

            if (buyerFee > 0) {
                IFeeVaultPod(feeVaultPod).collectFee(
                    buyOrder.tokenAddress,
                    buyOrder.user,
                    buyerFee,
                    buyOrder.eventId,
                    "trade"
                );
            }

            if (sellerFee > 0) {
                IFeeVaultPod(feeVaultPod).collectFee(
                    sellOrder.tokenAddress,
                    sellOrder.user,
                    sellerFee,
                    sellOrder.eventId,
                    "trade"
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

        emit OrderMatched(
            buyOrderId,
            sellOrderId,
            buyOrder.eventId,
            buyOrder.outcomeId,
            matchPrice,
            matchAmount
        );
    }

    // ------------------------------------------------------------
    // Internal: orderbook ops 订单簿操作
    // ------------------------------------------------------------
    function _addToOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
            .outcomeOrderBooks[order.outcomeId];

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

    function _removeFromOrderBook(uint256 orderId) internal {
        Order storage order = orders[orderId];
        EventOrderBook storage eventOrderBook = eventOrderBooks[order.eventId];
        OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
            .outcomeOrderBooks[order.outcomeId];

        if (order.side == OrderSide.Buy) {
            uint256[] storage priceOrders = outcomeOrderBook.buyOrdersByPrice[
                order.price
            ];
            _removeFromArray(priceOrders, orderId);
            if (priceOrders.length == 0) {
                _removeBuyPrice(outcomeOrderBook, order.price);
            }
        } else {
            uint256[] storage priceOrders = outcomeOrderBook.sellOrdersByPrice[
                order.price
            ];
            _removeFromArray(priceOrders, orderId);
            if (priceOrders.length == 0) {
                _removeSellPrice(outcomeOrderBook, order.price);
            }
        }
    }

    function _insertBuyPrice(
        OutcomeOrderBook storage orderBook,
        uint256 price
    ) internal {
        uint256 i = 0;
        while (
            i < orderBook.buyPriceLevels.length &&
            orderBook.buyPriceLevels[i] > price
        ) {
            i++;
        }
        if (
            i < orderBook.buyPriceLevels.length &&
            orderBook.buyPriceLevels[i] == price
        ) return;

        orderBook.buyPriceLevels.push(0);
        for (uint256 j = orderBook.buyPriceLevels.length - 1; j > i; j--) {
            orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[j - 1];
        }
        orderBook.buyPriceLevels[i] = price;
    }

    function _insertSellPrice(
        OutcomeOrderBook storage orderBook,
        uint256 price
    ) internal {
        uint256 i = 0;
        while (
            i < orderBook.sellPriceLevels.length &&
            orderBook.sellPriceLevels[i] < price
        ) {
            i++;
        }
        if (
            i < orderBook.sellPriceLevels.length &&
            orderBook.sellPriceLevels[i] == price
        ) return;

        orderBook.sellPriceLevels.push(0);
        for (uint256 j = orderBook.sellPriceLevels.length - 1; j > i; j--) {
            orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[j - 1];
        }
        orderBook.sellPriceLevels[i] = price;
    }

    function _removeBuyPrice(
        OutcomeOrderBook storage orderBook,
        uint256 price
    ) internal {
        for (uint256 i = 0; i < orderBook.buyPriceLevels.length; i++) {
            if (orderBook.buyPriceLevels[i] == price) {
                for (
                    uint256 j = i;
                    j < orderBook.buyPriceLevels.length - 1;
                    j++
                ) {
                    orderBook.buyPriceLevels[j] = orderBook.buyPriceLevels[
                        j + 1
                    ];
                }
                orderBook.buyPriceLevels.pop();
                break;
            }
        }
    }

    function _removeSellPrice(
        OutcomeOrderBook storage orderBook,
        uint256 price
    ) internal {
        for (uint256 i = 0; i < orderBook.sellPriceLevels.length; i++) {
            if (orderBook.sellPriceLevels[i] == price) {
                for (
                    uint256 j = i;
                    j < orderBook.sellPriceLevels.length - 1;
                    j++
                ) {
                    orderBook.sellPriceLevels[j] = orderBook.sellPriceLevels[
                        j + 1
                    ];
                }
                orderBook.sellPriceLevels.pop();
                break;
            }
        }
    }

    function _removeFromArray(uint256[] storage array, uint256 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    function _totalAtPrice(
        uint256[] storage orderIds
    ) internal view returns (uint256 total) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            Order storage order = orders[orderIds[i]];
            if (
                order.status == OrderStatus.Pending ||
                order.status == OrderStatus.Partial
            ) {
                total += order.remainingAmount;
            }
        }
    }

    // ------------------------------------------------------------
    // Internal: cancel & settle 撤单与结算
    // ------------------------------------------------------------
    function _cancelAllPendingOrders(uint256 eventId) internal {
        EventOrderBook storage eventOrderBook = eventOrderBooks[eventId];

        for (uint256 i = 0; i < eventOrderBook.supportedOutcomes.length; i++) {
            uint256 outcomeId = eventOrderBook.supportedOutcomes[i];
            OutcomeOrderBook storage outcomeOrderBook = eventOrderBook
                .outcomeOrderBooks[outcomeId];
            _cancelMarketOrders(outcomeOrderBook);
        }
    }

    function _cancelMarketOrders(
        OutcomeOrderBook storage marketOrderBook
    ) internal {
        for (uint256 i = 0; i < marketOrderBook.buyPriceLevels.length; i++) {
            uint256 price = marketOrderBook.buyPriceLevels[i];
            uint256[] storage ids = marketOrderBook.buyOrdersByPrice[price];
            for (uint256 j = 0; j < ids.length; j++) {
                Order storage order = orders[ids[j]];
                if (
                    order.status == OrderStatus.Pending ||
                    order.status == OrderStatus.Partial
                ) {
                    order.status = OrderStatus.Cancelled;

                    // ✅ 集成 FundingPod: 批量撤单解锁资金
                    if (order.remainingAmount > 0) {
                        uint256 unlockedAmount = order.side == OrderSide.Buy
                            ? (order.remainingAmount * order.price) / MAX_PRICE
                            : order.remainingAmount;

                        IFundingPod(fundingPod).unlockOnOrderCancelled(
                            order.user,
                            order.tokenAddress,
                            unlockedAmount,
                            order.eventId,
                            order.outcomeId
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
                if (
                    order.status == OrderStatus.Pending ||
                    order.status == OrderStatus.Partial
                ) {
                    order.status = OrderStatus.Cancelled;

                    // ✅ 集成 FundingPod: 批量撤单解锁资金
                    if (order.remainingAmount > 0) {
                        uint256 unlockedAmount = order.side == OrderSide.Buy
                            ? (order.remainingAmount * order.price) / MAX_PRICE
                            : order.remainingAmount;

                        IFundingPod(fundingPod).unlockOnOrderCancelled(
                            order.user,
                            order.tokenAddress,
                            unlockedAmount,
                            order.eventId,
                            order.outcomeId
                        );
                    }
                }
            }
        }
    }

    // ✅ 结算持仓 - 集成 FundingPod 分配奖金
    function _settlePositions(
        uint256 eventId,
        uint256 winningOutcomeId
    ) internal {
        // 获取获胜结果的所有持仓者
        address[] storage winners = positionHolders[eventId][winningOutcomeId];
        if (winners.length == 0) return; // 没有获胜者

        // 构建获胜者和持仓数组
        uint256[] memory winningPositions = new uint256[](winners.length);
        address tokenAddress = address(0); // 需要从订单中获取 token 地址

        // 收集获胜者持仓
        for (uint256 i = 0; i < winners.length; i++) {
            winningPositions[i] = positions[eventId][winningOutcomeId][
                winners[i]
            ];

            // 从该用户的订单中获取 token 地址
            if (tokenAddress == address(0) && userOrders[winners[i]].length > 0) {
                for (uint256 j = 0; j < userOrders[winners[i]].length; j++) {
                    uint256 orderId = userOrders[winners[i]][j];
                    if (orders[orderId].eventId == eventId) {
                        tokenAddress = orders[orderId].tokenAddress;
                        break;
                    }
                }
            }
        }

        // 如果找到了 token 地址,调用 FundingPod 结算
        if (tokenAddress != address(0)) {
            IFundingPod(fundingPod).settleEvent(
                eventId,
                winningOutcomeId,
                tokenAddress,
                winners,
                winningPositions
            );
        }
    }

    // ============ 持仓跟踪辅助函数 Position Tracking Helper ============

    /**
     * @notice 记录持仓者(避免重复记录)
     * @param eventId 事件 ID
     * @param outcomeId 结果 ID
     * @param user 用户地址
     */
    function _recordPositionHolder(
        uint256 eventId,
        uint256 outcomeId,
        address user
    ) internal {
        if (!isPositionHolder[eventId][outcomeId][user]) {
            positionHolders[eventId][outcomeId].push(user);
            isPositionHolder[eventId][outcomeId][user] = true;
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
     * @param outcomeId 结果 ID
     * @param user 用户地址
     * @return position 持仓数量
     */
    function getPosition(
        uint256 eventId,
        uint256 outcomeId,
        address user
    ) external view returns (uint256 position) {
        return positions[eventId][outcomeId][user];
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 设置 FundingPod 地址
     * @param _fundingPod FundingPod 地址
     */
    function setFundingPod(address _fundingPod) external onlyOwner {
        require(_fundingPod != address(0), "OrderBookPod: invalid address");
        fundingPod = _fundingPod;
    }

    /**
     * @notice 设置 FeeVaultPod 地址
     * @param _feeVaultPod FeeVaultPod 地址
     */
    function setFeeVaultPod(address _feeVaultPod) external onlyOwner {
        require(_feeVaultPod != address(0), "OrderBookPod: invalid address");
        feeVaultPod = _feeVaultPod;
    }

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
}
