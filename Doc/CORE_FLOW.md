# 核心业务流程工作流（新架构）

> 基于直接面向消费者（Direct-to-Consumer）的简化架构

## 架构概览

```
平台管理员（Owner）
├── EventManager（单一实例，管理所有事件）- UUPS 可升级
│   └── 事件创建者白名单（经授权的地址可创建事件）
├── OrderBookManager（单一实例，管理所有订单）- UUPS 可升级
│   ├── OrderStorage（三层存储架构）
│   │   ├── Layer 1: Price Trees (RedBlackTree) - O(log n)
│   │   ├── Layer 2: Order Queues (Linked List) - O(1) FIFO
│   │   └── Layer 3: Global Orders (Mapping) - O(1) lookup
│   └── OrderValidator（参数验证 + EIP712 签名支持）
├── FundingManager（单一实例，管理所有资金）- UUPS 可升级
├── FeeVaultManager（单一实例，费用直接给 owner，Maker-Taker 费用）- UUPS 可升级
└── OracleAdapter（事件结算，Simple/Mock/Third-party）
```

**存储架构：** 所有 Manager 合约使用集成存储模式，带有 `__gap` 数组以支持 UUPS 升级。OrderBookManager 使用独立的 OrderStorage 合约实现三层存储架构。

**升级机制：** 所有 Manager 合约通过 UUPS（ERC1967Proxy + UUPSUpgradeable）模式支持升级，仅 owner 可授权升级。

---

## 流程一：发布事件

### 参与角色

- **平台管理员**：添加/移除事件创建者
- **事件创建者**：被授权创建事件的地址（白名单）
- **EventManager**：事件管理合约（单一实例）
- **OrderBookManager**：订单簿合约（单一实例）
- **FundingManager**：资金管理合约（单一实例）

### 详细步骤

#### 步骤 0：授权事件创建者（一次性设置）

```
平台管理员 → EventManager.addEventCreator(creatorAddress)
├─ 更新白名单：isEventCreator[creatorAddress] = true
└─ 触发事件：EventCreatorAdded(creatorAddress)
```

**代码示例：**

```solidity
// 平台管理员调用
eventManager.addEventCreator(0x123...); // 授权创建者地址
```

---

#### 步骤 1：创建事件

```
事件创建者 → EventManager.createEvent()
├─ 访问控制检查：require(isEventCreator[msg.sender] || msg.sender == owner())
├─ 生成唯一事件ID：eventId = nextEventId++（从 1 开始，0 为保留的 dummy event）
├─ 验证参数：
│   ├─ 结果选项数量：2-32 个
│   ├─ 截止时间 > 当前时间
│   └─ 结算时间 > 截止时间
├─ 存储事件数据：
│   ├─ events[eventId] = Event {
│   │     eventId: eventId,
│   │     title: "事件标题",
│   │     description: "事件描述",
│   │     eventType: "政治" / "体育" / "娱乐" 等,
│   │     deadline: 投注截止时间戳,
│   │     settlementTime: 预期结算时间戳,
│   │     status: Created,
│   │     creator: msg.sender,
│   │     outcomes: ["选项A", "选项B", "选项C"],
│   │     winningOutcomeIndex: 0 (未设置)
│   │   }
│   └─ eventExists[eventId] = true
└─ 触发事件：EventCreated(eventId, title, eventType, outcomes)
```

**代码示例：**

```solidity
// 事件创建者调用
string[] memory outcomes = new string[](3);
outcomes[0] = "特朗普获胜";
outcomes[1] = "哈里斯获胜";
outcomes[2] = "其他候选人获胜";

uint256 eventId = eventManager.createEvent(
    "2024 年美国总统大选",           // title
    "谁将赢得 2024 年美国总统选举？", // description
    "政治",                          // eventType
    block.timestamp + 30 days,       // deadline（30天后截止投注）
    block.timestamp + 60 days,       // settlementTime（60天后结算）
    outcomes                         // 结果选项
);
```

**返回：** `eventId` (uint256) - 新创建的事件ID

---

#### 步骤 2：激活事件（使其可交易）

```
事件创建者 → EventManager.updateEventStatus(eventId, Active)
├─ 访问控制检查：require(isEventCreator[msg.sender] || msg.sender == owner())
├─ 验证事件存在：require(eventExists[eventId])
├─ 验证当前状态：require(status == Created)
├─ 更新状态：events[eventId].status = Active
├─ 添加到活跃列表：activeEventIds.push(eventId)
└─ 触发事件：EventStatusUpdated(eventId, Active)
```

**代码示例：**

```solidity
// 事件创建者调用
eventManager.updateEventStatus(eventId, EventStatus.Active);
```

---

#### 步骤 3：在订单簿中注册事件

```
事件创建者 → OrderBookManager.addEvent(eventId, outcomeCount)
├─ 从 EventManager 获取事件信息（通过引用）
├─ 验证事件状态为 Active
├─ 注册事件：supportedEvents[eventId] = true
├─ 注册结果选项：
│   └─ for i in 0..outcomeCount:
│       supportedOutcomes[eventId][i] = true
└─ 触发事件：EventAdded(eventId, outcomeCount)
```

**代码示例：**

```solidity
// 事件创建者调用
orderBookManager.addEvent(eventId, 3); // 3 个结果选项
```

---

#### 步骤 4：在资金池中注册事件（自动触发）

```
OrderBookManager.addEvent() 内部调用 → FundingManager.registerEvent(eventId, outcomes)
├─ 注册结果选项：
│   └─ for i in 0..outcomes.length:
│       eventOutcomes[eventId][i] = true
├─ 初始化奖金池：eventPrizePool[eventId] = 0 (USD)
└─ 触发事件：EventRegistered(eventId, outcomes.length)
```

**自动执行，无需手动调用**

---

### 流程图总结

```
┌─────────────────┐
│ 步骤 0 (一次性) │  平台管理员授权事件创建者
│ addEventCreator │
└────────┬────────┘
         │
┌────────▼────────┐
│    步骤 1       │  事件创建者创建事件
│  createEvent    │  → 状态: Created
└────────┬────────┘
         │
┌────────▼────────┐
│    步骤 2       │  事件创建者激活事件
│ updateEventStatus│ → 状态: Active
└────────┬────────┘
         │
┌────────▼────────┐
│    步骤 3       │  在订单簿中注册事件
│   addEvent      │  → OrderBookManager 支持该事件
└────────┬────────┘
         │
┌────────▼────────┐
│  步骤 4 (自动)  │  在资金池中注册事件
│ registerEvent   │  → FundingManager 支持该事件
└─────────────────┘
         │
         ▼
    事件已上线，用户可以开始交易
```

---

### 状态说明

**事件状态机：**

```
Created → Active → Settled / Cancelled
```

- **Created**：事件已创建，但不可交易
- **Active**：事件已激活，用户可以下单交易
- **Settled**：事件已结算，用户可提取奖金
- **Cancelled**：事件已取消，退还资金

---

## 流程二：下单 → 结算

### 参与角色

- **用户（交易者）**：存款、下单、提款
- **FundingManager**：资金托管与 Long Token 管理（统一 USD 余额）
- **OrderBookManager**：订单撮合引擎
- **FeeVaultManager**：费用收取（统一 USD 费用）
- **EventManager**：事件状态管理
- **OracleAdapter**：预言机结果提交（Simple/Mock/Third-party）
- **平台管理员**：提取平台费用

### 详细步骤

---

### 阶段 A：用户准备（存款 + 铸造）

#### 步骤 A1：用户存入资金

```
用户 → FundingManager.depositErc20(tokenAddress, amount)
├─ 前置条件：用户已授权 FundingManager 转账 ERC20 代币
│   └─ IERC20(token).approve(fundingManagerAddress, amount)
├─ 验证最小存款额：
│   ├─ 转换为 USD：usdAmount = normalizeToUsd(token, amount)
│   └─ require(usdAmount >= MIN_DEPOSIT_USD)  // 10 USD 最小存款
├─ 转账代币：token.transferFrom(user, address(this), amount)
├─ 更新余额：
│   ├─ userUsdBalances[user] += usdAmount
│   └─ tokenLiquidity[token] += amount
└─ 触发事件：Deposited(user, token, amount, usdAmount)
```

**代码示例：**

```solidity
// 用户调用（假设使用 USDT）
address usdt = 0xUSDT...;
IERC20(usdt).approve(address(fundingManager), 1000 ether);
fundingManager.depositErc20(usdt, 1000 ether); // 存入 1000 USDT
```

**用户余额：** `userUsdBalances[user] = 1000 USD` (以 1e18 精度存储)

**余额转换：** 所有 ERC20 代币通过 `normalizeToUsd(token, amount)` 转换为统一的 USD 余额。

**最小存款限制：**
- 所有代币需满足最小存款额：10 USD 等值
- 示例：USDT 需至少存入 10 USDT，USDC 需至少存入 10 USDC
- 前端应在用户存款前检查并显示最小存款要求

---

#### 步骤 A2：铸造完整集合（可选，提供流动性）

```
用户 → FundingManager.mintCompleteSet(eventId, usdAmount)
├─ 验证事件存在且未结算
├─ 验证用户有足够余额：require(userUsdBalances[user] >= usdAmount)
├─ 扣除用户余额：userUsdBalances[user] -= usdAmount
├─ 为每个结果选项铸造 Long Token：
│   └─ for i in 0..outcomeCount:
│       longPositions[user][eventId][i] += usdAmount
├─ 增加奖金池：eventPrizePool[eventId] += usdAmount
└─ 触发事件：CompleteSetMinted(user, eventId, usdAmount)
```

**代码示例：**

```solidity
// 用户调用（用 100 USD 铸造完整集合）
fundingManager.mintCompleteSet(eventId, 100 ether);
```

**效果：**

- 用户余额：`userUsdBalances[user] = 900 USD` (扣除 100)
- 用户获得 Long Token（虚拟代币，无 ERC20 部署）：
    - `longPositions[user][eventId][0] = 100 USD` (选项 A)
    - `longPositions[user][eventId][1] = 100 USD` (选项 B)
    - `longPositions[user][eventId][2] = 100 USD` (选项 C)
- 奖金池：`eventPrizePool[eventId] = 100 USD`

---

### 阶段 B：下单与撮合

#### 步骤 B1：用户下买单

```
用户 → OrderBookManager.placeOrder(eventId, outcomeIndex, Buy, price, amount)
├─ 验证事件状态为 Active
├─ 验证结果选项存在：supportedOutcomes[eventId][outcomeIndex]
├─ 【OrderValidator 验证】
│   ├─ 使用 OrderValidator.validateOrderParams() 统一验证
│   ├─ 验证 maker 地址非零
│   ├─ 验证 eventId 和 outcomeIndex（通过 _getEventOutcomeCount()）
│   ├─ 验证价格范围：1 <= price <= 10000 (基点)
│   ├─ 验证价格对齐：price % TICK_SIZE == 0 (TICK_SIZE = 10)
│   ├─ 验证数量：amount > 0
│   └─ 验证过期时间（如果非零）
│
├─ 【子步骤 1】锁定资金
│   ├─ 计算所需 USD：requiredUsd = (amount × price) / 10000
│   ├─ FundingManager.lockForOrder(user, requiredUsd, orderId)
│   │   ├─ 验证余额：require(userUsdBalances[user] >= requiredUsd)
│   │   ├─ 扣除可用余额：userUsdBalances[user] -= requiredUsd
│   │   └─ 增加锁定余额：orderLockedUsd[user][orderId] = requiredUsd
│   └─ 触发事件：FundsLocked(user, orderId, requiredUsd)
│
├─ 【子步骤 2】收取下单费用（Maker-Taker 费用）
│   ├─ Maker 下单费用：0%（免费挂单，激励流动性提供）
│   ├─ Taker 下单费用：0%（免费）
│   └─ 注：费用在成交时收取（Maker: 0.05%, Taker: 0.25%）
│
├─ 【子步骤 3】订单撮合（自动，使用三层存储架构）
│   ├─ 查找匹配卖单：从最低卖价开始遍历
│   │   ├─ Layer 1: 使用 OrderStorage.getBestPrice() 获取最优卖价 - O(log n)
│   │   └─ 遍历价格：lowestSellPrice → price (买单价格)
│   │
│   ├─ 对每个匹配的卖单执行成交：
│   │   ├─ Layer 2: 使用 OrderStorage.peekOrder() 获取队列头部 - O(1)
│   │   ├─ Layer 3: 通过 orderKeyToId[sellKey] 获取 orderId - O(1)
│   │   ├─ 计算成交量：matchAmount = min(buyOrder.remaining, sellOrder.remaining)
│   │   │
│   │   ├─ 计算成交价格（Taker 接受 Maker 的价格）：
│   │   │   ├─ 买家是 Taker：matchPrice = sellOrder.price（买家接受卖家挂单价）
│   │   │   └─ 卖家是 Taker：matchPrice = buyOrder.price（卖家接受买家出价）
│   │   │
│   │   ├─ 更新订单状态：
│   │   │   ├─ buyOrder.filledAmount += matchAmount
│   │   │   ├─ sellOrder.filledAmount += matchAmount
│   │   │   ├─ buyOrder.remainingAmount -= matchAmount
│   │   │   └─ sellOrder.remainingAmount -= matchAmount
│   │   │
│   │   ├─ 更新持仓：
│   │   │   ├─ positions[eventId][outcomeIndex][buyer] += matchAmount
│   │   │   └─ positions[eventId][outcomeIndex][seller] -= matchAmount
│   │   │
│   │   ├─ 结算资金：FundingManager.settleMatchedOrder()
│   │   │   ├─ 计算 USD 金额：usdAmount = (matchAmount × matchPrice) / 10000
│   │   │   ├─ 买方：
│   │   │   │   ├─ 解锁 USD：orderLockedUsd[buyer][buyOrderId] -= usdAmount
│   │   │   │   └─ 增加 Long Token：longPositions[buyer][eventId][outcome] += matchAmount
│   │   │   ├─ 卖方：
│   │   │   │   ├─ 解锁 Long Token：orderLockedLong[seller][sellOrderId] -= matchAmount
│   │   │   │   └─ 增加 USD：userUsdBalances[seller] += usdAmount
│   │   │   └─ 触发事件：OrderSettled(buyOrderId, sellOrderId, matchAmount, usdAmount)
│   │   │
│   │   ├─ 收取 Maker-Taker 成交费用：
│   │   │   ├─ Taker 费用：0.25%（25 基点）
│   │   │   │   └─ takerFee = (matchUsd * 25 + 9999) / 10000  // 向上取整
│   │   │   ├─ Maker 费用：0.05%（5 基点）
│   │   │   │   └─ makerFee = (matchUsd * 5 + 9999) / 10000   // 向上取整
│   │   │   ├─ 确定角色：
│   │   │   │   ├─ taker = buyerIsTaker ? buyOrder.maker : sellOrder.maker
│   │   │   │   └─ maker = buyerIsTaker ? sellOrder.maker : buyOrder.maker
│   │   │   ├─ FeeVaultManager.collectFee(takerToken, taker, takerFee, eventId, "taker_execution")
│   │   │   └─ FeeVaultManager.collectFee(makerToken, maker, makerFee, eventId, "maker_execution")
│   │   │
│   │   ├─ 🔧 Issue #11 修复：买单完全成交时返还剩余 USD
│   │   │   └─ if (buyOrder.remainingAmount == 0):
│   │   │       └─ FundingManager.unlockForOrder(buyer, buyOrderId, true, eventId, outcomeIndex)
│   │   │           └─ 返还剩余 USD：surplus = orderLockedUsd - actualUsed
│   │   │
│   │   └─ 触发事件：OrderMatched(buyOrderId, sellOrderId, matchAmount, matchPrice)
│   │
│   ├─ 获取下一个价格层级：
│   │   └─ Layer 1: OrderStorage.getNextPrice() - O(log n)
│   │
│   └─ 循环直到：buyOrder.remaining == 0 或无更多匹配卖单
│
├─ 【子步骤 4】入簿（如有剩余，使用三层存储）
│   ├─ if (buyOrder.remainingAmount > 0):
│   │   ├─ 订单状态 = Partial (部分成交) 或 Pending (未成交)
│   │   ├─ 生成 OrderKey：key = OrderStruct.hash(order)
│   │   ├─ Layer 3: OrderStorage.storeOrder(key, dbOrder) - O(1)
│   │   ├─ Layer 1: OrderStorage.insertPrice(eventId, outcomeIndex, isBuy, price) - O(log n)
│   │   ├─ Layer 2: OrderStorage.enqueueOrder(eventId, outcomeIndex, isBuy, price, key) - O(1)
│   │   └─ 订单按 FIFO 顺序排列（价格-时间优先）
│   └─ else:
│       ├─ 订单状态 = Filled (完全成交)
│       └─ 从订单簿移除
│
└─ 触发事件：OrderPlaced(orderId, user, eventId, outcome, Buy, price, amount)
```

**代码示例：**

```solidity
// 用户下买单（买入选项 0，价格 6000 = 0.6 USD，数量 100）
orderBookManager.placeOrder(
    eventId,        // 事件ID
    0,              // outcomeIndex（选项 A）
    OrderSide.Buy,  // 买单
    6000,           // price（6000 基点 = 0.6 USD per token）
    100 ether       // amount（买入 100 个）
);
```

**资金变化（统一 USD 余额，Maker-Taker 费用）：**

- 锁定金额：`(100 × 6000) / 10000 = 60 USD`
- 下单费用（Placement）：`0%`（Maker 和 Taker 均免费）
- 如果立即成交（Taker）：
  - 成交费用：`matchUsd × 0.25% = 0.25% Taker 费用`
  - 对手方（Maker）费用：`matchUsd × 0.05% = 0.05% Maker 费用`
- 如果挂单（Maker）：
  - 下单费用：`0%`（免费）
  - 成交时费用：`matchUsd × 0.05% = 0.05% Maker 费用`
- **Issue #11 修复**：如果以更优价格成交（如 5500），剩余 USD 自动返还
  - 示例：订单价 6000，成交价 5500 → 返还 `(100 × 500) / 10000 = 5 USD`

---

#### 步骤 B2：用户下卖单（类似流程）

```
用户 → OrderBookManager.placeOrder(eventId, outcomeIndex, Sell, price, amount)
├─ 【子步骤 1】锁定 Long Token
│   └─ FundingManager.lockForOrder(user, Long Token, amount, orderId)
│       ├─ 验证持仓：require(longPositions[user][eventId][outcome] >= amount)
│       ├─ 扣除持仓：longPositions[user][eventId][outcome] -= amount
│       └─ 锁定：orderLockedLong[user][orderId] = amount
│
├─ 【子步骤 2】收取下单费用（Placement Fee，0.1%）
├─ 【子步骤 3】订单撮合：从最高买价开始匹配
└─ 【子步骤 4】入簿（如有剩余）
```

**代码示例：**

```solidity
// 用户下卖单（卖出选项 0，价格 6500 = 0.65 USD，数量 50）
orderBookManager.placeOrder(
    eventId,
    0,
    OrderSide.Sell,
    6500,           // 卖价 0.65 USD
    50 ether        // 卖出 50 个
);
```

---

#### 步骤 B3：取消订单（可选）

```
用户 → OrderBookManager.cancelOrder(orderId)
├─ 验证订单所有者：require(orders[orderId].user == msg.sender)
├─ 验证订单状态：require(status == Pending || status == Partial)
├─ 解锁资金：FundingManager.unlockForOrder(user, orderId)
│   ├─ 买单：
│   │   ├─ 释放锁定 USD：lockedAmount = orderLockedUsd[user][orderId]
│   │   ├─ 返还余额：userUsdBalances[user] += lockedAmount
│   │   └─ 清空锁定：orderLockedUsd[user][orderId] = 0
│   └─ 卖单：
│       ├─ 释放锁定 Long Token：lockedAmount = orderLockedLong[user][orderId]
│       ├─ 返还持仓：longPositions[user][eventId][outcome] += lockedAmount
│       └─ 清空锁定：orderLockedLong[user][orderId] = 0
├─ 更新订单状态：orders[orderId].status = Cancelled
├─ 从订单簿移除
└─ 触发事件：OrderCancelled(orderId)
```

**代码示例：**

```solidity
// 用户取消订单
orderBookManager.cancelOrder(orderId);
```

---

### 阶段 C：事件结算（两步流程）

#### 步骤 C1：请求预言机

```
事件创建者/管理员 → EventManager.requestOracleResult(eventId)
├─ 验证事件状态：require(status == Active)
├─ 验证已过截止时间：require(block.timestamp >= deadline)
├─ 路由到适配器：targetOracleAdapter = _getOracleAdapterForEventType(evt.eventType)
│  ├─ 优先使用：eventTypeToOracleAdapter[eventType]（类型特定预言机）
│  └─ 回退到：defaultOracleAdapter（默认预言机）
├─ 记录使用的适配器：evt.usedOracleAdapter = targetOracleAdapter（不可变）
├─ 调用适配器：IOracle(targetOracleAdapter).requestEventResult(eventId, description)
├─ 记录 requestId：eventOracleRequests[eventId] = requestId
├─ 触发事件：OracleAdapterUsed(eventId, targetOracleAdapter, eventType)
└─ 由 OracleAdapter 触发事件：ResultRequested(...)
```

**代码示例：**

```solidity
// 事件创建者或管理员调用
eventManager.requestOracleResult(eventId);

// 系统会根据事件类型自动路由到对应的预言机适配器
// 例如：体育事件 → Chainlink，加密货币事件 → UMA，其他 → 默认适配器
```

---

#### 步骤 C2：预言机提交结果

```
预言机/Oracle 服务 → OracleAdapter.submitResult(...) 或 oracle-specific 回调
├─ 验证预言机授权（适配器内）
├─ 适配器将结果转换为统一回调
└─ 调用 EventManager.fulfillResult(eventId, winningOutcomeIndex, proof)
```

**代码示例：**

```solidity
// 预言机调用（示例：SimpleOracleAdapter.submitResult）
oracleAdapter.submitResult(
    requestId,
    eventId,
    1,          // 获胜选项索引（选项 B）
    ""          // proof 可为空
);
```

---

#### 步骤 C3：标记事件已结算

```
EventManager.fulfillResult(eventId, winningOutcomeIndex, proof)
├─ proof 可为空（第三方预言机通常不提供 Merkle 证明）
├─ 更新事件状态：
│   ├─ events[eventId].status = Settled
│   └─ events[eventId].winningOutcomeIndex = winningOutcomeIndex
├─ 从活跃列表移除
├─ 调用 OrderBookManager.settleEvent(eventId, winningOutcomeIndex)
│   ├─ 标记已结算：eventSettled[eventId] = true
│   ├─ 存储结果：eventResults[eventId] = winningOutcomeIndex
│   │
│   ├─ 【子步骤 1】取消所有待成交订单
│   │   └─ for each order where status == Pending or Partial:
│   │       ├─ FundingManager.unlockForOrder(user, orderId)  // 释放锁定资金
│   │       └─ orders[orderId].status = Cancelled
│   │
│   └─ 【子步骤 2】标记结算完成，等待用户提取
│       └─ FundingManager.markEventSettled(eventId, winningOutcomeIndex)
│           ├─ 标记已结算：eventSettled[eventId] = true
│           ├─ 存储获胜选项：eventWinningOutcome[eventId] = winningOutcomeIndex
│           └─ 触发事件：EventMarkedSettled(eventId, winningOutcomeIndex)
│
└─ 触发事件：EventSettled(eventId, winningOutcomeIndex)
```

**关键变化：** 不再使用无界循环分配奖金，改为标记结算状态，等待用户主动提取。

---

#### 步骤 C4：用户提取奖金（Pull Pattern）

```
用户 → FundingManager.redeemWinnings(eventId)
├─ 验证事件已结算：require(eventSettled[eventId])
├─ 获取获胜选项：winningOutcome = eventWinningOutcome[eventId]
├─ 获取用户持仓：winningPosition = longPositions[user][eventId][winningOutcome]
├─ 验证有持仓：require(winningPosition > 0)
├─ 验证未提取：require(!hasRedeemed[eventId][user])
├─ 兑换奖金（1:1 兑换）：
│   ├─ winnings = winningPosition  // 1 Winning Long Token = 1 USD
│   ├─ 清空持仓：longPositions[user][eventId][winningOutcome] = 0
│   ├─ 增加可用余额：userUsdBalances[user] += winnings
│   ├─ 标记已提取：hasRedeemed[eventId][user] = true
│   └─ 触发事件：WinningsRedeemed(user, eventId, winnings)
└─ 返回：winnings (uint256)
```

**代码示例：**

```solidity
// 用户提取奖金
uint256 winnings = fundingManager.redeemWinnings(eventId);
```

**奖金计算：** 1 Winning Long Token = 1 USD（直接转换，无需比例计算）

**示例：**

- 用户持有 100 个获胜选项 Long Token
- 兑换：100 Winning Long Token = 100 USD
- 用户 USD 余额增加 100 USD

---

#### 步骤 C5：查询提取状态

```
任何人 → FundingManager.canRedeemWinnings(eventId, user)
├─ 检查事件已结算
├─ 检查用户有获胜持仓
├─ 检查未提取过
└─ 返回：(canRedeem: bool, winningPosition: uint256)
```

**代码示例：**

```solidity
// 查询用户是否可以提取奖金
(bool canRedeem, uint256 winningPosition) = fundingManager.canRedeemWinnings(eventId, user);
if (canRedeem) {
    // 可以提取 winningPosition 数量的奖金
}
```

---

### 阶段 D：提取资金

#### 步骤 D1：用户提取 USD 余额

```
用户 → FundingManager.withdrawDirect(tokenAddress, usdAmount)
├─ 转换为 Token：tokenAmount = denormalizeFromUsd(token, usdAmount)
├─ 验证余额：require(userUsdBalances[user] >= usdAmount)
├─ 扣除余额：userUsdBalances[user] -= usdAmount
├─ 减少流动性：tokenLiquidity[token] -= tokenAmount
├─ 转账：token.transfer(user, tokenAmount)
└─ 触发事件：Withdrawn(user, token, tokenAmount, usdAmount)
```

**代码示例：**

```solidity
// 用户提取 200 USD (假设 1 USDT = 1 USD)
fundingManager.withdrawDirect(usdt, 200 ether);
```

**余额转换：** 通过 `denormalizeFromUsd(token, usdAmount)` 将 USD 余额转换回 ERC20 代币数量。
**按 Token 数量提现：** 使用 `withdrawTokenAmount(tokenAddress, tokenAmount)`。

---

#### 步骤 D2：平台管理员提取费用

```
平台管理员 → FeeVaultManager.withdrawFee(tokenAddress, tokenAmount)
├─ 访问控制：require(msg.sender == owner())
├─ 转换为 USD：usdAmount = normalizeToUsd(token, tokenAmount)
├─ 验证费用余额：require(protocolUsdFeeBalance >= usdAmount)
├─ 扣除余额：protocolUsdFeeBalance -= usdAmount
├─ 更新统计：totalFeesWithdrawn += usdAmount
├─ 调用 FundingManager.withdrawLiquidity(token, tokenAmount)
│   ├─ 验证流动性：require(tokenLiquidity[token] >= tokenAmount)
│   ├─ 减少流动性：tokenLiquidity[token] -= tokenAmount
│   └─ 转账给 FeeVaultManager：token.transfer(feeVault, tokenAmount)
├─ 转账给 owner：token.transfer(owner(), tokenAmount)
└─ 触发事件：FeeWithdrawn(token, owner(), tokenAmount, usdAmount)
```

**代码示例：**

```solidity
// 平台管理员提取 50 USDT 费用
feeVaultManager.withdrawFee(usdt, 50 ether);
```

**费用存储位置：** 费用以统一 USD 余额记录在 `FeeVaultManager.protocolUsdFeeBalance`，但实际代币流动性存储在 `FundingManager.tokenLiquidity[token]`。

---

## 完整流程图

```
┌──────────────────────────────────────────────────────────────┐
│                     阶段 A：用户准备                          │
└──────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
    ┌────▼─────┐         ┌────▼─────┐       ┌─────▼──────┐
    │  A1: 存款 │         │ A2: 铸造  │       │  (可选)     │
    │depositErc20│        │完整集合    │       │            │
    └────┬─────┘         └─────┬────┘       └────────────┘
         │                     │
         └──────────┬──────────┘
                    │
┌───────────────────▼──────────────────────────────────────────┐
│                    阶段 B：下单与撮合                          │
└──────────────────────────────────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
    ┌────▼─────┐          ┌────▼─────┐
    │ B1: 买单  │          │ B2: 卖单  │
    │placeOrder │          │placeOrder │
    │(Buy)      │          │(Sell)     │
    └────┬─────┘          └─────┬────┘
         │                      │
         │  ┌───────────────────┘
         │  │  ┌─────── 1. 锁定 USD/Long Token
         │  │  │
         │  │  ├─────── 2. 收取下单费用 (0.1% Placement Fee)
         │  │  │
         │  │  ├─────── 3. 自动撮合
         │  │  │         ├─ 更新持仓
         │  │  │         ├─ 结算资金
         │  │  │         └─ 收取成交费用 (0.2% = 0.1% × 2, Execution Fee)
         │  │  │
         │  │  └─────── 4. 入簿（如有剩余）
         │  │
         │  │  【可选】
         └──┼──▶ B3: 取消订单 (cancelOrder)
            │    └─ 解锁 USD/Long Token
            │
┌───────────▼──────────────────────────────────────────────────┐
│                    阶段 C：事件结算（两步流程）                │
└──────────────────────────────────────────────────────────────┘
            │
       ┌────▼─────┐
       │C1: 请求   │
       │预言机      │
       │requestOracleResult│
       └────┬─────┘
            │
       ┌────▼─────┐
       │C2: 预言机 │
       │提交结果    │
       │submitResult│
       └────┬─────┘
            │
       ┌────▼─────┐
       │C3: 标记   │
       │结算完成    │
       │settleEvent│
       └────┬─────┘
            │
            ├─────── 取消待成交订单
            │
            └─────── 标记结算状态（不分配奖金）
            │
       ┌────▼─────┐
       │C4: 用户   │
       │提取奖金    │
       │redeemWinnings│ (Pull Pattern)
       └────┬─────┘
            │
            └─────── 1 Winning Long Token = 1 USD
            │
┌───────────▼──────────────────────────────────────────────────┐
│                    阶段 D：提取资金                            │
└──────────────────────────────────────────────────────────────┘
            │
       ┌────┴─────┬─────────────┐
       │          │             │
  ┌────▼─────┐   │      ┌──────▼──────┐
  │D1: 用户   │   │      │D2: 平台管理员│
  │提取 USD   │   │      │提取费用      │
  │withdrawDirect│ │      │withdrawFee  │
  └──────────┘   │      └─────────────┘
                 │
            ┌────▼─────┐
            │  完成     │
            └──────────┘
```

---

## 关键数据结构

### EventManager

```solidity
events[eventId] = Event {
    eventId: uint256,
    title: string,
    description: string,
    eventType: string,           // 事件类型（如：政治、体育、娱乐等）
    deadline: uint256,           // 投注截止时间
    settlementTime: uint256,     // 预期结算时间
    status: EventStatus,         // Created/Active/Settled/Cancelled
    creator: address,            // 事件创建者
    outcomes: string[],          // 结果选项
    winningOutcomeIndex: uint8   // 获胜选项（结算后）
}
```

### OrderBookManager

```solidity
orders[orderId] = Order {
    orderId: uint256,
    user: address,
    eventId: uint256,
    outcomeIndex: uint8,
    side: OrderSide,             // Buy/Sell
    price: uint256,              // 1-10000 基点
    amount: uint256,
    filledAmount: uint256,
    remainingAmount: uint256,
    status: OrderStatus          // Pending/Partial/Filled/Cancelled
}

positions[eventId][outcomeIndex][user] = amount  // 持仓跟踪
```

### FundingManager（统一 USD 余额模型）

```solidity
userUsdBalances[user] = amount                    // 统一 USD 余额 (1e18 精度)
longPositions[user][eventId][outcome] = amount    // Long Token 持仓 (USD)
orderLockedUsd[user][orderId] = amount            // 买单锁定 (USD)
orderLockedLong[user][orderId] = amount           // 卖单锁定 (USD)
eventPrizePool[eventId] = amount                  // 奖金池 (USD)
tokenLiquidity[token] = amount                    // ERC20 代币流动性

eventSettled[eventId] = bool                      // 事件是否已结算
eventWinningOutcome[eventId] = uint8              // 获胜选项
hasRedeemed[eventId][user] = bool                 // 用户是否已提取

// 转换函数
normalizeToUsd(token, amount) → usdAmount         // ERC20 → USD
denormalizeFromUsd(token, usdAmount) → amount     // USD → ERC20

// 余额查询函数（前端集成）
getUserUsdBalance(user) → usdAmount               // 查询用户平台内 USD 余额
getSupportedTokens() → address[]                  // 获取协议支持的代币地址列表
getTokenPrice(token) → priceInUsd                 // 获取代币 USD 价格（用于显示和转换）
getMinDepositUsd() → uint256                      // 获取最小存款额（10 USD）

// 支持的代币配置
supportedTokens: address[]                        // 协议支持的 ERC20 代币地址数组
tokenPrices[token] = priceInUsd                   // 代币价格（1e18 精度）
MIN_DEPOSIT_USD: uint256 = 10e18                  // 最小存款额：10 USD
```

**前端余额显示需求：**

前端需要显示用户在所有支持代币中的余额（跨链），以便用户选择存款代币：

```javascript
// 前端伪代码示例（支持多链）
async function displayUserBalances(userAddress, chainId) {
    // 1. 获取用户平台内 USD 余额
    const usdBalance = await fundingManager.getUserUsdBalance(userAddress);
    console.log(`平台内余额: ${usdBalance} USD`);

    // 2. 获取协议支持的代币列表（当前链）
    const supportedTokens = await fundingManager.getSupportedTokens();

    // 3. 获取最小存款额
    const minDepositUsd = await fundingManager.getMinDepositUsd(); // 10 USD

    // 4. 为每个代币查询用户钱包余额（直接调用 ERC20 合约）
    for (const tokenAddress of supportedTokens) {
        // 直接调用代币合约查询余额
        const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
        const tokenBalance = await tokenContract.balanceOf(userAddress);
        const tokenSymbol = await tokenContract.symbol();
        const tokenDecimals = await tokenContract.decimals();

        // 获取代币价格
        const tokenPrice = await fundingManager.getTokenPrice(tokenAddress);

        // 计算 USD 等值
        const tokenValueInUsd = (tokenBalance * tokenPrice) / (10n ** BigInt(18 + tokenDecimals));

        // 计算最小存款要求
        const minTokenAmount = (minDepositUsd * (10n ** BigInt(tokenDecimals))) / tokenPrice;

        // 显示在 UI：
        // - 代币符号（USDT, USDC 等）
        // - 用户钱包余额
        // - USD 等值
        // - 最小存款要求（例如：10 USDT）
        // - 是否满足最小存款（禁用/启用存款按钮）
        // - 链 ID（用于多链支持）

        console.log({
            chain: chainId,
            token: tokenSymbol,
            balance: ethers.formatUnits(tokenBalance, tokenDecimals),
            valueInUsd: ethers.formatEther(tokenValueInUsd),
            minDeposit: ethers.formatUnits(minTokenAmount, tokenDecimals),
            canDeposit: tokenValueInUsd >= minDepositUsd
        });
    }
}

// 多链支持示例
const SUPPORTED_CHAINS = {
    1: 'Ethereum Mainnet',
    8453: 'Base',
    42161: 'Arbitrum One',
    10: 'Optimism'
};

// 用户可以选择链并查看该链上的代币余额
for (const [chainId, chainName] of Object.entries(SUPPORTED_CHAINS)) {
    await displayUserBalances(userAddress, chainId);
}
```

**关键设计原则：**
- ✅ 合约仅提供 `supportedTokens` 列表，不存储用户钱包余额
- ✅ 前端直接调用 ERC20 `balanceOf(user)` 查询钱包余额
- ✅ 支持多链部署，每条链有独立的 `supportedTokens` 配置
- ✅ 前端负责聚合显示多链余额

### FeeVaultManager（统一 USD 费用模型）

```solidity
protocolUsdFeeBalance = amount                    // 协议费用余额 (USD, 1e18 精度)
totalFeesCollected = amount                       // 累计费用 (USD)
totalFeesWithdrawn = amount                       // 累计提取 (USD)
eventFees[eventId] = amount                       // 事件费用 (USD)
userPaidFees[user] = amount                       // 用户支付费用 (USD)
```

---

## 费用说明

### 费用类型与费率（Maker-Taker 模型）

**Maker（流动性提供者）**：挂单在订单簿中的订单
- 下单费用（Placement Fee）：0%（免费挂单，激励流动性提供）
- 成交费用（Execution Fee）：0.05%（5 基点）

**Taker（流动性消耗者）**：立即成交的订单
- 下单费用（Placement Fee）：0%（免费）
- 成交费用（Execution Fee）：0.25%（25 基点）

**总最大费用：** 0.3%（单边，Maker: 0.05%, Taker: 0.25%）

**费用计算精度**：使用向上取整（ceiling division）避免费用不足
```solidity
// FeeVaultManager.sol
fee = (amount * rate + FEE_PRECISION - 1) / FEE_PRECISION;
```

### 费用存储与流转

```
用户交易费用 (USD)
    ↓
FeeVaultManager.protocolUsdFeeBalance (累积, USD 精度)
    ↓
FundingManager.tokenLiquidity[token] (实际代币流动性)
    ↓ (管理员手动提取)
平台钱包 (任意支持的 ERC20 代币)
```

**费用存储不变量：**

```
tokenLiquidity[token] = sum(userUsdBalances) + protocolUsdFeeBalance + sum(eventPrizePools)
```

所有 USD 余额通过 `normalizeToUsd()` 和 `denormalizeFromUsd()` 与实际代币流动性保持同步。

---

## 升级机制（UUPS）

### 可升级合约

所有 Manager 合约使用 UUPS（Universal Upgradeable Proxy Standard）模式：

- **EventManager** - ERC1967Proxy + UUPSUpgradeable
- **OrderBookManager** - ERC1967Proxy + UUPSUpgradeable
- **FundingManager** - ERC1967Proxy + UUPSUpgradeable
- **FeeVaultManager** - ERC1967Proxy + UUPSUpgradeable

### 升级授权

- 仅合约 owner 可授权升级
- 每个 Manager 实现 `_authorizeUpgrade()` 访问控制
- Owner 调用 `upgradeToAndCall()` 直接在 proxy 上升级

### 存储安全

- 所有合约包含存储间隙（`uint256[N] __gap`）
- 预留存储槽位以支持未来状态变量扩展
- 保证存储布局兼容性

### 升级命令

```bash
# 部署新系统（带 UUPS 代理）
make deploy-prediction-local

# 升级实现（需设置环境变量，must be owner）
export EVENT_MANAGER_PROXY=0x...
export ORDER_BOOK_MANAGER_PROXY=0x...
export FUNDING_MANAGER_PROXY=0x...
export FEE_VAULT_MANAGER_PROXY=0x...
forge script script/UpgradeManagers.s.sol --broadcast
```

**UUPS 优势：**
- Gas 效率：节省 ~2100 gas/调用（vs Transparent Proxy）
- 无需外部 ProxyAdmin 合约
- 升级逻辑在实现合约中，减少代理复杂度

---

## 总结

### 新架构优势

✅ **简化部署**：无需工厂、部署器、管理器，直接部署 4 个 Manager（带 UUPS 代理）
✅ **统一余额**：所有代币归一为 USD 余额，简化计算和费用管理
✅ **降低复杂度**：删除 ~2200 行代码，减少 32% 代码量
✅ **灵活权限**：白名单事件创建者，平衡质量与灵活性
✅ **直接费用**：费用直接给平台 owner，无需多层转移
✅ **Pull Pattern**：用户主动提取奖金，避免无界循环
✅ **可升级性**：UUPS 模式支持合约升级，保持存储兼容

### 关键变化

- ❌ **移除**：PodFactory, PodDeployer, 4 个 Managers, AdminFeeVault
- ✅ **保留**：EventManager, OrderBookManager, FundingManager, FeeVaultManager（单实例，带 UUPS）
- 🆕 **新增**：
  - 事件创建者白名单机制
  - 统一 USD 余额系统（`normalizeToUsd` / `denormalizeFromUsd`）
  - **OrderStorage 三层存储架构**（Price Trees + Order Queues + Global Orders）
  - **OrderValidator**（参数验证 + EIP712 签名支持）
  - **Maker-Taker 费用差异化**（Maker: 0.05%, Taker: 0.25%）
  - 两步结算流程（`markEventSettled` + `redeemWinnings`）
  - UUPS 升级机制
- 📉 **简化**：
  - 费用直接提取，无自动转移逻辑
  - 1:1 奖金兑换（1 Winning Long Token = 1 USD）
- ⚡ **性能优化**：
  - O(log n) 价格层级操作（84% gas 节省）
  - O(1) FIFO 订单队列
  - 价格-时间优先原则

### 核心公式

**奖金兑换：**
```
1 Winning Long Token = 1 USD (直接兑换)
```

**费用计算（Maker-Taker 模型）：**
```
Maker 下单费用 = 0% (免费)
Maker 成交费用 = matchUsd × 0.05% (5 基点)
Taker 下单费用 = 0% (免费)
Taker 成交费用 = matchUsd × 0.25% (25 基点)
总最大费用 = 0.3% (单边)
```

**余额转换：**
```
usdAmount = normalizeToUsd(token, tokenAmount)
tokenAmount = denormalizeFromUsd(token, usdAmount)
```
