// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IOrderBookPod {
    enum OrderSide {
        Buy,
        Sell
    }

    enum OrderStatus {
        Pending,
        Partial,
        Filled,
        Cancelled
    }

    struct Order {
        uint256 orderId;
        address user;
        uint256 eventId;
        uint256 outcomeId;
        OrderSide side;
        uint256 price;
        uint256 amount;
        uint256 filledAmount;
        uint256 remainingAmount;
        OrderStatus status;
        uint256 timestamp;
        address tokenAddress;
    }

    event OrderPlaced(
        uint256 indexed orderId,
        address indexed user,
        uint256 indexed eventId,
        uint256 outcomeId,
        OrderSide side,
        uint256 price,
        uint256 amount
    );

    event OrderMatched(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        uint256 indexed eventId,
        uint256 outcomeId,
        uint256 price,
        uint256 amount
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address indexed user,
        uint256 cancelledAmount
    );

    event EventSettled(uint256 indexed eventId, uint256 winningOutcomeId);

    event EventAdded(uint256 indexed eventId, uint256[] outcomeIds);

    error EventNotSupported(uint256 eventId);
    error OutcomeNotSupported(uint256 eventId, uint256 outcomeId);
    error EventAlreadySettled(uint256 eventId);
    error InvalidPrice(uint256 price);
    error InvalidAmount(uint256 amount);
    error PriceNotAlignedWithTickSize(uint256 price);
    error NotOrderOwner(uint256 orderId);
    error CannotCancelOrder(uint256 orderId);
    error EventMismatch(uint256 eventId1, uint256 eventId2);
    error OutcomeMismatch(uint256 outcomeId1, uint256 outcomeId2);

    function placeOrder(
        address user,
        uint256 eventId,
        uint256 outcomeId,
        OrderSide side,
        uint256 price,
        uint256 amount,
        address tokenAddress
    ) external returns (uint256 orderId);

    function cancelOrder(uint256 orderId) external;

    function settleEvent(uint256 eventId, uint256 winningOutcomeId) external;

    function addEvent(uint256 eventId, uint256[] calldata outcomeIds) external;

    function getBestBid(
        uint256 eventId,
        uint256 outcomeId
    ) external view returns (uint256 price, uint256 amount);

    function getBestAsk(
        uint256 eventId,
        uint256 outcomeId
    ) external view returns (uint256 price, uint256 amount);

    /**
     * @notice 获取订单信息
     * @param orderId 订单 ID
     * @return order 订单详情
     */
    function getOrder(uint256 orderId) external view returns (Order memory order);

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
    ) external view returns (uint256 position);

    /**
     * @notice 设置 FundingPod 地址
     * @param _fundingPod FundingPod 地址
     */
    function setFundingPod(address _fundingPod) external;
}
