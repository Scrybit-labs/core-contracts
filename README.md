# 去中心化预测市场平台

## 1. 概述
本仓库包含基于 Foundry 的预测市场智能合约实现，采用**直接面向消费者（D2C）**的简化架构：仅部署一套核心 Manager 合约，所有用户共享，不再区分 vendor/租户，也不再使用 Factory/Manager 层。

核心特点：
- 单实例 Manager（EventManager / OrderBookManager / FundingManager / FeeVaultManager）
- 事件创建白名单（EventManager 管理）
- 订单簿撮合、虚拟 Long Token、完整集合铸造
- OracleAdapter（Simple/Mock/Third-party）负责预言机结果
- 费用直接归集到 FeeVaultManager，owner 直接提现

## 2. 系统架构

```
平台管理员（Owner）
├── EventManager（单实例，管理所有事件）
│   └── 事件创建者白名单（授权地址可创建事件）
├── OrderBookManager（单实例，管理所有订单）
├── FundingManager（单实例，统一USD余额管理）
├── FeeVaultManager（单实例，统一USD手续费管理）
└── OracleAdapter（事件结算，Simple/Mock/Third-party）
```

## 3. 核心模块

### 3.1 EventManager
- 事件创建、状态管理、取消与结算
- 白名单事件创建者：`addEventCreator()` / `removeEventCreator()`
- 预言机请求：`requestOracleResult()`

### 3.2 OrderBookManager
- 用户下单、撮合、取消
- 自动撮合（买单从最低卖价匹配，卖单从最高买价匹配，FIFO）
- 结算事件：`settleEvent()`

### 3.3 FundingManager
- 入金/出金（ETH / ERC20）
- 统一USD余额模型
- 完整集合铸造/销毁（1:1 USD价值）
- 锁定资金与撮合结算
- 结算标记与赎回

### 3.4 FeeVaultManager
- 统一USD手续费追踪
- 下单手续费（0.1%）+ 撮合手续费（0.2%）
- owner 直接提现：`withdrawFee()`

### 3.5 Oracle 系统
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

完整流程详见 `CORE_WORKFLOW.md`。

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

## 6. 费用模型
- 下单费用：0.1%（10 bp，从用户USD余额扣除）
- 撮合费用：0.2%（20 bp，买卖方各承担50%，即各0.1%）
- 费用追踪：统一USD余额 protocolUsdFeeBalance
- 费用流向：用户 → FeeVaultManager → Owner（通过FundingManager提现）

## 7. 相关文档
- `CORE_WORKFLOW.md` - D2C 工作流细节
- `MULTI_ORACLE_ROUTING_PLAN.md` - 多预言机路由实现方案
- `TOB_ELIMINATION_PLAN.md` - 架构迁移计划（已实现）
- `L2_DEPLOYMENT_GUIDE.md` - L2 部署说明
- `VIRTUAL_LONG_TOKEN_GUIDE.md` - 虚拟 Long Token 说明
