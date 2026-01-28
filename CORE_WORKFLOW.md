# 核心业务流程工作流（新架构）

> 基于直接面向消费者（Direct-to-Consumer）的简化架构

## 架构概览

```
平台管理员（Owner）
├── EventPod（单一实例，管理所有事件）
│   └── 事件创建者白名单（经授权的地址可创建事件）
├── OrderBookPod（单一实例，管理所有订单）
├── FundingPod（单一实例，管理所有资金）
├── FeeVaultPod（单一实例，费用直接给 owner）
└── OracleAdapter（事件结算）
```

---

## 流程一：发布事件

### 参与角色
- **平台管理员**：添加/移除事件创建者
- **事件创建者**：被授权创建事件的地址（白名单）
- **EventPod**：事件管理合约（单一实例）
- **OrderBookPod**：订单簿合约（单一实例）
- **FundingPod**：资金管理合约（单一实例）

### 详细步骤

#### 步骤 0：授权事件创建者（一次性设置）
```
平台管理员 → EventPod.addEventCreator(creatorAddress)
├─ 更新白名单：isEventCreator[creatorAddress] = true
└─ 触发事件：EventCreatorAdded(creatorAddress)
```

**代码示例：**
```solidity
// 平台管理员调用
eventPod.addEventCreator(0x123...); // 授权创建者地址
```

---

#### 步骤 1：创建事件
```
事件创建者 → EventPod.createEvent()
├─ 访问控制检查：require(isEventCreator[msg.sender] || msg.sender == owner())
├─ 生成唯一事件ID：eventId = nextEventId++
├─ 验证参数：
│   ├─ 结果选项数量：2-32 个
│   ├─ 截止时间 > 当前时间
│   └─ 结算时间 > 截止时间
├─ 存储事件数据：
│   ├─ events[eventId] = Event {
│   │     eventId: eventId,
│   │     title: "事件标题",
│   │     description: "事件描述",
│   │     deadline: 投注截止时间戳,
│   │     settlementTime: 预期结算时间戳,
│   │     status: Created,
│   │     creator: msg.sender,
│   │     outcomes: ["选项A", "选项B", "选项C"],
│   │     winningOutcomeIndex: 0 (未设置)
│   │   }
│   └─ eventExists[eventId] = true
└─ 触发事件：EventCreated(eventId, title, outcomes)
```

**代码示例：**
```solidity
// 事件创建者调用
string[] memory outcomes = new string[](3);
outcomes[0] = "特朗普获胜";
outcomes[1] = "哈里斯获胜";
outcomes[2] = "其他候选人获胜";

uint256 eventId = eventPod.createEvent(
    "2024 年美国总统大选",           // title
    "谁将赢得 2024 年美国总统选举？", // description
    block.timestamp + 30 days,       // deadline（30天后截止投注）
    block.timestamp + 60 days,       // settlementTime（60天后结算）
    outcomes                         // 结果选项
);
```

**返回：** `eventId` (uint256) - 新创建的事件ID

---

#### 步骤 2：激活事件（使其可交易）
```
事件创建者 → EventPod.updateEventStatus(eventId, Active)
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
eventPod.updateEventStatus(eventId, EventStatus.Active);
```

---

#### 步骤 3：在订单簿中注册事件
```
事件创建者 → OrderBookPod.addEvent(eventId, outcomeCount)
├─ 从 EventPod 获取事件信息（通过引用）
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
orderBookPod.addEvent(eventId, 3); // 3 个结果选项
```

---

#### 步骤 4：在资金池中注册事件（自动触发）
```
OrderBookPod.addEvent() 内部调用 → FundingPod.registerEvent(eventId, outcomes)
├─ 注册结果选项：
│   └─ for i in 0..outcomes.length:
│       eventOutcomes[eventId][i] = true
├─ 初始化奖金池：eventPrizePool[eventId][supportedTokens] = 0
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
│   addEvent      │  → OrderBookPod 支持该事件
└────────┬────────┘
         │
┌────────▼────────┐
│  步骤 4 (自动)  │  在资金池中注册事件
│ registerEvent   │  → FundingPod 支持该事件
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
- **Settled**：事件已结算，奖金已分配
- **Cancelled**：事件已取消，退还资金

---

## 流程二：下单 → 结算

### 参与角色
- **用户（交易者）**：存款、下单、提款
- **FundingPod**：资金托管与 Long Token 管理
- **OrderBookPod**：订单撮合引擎
- **FeeVaultPod**：费用收取
- **EventPod**：事件状态管理
- **OracleAdapter**：预言机结果提交
- **平台管理员**：提取平台费用

### 详细步骤

---

### 阶段 A：用户准备（存款 + 铸造）

#### 步骤 A1：用户存入资金
```
用户 → FundingPod.depositErc20(tokenAddress, amount)
├─ 前置条件：用户已授权 FundingPod 转账 ERC20 代币
│   └─ IERC20(token).approve(fundingPodAddress, amount)
├─ 转账代币：token.transferFrom(user, address(this), amount)
├─ 更新余额：
│   ├─ userTokenBalances[user][token] += amount
│   └─ tokenBalances[token] += amount
└─ 触发事件：Deposited(user, token, amount)
```

**代码示例：**
```solidity
// 用户调用（假设使用 USDT）
address usdt = 0xUSDT...;
IERC20(usdt).approve(address(fundingPod), 1000 ether);
fundingPod.depositErc20(usdt, 1000 ether); // 存入 1000 USDT
```

**用户余额：** `userTokenBalances[user][USDT] = 1000 USDT`

---

#### 步骤 A2：铸造完整集合（可选，提供流动性）
```
用户 → FundingPod.mintCompleteSetDirect(eventId, tokenAddress, amount)
├─ 验证事件存在且未结算
├─ 验证用户有足够余额：require(userTokenBalances[user][token] >= amount)
├─ 扣除用户余额：userTokenBalances[user][token] -= amount
├─ 为每个结果选项铸造 Long Token：
│   └─ for i in 0..outcomeCount:
│       longPositions[user][token][eventId][i] += amount
├─ 增加奖金池：eventPrizePool[eventId][token] += amount
└─ 触发事件：CompleteSetMinted(user, eventId, token, amount)
```

**代码示例：**
```solidity
// 用户调用（用 100 USDT 铸造完整集合）
fundingPod.mintCompleteSetDirect(eventId, usdt, 100 ether);
```

**效果：**
- 用户余额：`userTokenBalances[user][USDT] = 900 USDT` (扣除 100)
- 用户获得 Long Token：
  - `longPositions[user][USDT][eventId][0] = 100` (选项 A)
  - `longPositions[user][USDT][eventId][1] = 100` (选项 B)
  - `longPositions[user][USDT][eventId][2] = 100` (选项 C)
- 奖金池：`eventPrizePool[eventId][USDT] = 100 USDT`

---

### 阶段 B：下单与撮合

#### 步骤 B1：用户下买单
```
用户 → OrderBookPod.placeOrder(eventId, outcomeIndex, Buy, price, amount, token)
├─ 验证事件状态为 Active
├─ 验证结果选项存在：supportedOutcomes[eventId][outcomeIndex]
├─ 验证价格范围：1 <= price <= 10000 (基点)
│
├─ 【子步骤 1】锁定资金
│   ├─ 计算所需金额：requiredAmount = (amount × price) / 10000
│   ├─ FundingPod.lockForOrder(user, token, requiredAmount, orderId)
│   │   ├─ 验证余额：require(userTokenBalances[user][token] >= requiredAmount)
│   │   ├─ 扣除可用余额：userTokenBalances[user][token] -= requiredAmount
│   │   └─ 增加锁定余额：orderLockedUSDT[user][orderId] = requiredAmount
│   └─ 触发事件：FundsLocked(user, orderId, token, requiredAmount)
│
├─ 【子步骤 2】收取下单费用
│   ├─ FeeVaultPod.calculateFee(amount, "trade") → fee
│   │   └─ fee = amount × feeRates["trade"] / 10000  (默认 30 基点 = 0.3%)
│   ├─ FeeVaultPod.collectFee(user, token, fee, eventId, "trade")
│   │   ├─ 从用户余额扣除：userTokenBalances[user][token] -= fee
│   │   ├─ 增加费用余额：feeBalances[token] += fee
│   │   ├─ 更新统计：
│   │   │   ├─ totalFeesCollected[token] += fee
│   │   │   ├─ eventFees[eventId][token] += fee
│   │   │   └─ userPaidFees[user][token] += fee
│   │   └─ 触发事件：FeeCollected(user, token, fee, eventId, "trade")
│   └─ 实际费用：fee = 100 × 0.003 = 0.3 USDT
│
├─ 【子步骤 3】订单撮合（自动）
│   ├─ 查找匹配卖单：从最低卖价开始遍历
│   │   └─ 遍历价格：lowestSellPrice → price (买单价格)
│   │
│   ├─ 对每个匹配的卖单执行成交：
│   │   ├─ 计算成交量：matchAmount = min(buyOrder.remaining, sellOrder.remaining)
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
│   │   ├─ 结算资金：FundingPod.settleMatchedOrder()
│   │   │   ├─ 计算金额：usdtAmount = (matchAmount × sellPrice) / 10000
│   │   │   ├─ 买方：
│   │   │   │   ├─ 解锁 USDT：orderLockedUSDT[buyer][buyOrderId] -= usdtAmount
│   │   │   │   └─ 增加 Long Token：longPositions[buyer][token][eventId][outcome] += matchAmount
│   │   │   ├─ 卖方：
│   │   │   │   ├─ 解锁 Long Token：orderLockedLong[seller][sellOrderId] -= matchAmount
│   │   │   │   └─ 增加 USDT：userTokenBalances[seller][token] += usdtAmount
│   │   │   └─ 触发事件：OrderSettled(buyOrderId, sellOrderId, matchAmount, usdtAmount)
│   │   │
│   │   ├─ 收取成交费用（买卖各 50%）：
│   │   │   ├─ buyerFee = matchAmount × feeRate / 20000  (15 基点 = 0.15%)
│   │   │   ├─ sellerFee = matchAmount × feeRate / 20000
│   │   │   ├─ FeeVaultPod.collectFee(buyer, token, buyerFee, ...)
│   │   │   └─ FeeVaultPod.collectFee(seller, token, sellerFee, ...)
│   │   │
│   │   └─ 触发事件：OrderMatched(buyOrderId, sellOrderId, matchAmount, sellPrice)
│   │
│   └─ 循环直到：buyOrder.remaining == 0 或无更多匹配卖单
│
├─ 【子步骤 4】入簿（如有剩余）
│   ├─ if (buyOrder.remainingAmount > 0):
│   │   ├─ 订单状态 = Partial (部分成交) 或 Pending (未成交)
│   │   ├─ 添加到订单簿：buyOrders[price].push(orderId)
│   │   └─ 订单按 FIFO 顺序排列
│   └─ else:
│       ├─ 订单状态 = Filled (完全成交)
│       └─ 从订单簿移除
│
└─ 触发事件：OrderPlaced(orderId, user, eventId, outcome, Buy, price, amount)
```

**代码示例：**
```solidity
// 用户下买单（买入选项 0，价格 6000 = 0.6 USDT，数量 100）
orderBookPod.placeOrder(
    eventId,        // 事件ID
    0,              // outcomeIndex（选项 A）
    OrderSide.Buy,  // 买单
    6000,           // price（6000 基点 = 0.6 USDT per token）
    100 ether,      // amount（买入 100 个）
    usdt            // tokenAddress
);
```

**资金变化：**
- 锁定金额：`(100 × 6000) / 10000 = 60 USDT`
- 下单费用：`100 × 0.003 = 0.3 USDT`
- 用户可用余额减少：`60 + 0.3 = 60.3 USDT`
- 如果匹配成交，买方获得 Long Token，卖方获得 USDT

---

#### 步骤 B2：用户下卖单（类似流程）
```
用户 → OrderBookPod.placeOrder(eventId, outcomeIndex, Sell, price, amount, token)
├─ 【子步骤 1】锁定 Long Token
│   └─ FundingPod.lockForOrder(user, Long Token, amount, orderId)
│       ├─ 验证持仓：require(longPositions[user][token][eventId][outcome] >= amount)
│       ├─ 扣除持仓：longPositions[user][token][eventId][outcome] -= amount
│       └─ 锁定：orderLockedLong[user][orderId] = amount
│
├─ 【子步骤 2】收取下单费用（同买单）
├─ 【子步骤 3】订单撮合：从最高买价开始匹配
└─ 【子步骤 4】入簿（如有剩余）
```

**代码示例：**
```solidity
// 用户下卖单（卖出选项 0，价格 6500 = 0.65 USDT，数量 50）
orderBookPod.placeOrder(
    eventId,
    0,
    OrderSide.Sell,
    6500,           // 卖价 0.65 USDT
    50 ether,       // 卖出 50 个
    usdt
);
```

---

#### 步骤 B3：取消订单（可选）
```
用户 → OrderBookPod.cancelOrder(orderId)
├─ 验证订单所有者：require(orders[orderId].user == msg.sender)
├─ 验证订单状态：require(status == Pending || status == Partial)
├─ 解锁资金：FundingPod.unlockForOrder(user, orderId)
│   ├─ 买单：
│   │   ├─ 释放锁定 USDT：lockedAmount = orderLockedUSDT[user][orderId]
│   │   ├─ 返还余额：userTokenBalances[user][token] += lockedAmount
│   │   └─ 清空锁定：orderLockedUSDT[user][orderId] = 0
│   └─ 卖单：
│       ├─ 释放锁定 Long Token：lockedAmount = orderLockedLong[user][orderId]
│       ├─ 返还持仓：longPositions[user][token][eventId][outcome] += lockedAmount
│       └─ 清空锁定：orderLockedLong[user][orderId] = 0
├─ 更新订单状态：orders[orderId].status = Cancelled
├─ 从订单簿移除
└─ 触发事件：OrderCancelled(orderId)
```

**代码示例：**
```solidity
// 用户取消订单
orderBookPod.cancelOrder(orderId);
```

---

### 阶段 C：事件结算

#### 步骤 C1：请求预言机
```
事件创建者/管理员 → EventPod.requestOracleResult(eventId)
├─ 验证事件状态：require(status == Active)
├─ 验证已过截止时间：require(block.timestamp >= deadline)
├─ 存储请求：eventOracleRequests[eventId] = OracleRequest {
│     requestTime: block.timestamp,
│     fulfilled: false
│   }
└─ 触发事件：OracleResultRequested(eventId, oracleAdapter)
```

**代码示例：**
```solidity
// 事件创建者或管理员调用
eventPod.requestOracleResult(eventId);
```

---

#### 步骤 C2：预言机提交结果
```
预言机 → OracleAdapter.submitResult(requestId, eventId, winningOutcomeIndex, merkleProof)
├─ 验证预言机授权：require(isAuthorizedOracle[msg.sender])
├─ 验证事件存在请求
├─ 调用 EventPod.settleEvent(eventId, winningOutcomeIndex, merkleProof)
└─ 标记已完成：eventOracleRequests[eventId].fulfilled = true
```

**代码示例：**
```solidity
// 预言机调用
oracleAdapter.fulfillResult(
    eventId,
    1,              // 获胜选项索引（选项 B）
    merkleProof     // Merkle 证明
);
```

---

#### 步骤 C3：事件结算
```
EventPod.settleEvent(eventId, winningOutcomeIndex, merkleProof)
├─ 验证 Merkle 证明
├─ 更新事件状态：
│   ├─ events[eventId].status = Settled
│   └─ events[eventId].winningOutcomeIndex = winningOutcomeIndex
├─ 从活跃列表移除
├─ 调用 OrderBookPod.settleEvent(eventId, winningOutcomeIndex)
│   ├─ 标记已结算：eventSettled[eventId] = true
│   ├─ 存储结果：eventResults[eventId] = winningOutcomeIndex
│   │
│   ├─ 【子步骤 1】取消所有待成交订单
│   │   └─ for each order where status == Pending or Partial:
│   │       ├─ FundingPod.unlockForOrder(user, orderId)  // 释放锁定资金
│   │       └─ orders[orderId].status = Cancelled
│   │
│   └─ 【子步骤 2】结算持仓，分配奖金
│       └─ FundingPod.settleEvent(eventId, winningOutcomeIndex, winners[], amounts[])
│           ├─ 标记已结算：eventSettled[eventId] = true
│           ├─ 获取奖金池：prizePool = eventPrizePool[eventId][token]
│           ├─ 计算总获胜持仓：
│           │   └─ totalWinningPositions = Σ longPositions[user][token][eventId][winningOutcome]
│           │
│           └─ 分配奖金给每个获胜者：
│               └─ for each winner in positionHolders[eventId][winningOutcome]:
│                   ├─ userPosition = longPositions[winner][token][eventId][winningOutcome]
│                   ├─ reward = (prizePool × userPosition) / totalWinningPositions
│                   ├─ 增加可用余额：userTokenBalances[winner][token] += reward
│                   └─ 触发事件：RewardDistributed(winner, token, reward)
│
└─ 触发事件：EventSettled(eventId, winningOutcomeIndex)
```

**奖金分配公式：**
```
用户奖励 = (奖金池总额 × 用户获胜 Long Token) / 所有获胜者 Long Token 总和
```

**示例：**
- 奖金池：1000 USDT
- 选项 B 获胜（总持仓 500 个）
- 用户 A 持有 100 个选项 B → 奖励 = (1000 × 100) / 500 = 200 USDT
- 用户 B 持有 200 个选项 B → 奖励 = (1000 × 200) / 500 = 400 USDT

---

### 阶段 D：提取资金

#### 步骤 D1：用户提取获胜奖金
```
用户 → FundingPod.withdrawDirect(tokenAddress, amount)
├─ 验证余额：require(userTokenBalances[user][token] >= amount)
├─ 扣除余额：userTokenBalances[user][token] -= amount
├─ 转账：token.transfer(user, amount)
└─ 触发事件：Withdrawn(user, token, amount)
```

**代码示例：**
```solidity
// 用户提取 200 USDT
fundingPod.withdrawDirect(usdt, 200 ether);
```

---

#### 步骤 D2：平台管理员提取费用
```
平台管理员 → FeeVaultPod.withdrawFee(tokenAddress, amount)
├─ 访问控制：require(msg.sender == owner())
├─ 验证费用余额：require(feeBalances[token] >= amount)
├─ 扣除余额：feeBalances[token] -= amount
├─ 更新统计：totalFeesWithdrawn[token] += amount
├─ 转账：token.transfer(owner(), amount)
└─ 触发事件：FeeWithdrawn(token, owner(), amount)
```

**代码示例：**
```solidity
// 平台管理员提取 50 USDT 费用
feeVaultPod.withdrawFee(usdt, 50 ether);
```

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
         │  │  ┌─────── 1. 锁定资金/Long Token
         │  │  │
         │  │  ├─────── 2. 收取下单费用 (0.3%)
         │  │  │
         │  │  ├─────── 3. 自动撮合
         │  │  │         ├─ 更新持仓
         │  │  │         ├─ 结算资金
         │  │  │         └─ 收取成交费用 (0.15% × 2)
         │  │  │
         │  │  └─────── 4. 入簿（如有剩余）
         │  │
         │  │  【可选】
         └──┼──▶ B3: 取消订单 (cancelOrder)
            │    └─ 解锁资金/Long Token
            │
┌───────────▼──────────────────────────────────────────────────┐
│                    阶段 C：事件结算                            │
└──────────────────────────────────────────────────────────────┘
            │
       ┌────▼─────┐
       │C1: 请求   │
       │预言机      │
       │requestOracle│
       └────┬─────┘
            │
       ┌────▼─────┐
       │C2: 预言机 │
       │提交结果    │
       │fulfillResult│
       └────┬─────┘
            │
       ┌────▼─────┐
       │C3: 事件   │
       │结算       │
       │settleEvent│
       └────┬─────┘
            │
            ├─────── 取消待成交订单
            │
            └─────── 分配奖金给获胜者
                     └─ 按持仓比例分配奖金池
                        reward = (prizePool × userPosition) / totalWinningPositions
            │
┌───────────▼──────────────────────────────────────────────────┐
│                    阶段 D：提取资金                            │
└──────────────────────────────────────────────────────────────┘
            │
       ┌────┴─────┬─────────────┐
       │          │             │
  ┌────▼─────┐   │      ┌──────▼──────┐
  │D1: 用户   │   │      │D2: 平台管理员│
  │提取奖金    │   │      │提取费用      │
  │withdrawDirect│ │      │withdrawFee  │
  └──────────┘   │      └─────────────┘
                 │
            ┌────▼─────┐
            │  完成     │
            └──────────┘
```

---

## 关键数据结构

### EventPod
```solidity
events[eventId] = Event {
    eventId: uint256,
    title: string,
    description: string,
    deadline: uint256,           // 投注截止时间
    settlementTime: uint256,     // 预期结算时间
    status: EventStatus,         // Created/Active/Settled/Cancelled
    creator: address,            // 事件创建者
    outcomes: string[],          // 结果选项
    winningOutcomeIndex: uint8   // 获胜选项（结算后）
}
```

### OrderBookPod
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
    status: OrderStatus,         // Pending/Partial/Filled/Cancelled
    tokenAddress: address
}

positions[eventId][outcomeIndex][user] = amount  // 持仓跟踪
```

### FundingPod
```solidity
userTokenBalances[user][token] = amount           // 可用余额
longPositions[user][token][eventId][outcome] = amount  // Long Token 持仓
orderLockedUSDT[user][orderId] = amount           // 买单锁定
orderLockedLong[user][orderId] = amount           // 卖单锁定
eventPrizePool[eventId][token] = amount           // 奖金池
```

### FeeVaultPod
```solidity
feeBalances[token] = amount                       // 费用余额
totalFeesCollected[token] = amount                // 累计费用
eventFees[eventId][token] = amount                // 事件费用
userPaidFees[user][token] = amount                // 用户支付费用
feeRates["trade"] = 30                            // 0.3% 费率
```

---

## 费用说明

### 费用收取点
1. **下单费用**：下单时从用户余额扣除
   - 费率：30 基点 (0.3%)
   - 计算：`fee = orderAmount × 0.003`

2. **成交费用**：订单撮合时从锁定资金扣除
   - 买方：15 基点 (0.15%)
   - 卖方：15 基点 (0.15%)
   - 总计：30 基点 (0.3%)

### 费用流转
```
用户交易费用
    ↓
FeeVaultPod (累积)
    ↓ (管理员手动提取)
平台钱包
```

---

## 总结

### 新架构优势
✅ **简化部署**：无需工厂、部署器、管理器，直接部署 4 个 Pod
✅ **降低复杂度**：删除 ~2200 行代码，减少 32% 代码量
✅ **灵活权限**：白名单事件创建者，平衡质量与灵活性
✅ **直接费用**：费用直接给平台 owner，无需多层转移

### 关键变化
- ❌ **移除**：PodFactory, PodDeployer, 4 个 Managers, AdminFeeVault
- ✅ **保留**：EventPod, OrderBookPod, FundingPod, FeeVaultPod（单实例）
- 🆕 **新增**：事件创建者白名单机制
- 📉 **简化**：费用直接提取，无自动转移逻辑
