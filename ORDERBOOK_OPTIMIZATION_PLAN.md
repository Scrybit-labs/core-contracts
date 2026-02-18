# OrderBook 优化实施计划

## 概述

重构 OrderBookManager 以使用红黑树实现 O(log n) 的价格层级操作，使用链表队列实现 FIFO 订单管理，并实现 maker-taker 费用差异化以激励流动性提供（解决 issue #11）。

## ⚠️ 关键 Bug 修复

**当前实现的严重问题**：`_executeMatch` 函数中始终使用 `sellOrder.price` 作为成交价格（line 404），这是错误的！

**正确的价格匹配规则**：
- 买单价格 >= 卖单价格时才能撮合
- **成交价格 = Taker 接受 Maker 的价格**
  - 买家是 Taker（买单刚下单）：成交价 = 卖单价格（买家接受卖家的挂单价）
  - 卖家是 Taker（卖单刚下单）：成交价 = 买单价格（卖家接受买家的出价）

**修复方案**：
```solidity
// 错误（当前实现）
uint256 matchPrice = sellOrder.price;

// 正确
uint256 matchPrice = buyerIsTaker ? sellOrder.price : buyOrder.price;
```

此 bug 会导致：
- 卖家 Taker 时获得错误的成交价格（应该是买单价格，实际是卖单价格）
- 价格发现机制失效
- 套利机会被错误定价

## 当前状态分析

### OrderBookManager.sol 的痛点

| 操作 | 当前实现 | 优化后 | 权衡说明 |
|------|---------|--------|---------|
| 插入价格层级 | O(n) 数组移位 | O(log n) 树插入 | ✅ 显著提升 |
| 删除价格层级 | O(n) 数组移位 | O(log n) 树删除 | ✅ 显著提升 |
| 查找最优价格 | O(1) array[0] | O(log n) tree first/last | ⚠️ 轻微下降，但可接受* |
| 订单撮合 | O(n*m) 嵌套循环 | O(log n * m) | ✅ 更快的价格迭代 |

\* **查找最优价格的权衡**：虽然从 O(1) 变为 O(log n)，但这是可接受的，因为：
1. 插入/删除操作频率远高于查找（每次下单/取消 vs 每次撮合迭代）
2. O(log n) 仍然很快（1000 个价格层级仅需 ~10 次操作）
3. 整体撮合性能提升（O(n) → O(log n) 的价格层级遍历）

### 当前订单存储（12 个存储槽 - 未优化）

```solidity
struct Order {
    uint256 orderId;        // slot 1
    address user;           // slot 2
    uint256 eventId;        // slot 3
    uint8 outcomeIndex;     // slot 4 (浪费 31 字节)
    OrderSide side;         // slot 5 (浪费 31 字节)
    uint256 price;          // slot 6
    uint256 amount;         // slot 7
    uint256 filledAmount;   // slot 8
    uint256 remainingAmount;// slot 9
    OrderStatus status;     // slot 10 (浪费 31 字节)
    uint256 timestamp;      // slot 11
    address tokenAddress;   // slot 12
}
```

### 当前费用结构（无 Maker-Taker 区分）

- 下单费用：0.1%（10 个基点）- 所有订单
- 成交费用：0.2%（20 个基点）- 买卖双方各 50%
- **问题**：没有激励流动性提供者（makers）

## 现有基础设施（好消息！）

✅ **OrderStruct.sol** 已经具备：
- `OrderKey` 类型（bytes32 包装器）
- `DBOrder` 结构体带 `next` 指针（链表就绪！）
- `OrderQueue` 结构体带 `head`/`tail`（FIFO 队列就绪！）
- `hash()`, `isSentinel()` 辅助函数

✅ **RedBlackTreeLibrary.sol** 已经存在：
- `Price` 类型（uint128），`Tree` 结构体
- `first()`, `last()`, `next()`, `prev()`, `exists()`, `insert()`, `remove()`
- 所有价格层级管理的 O(log n) 操作

## 新架构

### 三层存储设计

```
┌─────────────────────────────────────────────────────────────┐
│ 第 1 层：价格树（RedBlackTree）- O(log n)                    │
│ ├── 买单树：降序（最优 = last/max）                          │
│ ├── 卖单树：升序（最优 = first/min）                         │
│ └── 操作：insertPrice, removePrice, getBestPrice            │
├─────────────────────────────────────────────────────────────┤
│ 第 2 层：订单队列（链表）- O(1)                              │
│ ├── FIFO：最早的订单在 head，最新的在 tail                   │
│ ├── 使用现有的 DBOrder.next 指针                            │
│ └── 操作：enqueueOrder, dequeueOrder, peekOrder            │
├─────────────────────────────────────────────────────────────┤
│ 第 3 层：全局订单（映射）- O(1)                              │
│ ├── orders[OrderKey] => DBOrder                            │
│ └── 操作：storeOrder, getOrder, deleteOrder                │
└─────────────────────────────────────────────────────────────┘
```

### Maker-Taker 费用结构

| 角色 | 费用类型 | 当前 | 建议 | 基点 |
|------|---------|------|------|------|
| Maker | 下单费用 | 0.1% | 0% | 0 |
| Maker | 成交费用 | 0.1% | 0.05% | 5 |
| Taker | 成交费用 | 0.1% | 0.25% | 25 |

**Maker** = 挂单在订单簿中的订单（提供流动性）
**Taker** = 立即成交的订单（消耗流动性）

## 实施步骤

### 阶段 1：创建 OrderStorage 合约

**文件**：`src/core/OrderStorage.sol`

创建封装三层存储的新合约：

```solidity
contract OrderStorage {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    // 第 1 层：价格树
    // eventId => outcomeIndex => side (0=buy, 1=sell) => Tree
    mapping(uint256 => mapping(uint8 => mapping(uint8 => Tree))) internal priceTrees;

    // 第 2 层：订单队列
    // eventId => outcomeIndex => side => price => OrderQueue
    mapping(uint256 => mapping(uint8 => mapping(uint8 => mapping(Price => OrderQueue)))) internal orderQueues;

    // 第 3 层：全局订单
    mapping(OrderKey => DBOrder) internal orders;

    // 价格树操作
    function insertPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;
    function removePrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;
    function getBestPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy) external view returns (uint128);
    function getNextPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 current) external view returns (uint128);

    // 订单队列操作
    function enqueueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price, OrderKey key) external;
    function dequeueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external returns (OrderKey);
    function peekOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external view returns (OrderKey);
    function isQueueEmpty(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external view returns (bool);

    // 全局订单操作
    function storeOrder(OrderKey key, DBOrder calldata order) external;
    function getOrder(OrderKey key) external view returns (DBOrder memory);
    function deleteOrder(OrderKey key) external;
}
```

**关键实现细节**：
- 使用 `Price.wrap(uint128)` 进行树操作
- 买单树：使用 `tree.last()` 获取最高买价
- 卖单树：使用 `tree.first()` 获取最低卖价
- 链表：追加到 tail，从 head 出队（FIFO）
- 当队列为空时从树中删除价格层级

### 阶段 2：创建 OrderValidator 合约

**文件**：`src/core/OrderValidator.sol`

用于验证和 EIP712 签名支持的抽象合约：

```solidity
abstract contract OrderValidator is EIP712Upgradeable {
    // 执行状态跟踪
    mapping(OrderKey => uint128) public orderFilledAmount;
    mapping(OrderKey => bool) public orderCancelled;

    // 常量
    uint128 public constant TICK_SIZE = 10;
    uint128 public constant MAX_PRICE = 10000;

    // EIP712 类型哈希
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint8 side,address maker,uint64 expiry,uint64 salt,uint128 price,uint128 amount,uint256 eventId,uint8 outcomeIndex)"
    );

    function validateOrderParams(
        address maker,
        uint256 eventId,
        uint8 outcomeIndex,
        uint128 price,
        uint128 amount,
        uint64 expiry
    ) external view returns (bool valid, string memory reason);

    function verifyOrderSignature(
        OrderStruct.Order calldata order,
        bytes calldata signature
    ) external view returns (bool);

    function markFilled(OrderKey key, uint128 amount) internal;
    function markCancelled(OrderKey key) internal;

    // 实现 validateOrderParams
    function validateOrderParams(
        address maker,
        uint256 eventId,
        uint8 outcomeIndex,
        uint128 price,
        uint128 amount,
        uint64 expiry
    ) public view returns (bool valid, string memory reason) {
        if (maker == address(0)) {
            return (false, "Invalid maker address");
        }
        if (price == 0 || price > MAX_PRICE) {
            return (false, "Price out of range");
        }
        if (price % TICK_SIZE != 0) {
            return (false, "Price not aligned with tick size");
        }
        if (amount == 0) {
            return (false, "Amount must be greater than zero");
        }
        if (expiry != 0 && expiry < block.timestamp) {
            return (false, "Order expired");
        }
        return (true, "");
    }

    // 实现 verifyOrderSignature
    function verifyOrderSignature(
        OrderStruct.Order calldata order,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.side,
            order.maker,
            order.expiry,
            order.salt,
            order.price,
            order.amount
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        return signer == order.maker && signer != address(0);
    }
}
```

**关键实现细节**：
- 继承 OpenZeppelin 的 `EIP712Upgradeable`
- 使用 `_hashTypedDataV4()` 进行签名验证
- 在域分隔符中包含 `chainId` 和合约地址
- 验证价格与 TICK_SIZE（10 个基点）对齐
- 如果非零则检查过期时间戳

### 阶段 3：更新 FeeVaultManager 以支持 Maker-Taker 费用

**文件**：`src/core/FeeVaultManager.sol`

修改初始化并添加新的费用计算函数：

```solidity
function initialize(address initialOwner) external initializer {
    __Ownable_init(initialOwner);
    __Pausable_init();

    // Maker 费用（流动性提供者）
    _setFeeRate("maker_placement", 0);   // 0% - 免费下单
    _setFeeRate("maker_execution", 5);   // 0.05% - 成交时最小费用

    // Taker 费用（流动性消耗者）
    _setFeeRate("taker_execution", 25);  // 0.25% - 为即时性付费
}

function calculateMakerTakerFee(
    uint256 amount,
    bool isMaker
) external view returns (uint256 fee) {
    string memory feeType = isMaker ? "maker_execution" : "taker_execution";
    bytes32 key = keccack256(hash(bytes(feeType)));
    uint256 rate = feeRates[key];
    return (amount * rate) / FEE_PRECISION;
}
```

**接口更新**（`src/interfaces/core/IFeeVaultManager.sol`）：
```solidity
function calculateMakerTakerFee(uint256 amount, bool isMaker) external view returns (uint256 fee);
```

### 阶段 4：重构 OrderBookManager

**文件**：`src/core/OrderBookManager.sol`

主要变更：

**关键：OrderValidator 调用位置**

OrderValidator 应该在以下位置调用：

1. **placeOrder()** - 下单时（必须）：
   ```solidity
   function placeOrder(...) external {
       // 使用 OrderValidator 验证参数
       (bool valid, string memory reason) = validateOrderParams(
           msg.sender,
           eventId,
           outcomeIndex,
           uint128(price),
           uint128(amount),
           0  // expiry (0 = 永不过期)
       );
       require(valid, reason);

       // ... 继续下单逻辑
   }
   ```

2. **placeOrderWithSignature()** - 链下签名订单（新功能，可选）：
   ```solidity
   function placeOrderWithSignature(
       OrderStruct.Order calldata order,
       bytes calldata signature
   ) external {
       // 验证签名
       require(verifyOrderSignature(order, signature), "Invalid signature");

       // 验证参数
       (bool valid, string memory reason) = validateOrderParams(...);
       require(valid, reason);

       // ... 下单逻辑
   }
   ```

3. **_matchOrder()** - 撮合时（可选，性能优化）：
   ```solidity
   // 跳过已取消的订单
   if (orderCancelled[orderKey]) {
       continue;
   }
   ```

4. **cancelOrder()** - 取消订单时（当前验证已足够）：
   ```solidity
   // 当前的状态检查已经足够
   // 不需要额外调用 OrderValidator
   ```

1. **添加存储引用**：
```solidity
contract OrderBookManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    OrderValidator,  // 继承验证
    IOrderBookManager
{
    OrderStorage public orderStorage;

    // 保留旧映射以实现向后兼容
    mapping(uint256 => Order) public orders;
    mapping(OrderKey => uint256) public orderKeyToId;
}
```

2. **重构 placeOrder 以使用 OrderValidator**（新增）：
```solidity
function placeOrder(
    uint256 eventId,
    uint8 outcomeIndex,
    OrderSide side,
    uint256 price,
    uint256 amount,
    address tokenAddress
) external whenNotPaused nonReentrant returns (uint256 orderId) {
    address user = msg.sender;

    // 使用 OrderValidator 统一验证（替换原有的分散验证）
    (bool valid, string memory reason) = validateOrderParams(
        user,
        eventId,
        outcomeIndex,
        uint128(price),
        uint128(amount),
        0  // expiry: 0 表示永不过期
    );
    require(valid, reason);

    // 额外验证：事件支持和未结算
    uint8 outcomeCount = eventOutcomeCount[eventId];
    require(outcomeCount > 0, "Event not supported");
    require(outcomeIndex < outcomeCount, "Outcome not supported");
    require(!eventSettled[eventId], "Event already settled");

    // 计算费用（根据是否立即成交判断 maker/taker）
    uint256 tradeUsd = (amount * price) / MAX_PRICE;

    // 检查是否会立即成交（判断 maker/taker）
    bool willMatchImmediately = _willOrderMatchImmediately(eventId, outcomeIndex, side, price);

    uint256 placementFee = 0;
    if (feeVaultManager != address(0)) {
        if (willMatchImmediately) {
            // Taker: 不收取下单费用，只收取成交费用
            placementFee = 0;
        } else {
            // Maker: 不收取下单费用（0%）
            placementFee = 0;
        }
    }

    // 锁定资金
    IFundingManager(fundingManager).lockForOrder(...);

    // 创建订单
    orderId = nextOrderId++;
    orders[orderId] = Order({...});

    // 尝试撮合
    _matchOrder(orderId);

    // 如果有剩余，加入订单簿
    if (orders[orderId].remainingAmount > 0) {
        _addToOrderBook(orderId);
    }

    emit OrderPlaced(orderId, user, eventId, outcomeIndex, side, price, amount);
}

// 辅助函数：判断订单是否会立即成交
function _willOrderMatchImmediately(
    uint256 eventId,
    uint8 outcomeIndex,
    OrderSide side,
    uint256 price
) internal view returns (bool) {
    if (side == OrderSide.Buy) {
        uint128 bestAsk = orderStorage.getBestPrice(eventId, outcomeIndex, false);
        return bestAsk != 0 && bestAsk <= price;
    } else {
        uint128 bestBid = orderStorage.getBestPrice(eventId, outcomeIndex, true);
        return bestBid != 0 && bestBid >= price;
    }
}
```

3. **重构 _addToOrderBook**（替换 lines 485-505）：
```solidity
function _addToOrderBook(uint256 orderId) internal {
    Order storage order = orders[orderId];

    // 生成 OrderKey
    OrderStruct.Order memory structOrder = _convertToStructOrder(order, orderId);
    OrderKey key = OrderStruct.hash(structOrder);
    orderKeyToId[key] = orderId;

    uint8 side = order.side == OrderSide.Buy ? 0 : 1;
    uint128 price = uint128(order.price);

    // 如果是新价格层级则插入（O(log n)）
    orderStorage.insertPrice(order.eventId, order.outcomeIndex, side == 0, price);

    // 在价格层级入队订单（O(1)）
    orderStorage.enqueueOrder(order.eventId, order.outcomeIndex, side == 0, price, key);
}
```

3. **重构 _removeFromOrderBook**（替换 lines 507-522）：
```solidity
function _removeFromOrderBook(uint256 orderId) internal {
    Order storage order = orders[orderId];
    uint8 side = order.side == OrderSide.Buy ? 0 : 1;
    uint128 price = uint128(order.price);

    // 检查删除后队列是否为空
    if (orderStorage.isQueueEmpty(order.eventId, order.outcomeIndex, side == 0, price)) {
        // 从树中删除价格层级（O(log n)）
        orderStorage.removePrice(order.eventId, order.outcomeIndex, side == 0, price);
    }
}
```

4. **重构 _matchBuy**（替换 lines 332-362）：
```solidity
function _matchBuy(uint256 buyOrderId, uint256 eventId, uint8 outcomeIndex) internal {
    Order storage buyOrder = orders[buyOrderId];

    // 通过树获取最优卖价（O(log n)）
    uint128 bestAsk = orderStorage.getBestPrice(eventId, outcomeIndex, false);

    while (bestAsk != 0 && bestAsk <= uint128(buyOrder.price) && buyOrder.remainingAmount > 0) {
        // 获取该价格的第一个订单（O(1)）
        OrderKey sellKey = orderStorage.peekOrder(eventId, outcomeIndex, false, bestAsk);

        while (OrderStruct.isNotSentinel(sellKey) && buyOrder.remainingAmount > 0) {
            uint256 sellOrderId = orderKeyToId[sellKey];
            Order storage sellOrder = orders[sellOrderId];

            if (sellOrder.remainingAmount > 0) {
                // 使用 maker-taker 费用执行撮合
                _executeMatchWithFees(buyOrderId, sellOrderId, true); // buyOrder 是 taker
            }

            // 获取队列中的下一个订单
            DBOrder memory dbOrder = orderStorage.getOrder(sellKey);
            sellKey = dbOrder.next;
        }

        // 获取下一个价格层级（O(log n)）
        bestAsk = orderStorage.getNextPrice(eventId, outcomeIndex, false, bestAsk);
    }
}
```

5. **更新 _executeMatch 以支持 Maker-Taker 费用**（替换 lines 396-483）：
```solidity
function _executeMatchWithFees(
    uint256 buyOrderId,
    uint256 sellOrderId,
    bool buyerIsTaker
) internal {
    Order storage buyOrder = orders[buyOrderId];
    Order storage sellOrder = orders[sellOrderId];

    uint256 matchAmount = buyOrder.remainingAmount < sellOrder.remainingAmount
        ? buyOrder.remainingAmount
        : sellOrder.remainingAmount;

    // 成交价格 = Taker 接受 Maker 的价格
    // - 买家是 Taker：成交价 = 卖单价格（买家接受卖家的挂单价）
    // - 卖家是 Taker：成交价 = 买单价格（卖家接受买家的出价）
    uint256 matchPrice = buyerIsTaker ? sellOrder.price : buyOrder.price;
    uint256 matchUsd = (matchAmount * matchPrice) / MAX_PRICE;

    // 计算 maker-taker 费用
    uint256 takerFee = IFeeVaultManager(feeVaultManager).calculateMakerTakerFee(matchUsd, false);
    uint256 makerFee = IFeeVaultManager(feeVaultManager).calculateMakerTakerFee(matchUsd, true);

    // 根据谁是 taker 分配费用
    address taker = buyerIsTaker ? buyOrder.user : sellOrder.user;
    address maker = buyerIsTaker ? sellOrder.user : buyOrder.user;

    // 收取费用
    if (takerFee > 0) {
        IFeeVaultManager(feeVaultManager).collectFee(
            buyOrder.tokenAddress,
            taker,
            takerFee,
            buyOrder.eventId,
            "taker_execution"
        );
    }

    if (makerFee > 0) {
        IFeeVaultManager(feeVaultManager).collectFee(
            sellOrder.tokenAddress,
            maker,
            makerFee,
            sellOrder.eventId,
            "maker_execution"
        );
    }

    // 更新订单状态
    buyOrder.filledAmount += matchAmount;
    buyOrder.remainingAmount -= matchAmount;
    sellOrder.filledAmount += matchAmount;
    sellOrder.remainingAmount -= matchAmount;

    // ... 其余结算逻辑不变
}
```

### 阶段 5：创建接口文件

**文件**：`src/interfaces/core/IOrderStorage.sol`
```solidity
interface IOrderStorage {
    function insertPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;
    function removePrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external;
    function getBestPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy) external view returns (uint128);
    function getNextPrice(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 current) external view returns (uint128);
    function enqueueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price, OrderKey key) external;
    function dequeueOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external returns (OrderKey);
    function peekOrder(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external view returns (OrderKey);
    function isQueueEmpty(uint256 eventId, uint8 outcomeIndex, bool isBuy, uint128 price) external view returns (bool);
    function storeOrder(OrderKey key, DBOrder calldata order) external;
    function getOrder(OrderKey key) external view returns (DBOrder memory);
    function deleteOrder(OrderKey key) external;
}
```

**文件**：`src/interfaces/core/IOrderValidator.sol`
```solidity
interface IOrderValidator {
    function validateOrderParams(
        address maker,
        uint256 eventId,
        uint8 outcomeIndex,
        uint128 price,
        uint128 amount,
        uint64 expiry
    ) external view returns (bool valid, string memory reason);

    function verifyOrderSignature(
        OrderStruct.Order calldata order,
        bytes calldata signature
    ) external view returns (bool);

    function getOrderHash(OrderStruct.Order calldata order) external view returns (bytes32);
}
```

## 测试策略

### 单元测试

1. **test/unit/OrderStorage.t.sol**：
   - 价格树插入/删除（验证 O(log n) 行为）
   - 订单队列入队/出队（验证 FIFO）
   - 边界情况：空队列、单个订单、多个价格层级

2. **test/unit/OrderValidator.t.sol**：
   - 参数验证（价格对齐、过期时间、数量）
   - EIP712 签名验证
   - 无效签名拒绝

3. **test/unit/MakerTakerFee.t.sol**：
   - Maker vs Taker 的费用计算
   - 验证 0% maker 下单费用、0.05% maker 成交费用、0.25% taker 成交费用

### 集成测试

1. **test/integration/OrderBookV2.t.sol**：
   - 使用新存储的完整订单生命周期
   - 同一价格的多个订单（FIFO 验证）
   - 跨多个价格层级的价格-时间优先级
   - 订单取消和删除

2. **test/integration/FeeIntegration.t.sol**：
   - 端到端费用收取与 maker-taker 区分
   - 验证 taker 支付比 maker 更多
   - FeeVaultManager 中的费用累积

### Gas 基准测试

**test/gas/OrderBookGasBenchmark.t.sol**：
```solidity
function test_GasComparison_InsertPrice() public {
    // 比较旧的基于数组 vs 新的基于树
    // 测试 10、50、100 个价格层级
}

function test_GasComparison_MatchOrder() public {
    // 比较撮合性能
    // 测试各种订单簿深度
}
```

## 预期 Gas 节省

| 操作 | 当前（100 层级） | 优化后 | 节省/变化 | 说明 |
|------|----------------|--------|----------|------|
| 插入价格 | ~50,000 gas | ~8,000 gas | ✅ 84% | 主要优化点 |
| 删除价格 | ~45,000 gas | ~7,500 gas | ✅ 83% | 主要优化点 |
| 查找最优价格 | ~500 gas (O(1)) | ~2,000 gas (O(log n)) | ⚠️ +300% | 可接受的权衡* |
| 订单撮合（整体） | 可变 | 快 20-30% | ✅ 提升 | 由于更快的价格迭代 |

\* **查找最优价格的 Gas 权衡**：
- 虽然单次查找从 ~500 gas 增加到 ~2,000 gas
- 但插入/删除操作的巨大节省（84%）远超这个成本
- 在实际使用中，插入/删除频率 >> 查找频率
- 整体撮合性能仍然提升 20-30%

## 验证计划

实施后：

1. **运行现有测试**：`forge test` - 所有测试应通过
2. **运行 gas 基准测试**：`forge test --match-path test/gas/*` - 验证节省
3. **部署到本地 Anvil**：`make deploy-prediction-local`
4. **测试完整工作流**：
   - 创建事件
   - 在不同价格下单多个订单
   - 验证同一价格的 FIFO 撮合
   - 验证 maker-taker 费用正确应用
   - 取消订单并验证价格层级清理
5. **检查存储布局**：`forge inspect OrderBookManager storage-layout` - 验证无冲突
6. **模糊测试**：为订单撮合边界情况添加模糊测试

## 关键文件摘要

### 创建
- `src/core/OrderStorage.sol` - 三层存储实现
- `src/core/OrderValidator.sol` - 验证和 EIP712
- `src/interfaces/core/IOrderStorage.sol` - 存储接口
- `src/interfaces/core/IOrderValidator.sol` - 验证器接口
- `test/unit/OrderStorage.t.sol` - 存储单元测试
- `test/unit/OrderValidator.t.sol` - 验证器单元测试
- `test/unit/MakerTakerFee.t.sol` - 费用单元测试
- `test/gas/OrderBookGasBenchmark.t.sol` - Gas 基准测试

### 修改
- `src/core/OrderBookManager.sol` - 集成新存储，重构撮合
- `src/core/FeeVaultManager.sol` - 添加 maker-taker 费用计算
- `src/interfaces/core/IFeeVaultManager.sol` - 添加 calculateMakerTakerFee()
- `test/integration/OrderBookV2.t.sol` - 更新集成测试

### 无需更改
- `src/library/OrderStruct.sol` - 已经具备所有需要的结构！
- `src/library/RedBlackTreeLibrary.sol` - 已经完美！
- `src/core/FundingManager.sol` - 无需更改
- `src/core/EventManager.sol` - 无需更改

## 风险与缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| RedBlackTree bug | 高 | 使用经过实战检验的 BokkyPooBah 库（已在仓库中） |
| 存储槽冲突 | 高 | 使用存储间隙模式（所有合约中已存在） |
| 费用计算错误 | 中 | 全面的单元测试、模糊测试 |
| 签名重放攻击 | 高 | 在 EIP712 域中包含 chainId、nonce |
| 迁移复杂性 | 中 | 保留旧存储，添加功能标志以逐步推出 |

## 实施时间表

- **第 1 周**：OrderStorage + IOrderStorage + 单元测试
- **第 2 周**：OrderValidator + IOrderValidator + EIP712 + 单元测试
- **第 3 周**：FeeVaultManager maker-taker 费用 + 单元测试
- **第 4 周**：OrderBookManager 集成 + 重构
- **第 5 周**：集成测试 + gas 基准测试
- **第 6 周**：安全审查 + 部署准备
