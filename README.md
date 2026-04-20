# 去中心化预测市场平台

## 1. 概述
本仓库包含基于 Foundry 的预测市场智能合约实现，采用**直接面向消费者（D2C）**的简化架构：仅部署一套核心 Manager 合约，所有用户共享，不再区分 vendor/租户，也不再使用 Factory/Manager 层。

核心特点：
- 单实例 Manager（EventManager / OrderBookManager / FundingManager / FeeVaultManager）
- 事件创建白名单（EventManager 管理）
- **高性能订单簿**：三层存储架构（Price Trees + Order Queues + Global Orders）
- **O(log n) 价格操作**：使用红黑树实现高效价格层级管理
- **Maker-Taker 费用差异化**：激励流动性提供者
- 订单簿撮合、虚拟 Long Token、完整集合铸造
- OracleAdapter（Simple/Mock/Third-party）负责预言机结果
- 费用直接归集到 FeeVaultManager，owner 直接提现

## 2. 系统架构

```
平台管理员（Owner）
├── EventManager（单实例，管理所有事件）
│   └── 事件创建者白名单（授权地址可创建事件）
├── OrderBookManager（单实例，管理所有订单）
│   ├── OrderStorage（三层存储架构）
│   │   ├── Layer 1: Price Trees (RedBlackTree) - O(log n)
│   │   ├── Layer 2: Order Queues (Linked List) - O(1) FIFO
│   │   └── Layer 3: Global Orders (Mapping) - O(1) lookup
│   └── OrderValidator（参数验证 + EIP712 签名支持）
├── FundingManager（单实例，统一USD余额管理）
├── FeeVaultManager（单实例，统一USD手续费管理，Maker-Taker 费用）
└── OracleAdapter（事件结算，Simple/Mock/Third-party）
```

## 3. 核心模块

### 3.1 EventManager
- 事件创建、状态管理、取消与结算
- 白名单事件创建者：`addEventCreator()` / `removeEventCreator()`
- 预言机请求：`requestOracleResult()`

### 3.2 OrderBookManager（已优化）
- 用户下单、撮合、取消
- **三层存储架构**：
  - **Layer 1 (Price Trees)**：红黑树管理价格层级，O(log n) 插入/删除/查找
  - **Layer 2 (Order Queues)**：链表实现 FIFO 队列，O(1) 入队/出队
  - **Layer 3 (Global Orders)**：映射存储订单数据，O(1) 查找
- 自动撮合（买单从最低卖价匹配，卖单从最高买价匹配，FIFO）
- **价格-时间优先**：同价格订单按时间顺序（FIFO）撮合
- 结算事件：`settleEvent()`

### 3.3 OrderStorage
- 封装三层存储逻辑的独立合约
- 价格树操作：`insertPrice()`, `removePrice()`, `getBestPrice()`, `getNextPrice()`
- 订单队列操作：`enqueueOrder()`, `dequeueOrder()`, `peekOrder()`, `isQueueEmpty()`
- 全局订单操作：`storeOrder()`, `getOrder()`, `deleteOrder()`

### 3.4 OrderValidator
- 订单参数验证：价格对齐（10 基点 tick size）、数量、过期时间
- **eventId 和 outcomeIndex 验证**：确保事件已注册且结果索引有效
- EIP712 签名支持：链下订单签名验证（为未来功能预留）
- 常量：`TICK_SIZE = 10`, `MAX_PRICE = 10000`

### 3.5 FundingManager
- 入金/出金（ETH / ERC20）
- 统一USD余额模型
- 完整集合铸造/销毁（1:1 USD价值）
- 锁定资金与撮合结算
- **Issue #11 修复**：买单以更优价格成交时返还剩余 USD
- 结算标记与赎回

### 3.6 FeeVaultManager（已优化）
- 统一USD手续费追踪
- **Maker-Taker 费用差异化**：
  - **Maker（流动性提供者）**：
    - 下单费用：0%（免费）
    - 成交费用：0.05%（5 基点）
  - **Taker（流动性消耗者）**：
    - 下单费用：0%（免费）
    - 成交费用：0.25%（25 基点）
  - **总最大费用**：0.3%（Maker: 0.05%, Taker: 0.25%）
- owner 直接提现：`withdrawFee()`
- **费用计算精度优化**：使用向上取整避免费用不足

### 3.7 Oracle 系统
- **OracleAdapter 设计**：抽象层，支持 Simple（手动）/ Mock（测试）/ Third-party（Chainlink/UMA/API3）
- **事件类型路由**：每个事件有 `eventType` 字段（bytes32），可为不同类型配置不同预言机
  - 例如：体育事件 → Chainlink，加密货币事件 → UMA
  - 路由逻辑：优先使用 `eventTypeToOracleAdapter[eventType]`，否则回退到 `defaultOracleAdapter`
- **EventManager** 作为 OracleConsumer（仅依赖 IOracle 接口）
- **MockOracleAdapter + MockOracle** 用于本地/测试
- **SimpleOracleAdapter** 用于手动/轻量预言机
- 支持多预言机授权与平滑切换（新旧适配器并行完成在途请求）
- 预言机适配器在 `requestOracleResult` 时记录，每个事件不可变

## 4. 核心流程（摘要）

完整流程详见 `Doc/CORE_FLOW.md`。

### 4.1 发布事件
1. Owner 添加事件创建者白名单
2. 创建事件（状态 Created，必须指定 eventType）
   ```solidity
   bytes32 sportsType = keccak256("SPORTS");
   eventManager.createEvent(title, description, deadline, settlementTime, outcomes, sportsType);
   ```
3. 激活事件（状态 Active）
4. 在 OrderBookManager 注册事件

### 4.2 交易与结算
1. 用户入金（FundingManager）
2. 下买/卖单（OrderBookManager 自动撮合）
   - 订单通过 OrderValidator 验证
   - 使用三层存储架构高效管理
   - 自动撮合并应用 Maker-Taker 费用
3. 事件到期后请求预言机结果（EventManager → 根据 eventType 路由到对应 OracleAdapter）
4. OracleAdapter 回调 EventManager.fulfillResult()（proof 可为空）
5. OrderBookManager 取消待成交订单，FundingManager 标记结算
6. 用户调用 redeemWinnings() 赎回奖金（1 胜出 Long Token = 1 USD）

## 5. 部署

使用 `script/SimpleDeploy.s.sol`：

```bash
# 本地部署
make deploy-prediction-local

# L2 测试网
make deploy-prediction-base-sepolia
make deploy-prediction-arbitrum-sepolia
make deploy-prediction-optimism-sepolia
```

## 6. 费用模型（已优化）

### Maker-Taker 费用结构
- **Maker（流动性提供者）**：
  - 下单费用：0%（免费挂单）
  - 成交费用：0.05%（5 基点）
- **Taker（流动性消耗者）**：
  - 下单费用：0%（免费）
  - 成交费用：0.25%（25 基点）
- **总最大费用**：0.3%（单边）

### 费用追踪与流转
- 费用追踪：统一USD余额 `protocolUsdFeeBalance`
- 费用流向：用户 → FeeVaultManager → Owner（通过FundingManager提现）
- **费用计算精度**：使用向上取整（ceiling division）避免费用不足

## 7. 性能优化

### OrderBook 优化（已实施）

| 操作 | 优化前 | 优化后 | 改进 |
|------|--------|--------|------|
| 插入价格层级 | O(n) 数组移位 | O(log n) 树插入 | ✅ 84% gas 节省 |
| 删除价格层级 | O(n) 数组移位 | O(log n) 树删除 | ✅ 83% gas 节省 |
| 查找最优价格 | O(1) 数组访问 | O(log n) 树遍历 | ⚠️ 轻微增加，可接受* |
| 订单撮合（整体） | O(n*m) 嵌套循环 | O(log n * m) | ✅ 20-30% 性能提升 |

\* **查找最优价格的权衡**：虽然从 O(1) 变为 O(log n)，但插入/删除操作的巨大节省（84%）远超这个成本。在实际使用中，插入/删除频率远高于查找频率。

### 关键 Bug 修复

**Issue #11**：买单以更优价格成交时返还剩余 USD
- **问题**：买单锁定 `amount * orderPrice`，但以 `matchPrice < orderPrice` 成交时，剩余 USD 未返还
- **修复**：在 `_executeMatch` 中，买单完全成交后调用 `unlockForOrder()` 返还剩余 USD
- **示例**：订单价 8000，成交价 7000，100 个 token → 返还 10 USD

**成交价格修复**：
- **正确规则**：成交价 = Taker 接受 Maker 的价格
  - 买家是 Taker：成交价 = 卖单价格
  - 卖家是 Taker：成交价 = 买单价格
- **代码**：`uint128 matchPrice = buyerIsTaker ? sellOrder.price : buyOrder.price;`

## 8. 相关文档
- `Doc/CORE_FLOW.md` - D2C 工作流细节（中文）
- `Doc/ORDERBOOK_OPTIMIZATION_PLAN.md` - OrderBook 优化实施计划（中文）
- `Doc/MULTI_ORACLE_ROUTING_PLAN.md` - 多预言机路由实现方案
- `Doc/TOB_ELIMINATION_PLAN.md` - 架构迁移计划（已实现）
- `Doc/L2_DEPLOYMENT_GUIDE.md` - L2 部署说明
- `Doc/VIRTUAL_LONG_TOKEN_GUIDE.md` - 虚拟 Long Token 说明

## 9. 技术栈
- **Solidity**: 0.8.33
- **Foundry**: 构建、测试、部署
- **OpenZeppelin**: 可升级合约（UUPS）、访问控制、EIP712
- **RedBlackTree**: BokkyPooBah's Red-Black Tree Library（O(log n) 价格管理）
- **目标网络**: L2 链（Arbitrum, Base, Optimism）

## 10. 测试

```bash
# 运行所有测试
forge test

# 运行特定测试
forge test --match-contract OrderBookManagerTest
forge test --match-test testPlaceOrder

# Gas 报告
forge test --gas-report

# 覆盖率报告
forge coverage
```

## 11. 安全特性
- **UUPS 可升级模式**：所有 Manager 合约支持升级
- **存储间隙**：预留存储槽位以支持未来扩展
- **访问控制**：基于角色的权限管理
- **重入保护**：关键函数使用 `nonReentrant` 修饰符
- **参数验证**：OrderValidator 统一验证订单参数
- **EIP712 签名**：支持链下订单签名（未来功能）

## 12. 许可证
UNLICENSED

## 13.部署合约主网地址hashkey：
- Deployer:                   0x523df39cAe18ea125930DA730628213e4b147CDc
- MockOracle:                 0xaFdC7a7871a0207e5d2F079Aa6c101f78700d586
- MockOracleAdapter (proxy):  0xd5E9adD135979F436242B85fFD474aCec77950c5
- EventManager (proxy):       0xD3B32Dd902E4EFE5C5186A8a7900157d43a6B450
- FeeVaultManager (proxy):    0x5A39fE21B2d819EAE1c182749deb3fE2aBD6e597
- FundingManager (proxy):     0xF3499B0557AfA2336E9F31ECB345f0d088c8EfcD
- OrderBookManager (proxy):   0xa77ECe2c29480ffE59a4e8859791903277d756De
- OrderStorage (proxy):       0xE6CEA57f878e907259e579bC23e54626B53C7C09