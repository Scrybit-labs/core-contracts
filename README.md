# 去中心化预测市场平台

## 1. 概述
本仓库包含基于 Foundry 的预测市场智能合约实现，采用**直接面向消费者（D2C）**的简化架构：仅部署一套核心 Pod 合约，所有用户共享，不再区分 vendor/租户，也不再使用 Factory/Manager 层。

核心特点：
- 单实例 Pod（EventPod / OrderBookPod / FundingPod / FeeVaultPod）
- 事件创建白名单（EventPod 管理）
- 订单簿撮合、虚拟 Long Token、完整集合铸造
- OracleManager + OracleAdapter 负责预言机结果
- 费用直接归集到 FeeVaultPod，owner 直接提现

## 2. 系统架构

```
平台管理员（Owner）
├── EventPod（单实例，管理所有事件）
│   └── 事件创建者白名单（授权地址可创建事件）
├── OrderBookPod（单实例，管理所有订单）
├── FundingPod（单实例，管理所有资金）
├── FeeVaultPod（单实例，手续费直接归 owner）
└── OracleAdapter（事件结算）

OracleManager（适配器注册与授权）
└── OracleAdapter
```

## 3. 核心模块

### 3.1 EventPod
- 事件创建、状态管理、取消与结算
- 白名单事件创建者：`addEventCreator()` / `removeEventCreator()`
- 预言机请求：`requestOracleResult()`

### 3.2 OrderBookPod
- 用户下单、撮合、取消
- 自动撮合（买单从最低卖价匹配，卖单从最高买价匹配，FIFO）
- 结算事件：`settleEvent()`

### 3.3 FundingPod
- 入金/出金（ETH / ERC20）
- 完整集合铸造/销毁
- 锁定资金与撮合结算

### 3.4 FeeVaultPod
- 收取下单与撮合手续费
- owner 直接提现：`withdrawFee()`

### 3.5 Oracle 系统
- OracleManager 管理适配器
- OracleAdapter 处理请求与结果提交
- EventPod 作为 OracleConsumer

## 4. 核心流程（摘要）

完整流程详见 `CORE_WORKFLOW.md`。

### 4.1 发布事件
1. Owner 添加事件创建者白名单
2. 创建事件（状态 Created）
3. 激活事件（状态 Active）
4. 在 OrderBookPod 注册事件

### 4.2 交易与结算
1. 用户入金（FundingPod）
2. 下买/卖单（OrderBookPod 自动撮合）
3. 事件到期后请求预言机结果
4. OracleAdapter 回调结算
5. FundingPod 分配奖金，用户提现

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
- 下单费用：0.3%（默认 30 bp）
- 撮合费用：买卖各 0.15%
- 费用流向：用户 → FeeVaultPod → Owner

## 7. 相关文档
- `CORE_WORKFLOW.md` - D2C 工作流细节
- `TOB_ELIMINATION_PLAN.md` - 架构迁移计划（已实现）
- `L2_DEPLOYMENT_GUIDE.md` - L2 部署说明
- `VIRTUAL_LONG_TOKEN_GUIDE.md` - 虚拟 Long Token 说明
