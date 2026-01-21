# 去中心化预测市场 BaaS 平台

## 1. 概述

这是一个完全去中心化的事件预测市场区块链即服务 (BaaS) 平台，旨在帮助开发者和项目团队快速构建专属的预测市场。它通过模块化的智能合约架构，实现了事件、资金和平台费用的完全分离。

一句话概括：项目 = 去中心化 + 模块化设计 + 多链支持 + AI 代理驱动的预测市场构建器

主要特点包括：

- 完全基于智能合约构建
- 透明的事件、资金和规则
- 具有可验证的无需信任性的自动结算
- 用户参与门槛低

## 2.平台简介

该平台提供完整且可用于生产环境的技术框架。开发者可以在几秒钟内部署功能齐全的预测市场去中心化应用（DApp）。

核心能力包括：

- 去中心化资金托管（由智能合约自动管理）
- 独立事件架构（互不影响的独立市场）
- 用于快速创建自定义预测市场的 AI 代理开发工具包
- 支持多链，兼容主流区块链生态系统

## 3.系统架构

[![Architecture](./assets/architecture.png)](https://github.com/roothash-pay/event-contracts)

### 3.1.智能合约架构

该平台系统采用完全模块化和基于 Pod 的设计，可实现横向扩展和平台隔离：

#### Event Creation & Management

- EventManager: 管理事件生命周期并分发事件更新。
- EventPod: 专用的事件处理 pod，可独立处理不同的事件组。

#### Funding Management & Settlement

- FundingManager: 管理市场资金池、结算逻辑和奖励分配。
- FundingPod: 用于资金跟踪和自动结算的资金池级合约舱。

#### Fee & Revenue Management

- FeeVaultManager: 管理每个项目或市场的费用累积。
- FeeVaultPod: 用于平台隔离的独立费用池。

#### Decentralized Order Matching

- OrderBookManager:：管理用户持仓和订单状态。
- OrderBookPod: 订单簿 pod 独立运行，以实现可扩展性和隔离性。

#### Admin-Level Fee Custody

- AdminFeeVault: 存储汇总的平台级管理费用，并实现收入分成。

## 4.总结

该平台提供了一个模块化、去中心化且对开发者友好的框架，用于构建可扩展的预测市场。凭借基于智能合约的自动化、多链部署能力和人工智能驱动的生成工具，该平台大幅降低了推出安全、透明且可定制的预测市场应用程序的门槛。

## 5.Usage

### 5.1.Build

```shell
$ forge build
```

### 5.2.Test

```shell
$ forge test
```

### 5.3.Format

```shell
$ forge fmt
```

### 5.4.Gas Snapshots

```shell
$ forge snapshot
```

### 5.5.Deploy

```shell

```

## 6.算法

📚 settleMatchedOrder 撮合算法详解

🎯 核心概念: 预测市场的完整合约模型 (Complete Set)

在预测市场中,每个事件的结果被建模为 完整合约集 (Complete Set):

- 1 份完整合约 = 1 单位价值 (例如 1 USDT)
- 每份完整合约包含所有可能结果的份额
- 只有一个结果会获胜,获胜份额可以兑换为 1 单位价值

---

💡 算法原理

// ❌ 这个公式假设: P(outcome) + P(opposite) = 1
uint256 sellerPayment = (amount \* (PRICE_PRECISION - price)) / PRICE_PRECISION;

问题场景示例

场景：世界杯冠军预测（4 个结果）

- 阿根廷: 40%
- 巴西: 30%
- 法国: 20%
- 德国: 10%

❌ 错误交易:
Alice 买 100 份 "阿根廷" @ 0.4 → 支付 40 USDT ✅
Bob 卖 100 份 "阿根廷" @ 0.4 → 支付 60 USDT ❌

问题: Bob 卖出"阿根廷"并不等于买入"其他所有队"!

- 二元市场: 卖 Yes = 买 No (补数关系)
- 多结果市场: 卖 A ≠ 买 (B+C+D)，不存在简单补数

---

🔧 修复方案

方案 1：对手盘模式（推荐 - 最简单）

核心思路: 卖家锁定完整份额价值（1 单位 = MAX_PRICE）

```
function settleMatchedOrder(
    address buyer,
    address seller,
    address token,
    uint256 amount,
    uint256 price,
    uint256 eventId,
    uint256 buyOutcomeId,
    uint256 sellOutcomeId
) external onlyOrderBookPod {
require(buyOutcomeId == sellOutcomeId, "FundingPod: outcome mismatch");

      // 买家支付 = amount * price
      uint256 buyerPayment = (amount * price) / PRICE_PRECISION;

      // ✅ 修复: 卖家支付完整份额价值 (不管几个结果)
      uint256 sellerPayment = amount;  // 1 份 = 1 单位价值 (MAX_PRICE = 10000 = 1.0)

      // 买家锁定减少
      lockedBalances[buyer][token][eventId][buyOutcomeId] -= buyerPayment;

      // 卖家锁定增加 (完整份额)
      lockedBalances[seller][token][eventId][sellOutcomeId] += sellerPayment;

      // 更新卖家总锁定
      userEventTotalLocked[seller][token][eventId] += sellerPayment;

      // 奖金池增加 (买家支付 + 卖家锁定)
      eventPrizePool[eventId][token] += sellerPayment;

}
```

撮合示例:
Alice 买 100 份 "阿根廷" @ 0.4
Bob 卖 100 份 "阿根廷" @ 0.4

撮合:

- Alice 支付: 40 USDT (下单时已锁定并加入奖金池)
- Bob 锁定: 100 USDT (撮合时锁定并加入奖金池)
- 奖金池总额: 40 + 100 = 140 USDT

结算:

- 如果阿根廷赢: Alice 持有 100 份,获得 140 USDT (赚 100 USDT)
- 如果阿根廷输: Bob 解锁,获得 140 USDT (赚 40 USDT)

优点:

- ✅ 简单直观,适用于任意数量结果
- ✅ 无需知道事件有几个结果
- ✅ 风险对等: 买家最多亏损投入,卖家最多亏损份额价值

缺点:

- ❌ 卖家成本高 (需要锁定完整份额)
- ❌ 奖金池会膨胀 (包含买卖双方锁定)

---

方案 2：完整集合铸造模式（更复杂但更精确）

核心思路: 平台铸造包含所有结果的"完整集合",卖家提供完整集合

function settleMatchedOrder(
address buyer,
address seller,
address token,
uint256 amount,
uint256 price,
uint256 eventId,
uint256 buyOutcomeId,
uint256 sellOutcomeId
) external onlyOrderBookPod {
require(buyOutcomeId == sellOutcomeId, "FundingPod: outcome mismatch");

      // 买家支付
      uint256 buyerPayment = (amount * price) / PRICE_PRECISION;

      // ✅ 卖家需要提供"完整集合"
      // 完整集合成本 = amount (1 份所有结果 = 1 USDT)
      // 卖家收入 = buyerPayment
      // 卖家净成本 = amount - buyerPayment
      uint256 sellerNetCost = amount - buyerPayment;

      // 买家锁定减少
      lockedBalances[buyer][token][eventId][buyOutcomeId] -= buyerPayment;

      // 卖家锁定增加 (净成本)
      lockedBalances[seller][token][eventId][sellOutcomeId] += sellerNetCost;

      // 卖家在其他结果上获得持仓
      uint256[] memory allOutcomes = getEventOutcomes(eventId); // 需要新增函数
      for (uint256 i = 0; i < allOutcomes.length; i++) {
          if (allOutcomes[i] != sellOutcomeId) {
              // 卖家获得其他结果的持仓
              positions[eventId][allOutcomes[i]][seller] += amount;
          }
      }

      // 奖金池增加完整集合价值
      eventPrizePool[eventId][token] += amount;

}

优点:

- ✅ 更符合预测市场理论
- ✅ 卖家成本降低 (只需锁定净成本)
- ✅ 奖金池精确 (不会膨胀)

缺点:

- ❌ 实现复杂,需要跨模块交互 (FundingPod 需要访问 EventPod 数据)
- ❌ Gas 成本高 (需要更新多个 outcome 的持仓)

---
