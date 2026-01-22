# AdminFeeVault 集成指南

## 📖 概述

本文档说明如何配置 FeeVaultPod 与 AdminFeeVault 的集成，实现手续费自动推送和分配。

---

## 🎯 架构说明

### 三个受益人

AdminFeeVault 将手续费按比例分配给三个受益人：

1. **Treasury (金库)**: 50% - 平台储备金，用于运营和发展
2. **Team (团队)**: 30% - 团队激励，奖励开发和运营人员
3. **Liquidity (流动性)**: 20% - 流动性挖矿，激励做市商提供流动性

### 资金流

```
用户交易 → OrderBookPod → FeeVaultPod (累积)
                                ↓ (达到阈值)
                         AdminFeeVault (分配)
                                ↓
                    ┌───────────┼───────────┐
                    ↓           ↓           ↓
                Treasury     Team      Liquidity
                 (50%)      (30%)       (20%)
```

---

## 🚀 部署和配置

### Step 1: 部署合约

```solidity
// 部署 AdminFeeVault
AdminFeeVault adminFeeVault = new AdminFeeVault();
adminFeeVault.initialize(owner);

// 部署 FeeVaultManager 和 FeeVaultPod
FeeVaultManager feeVaultManager = new FeeVaultManager();
FeeVaultPod feeVaultPod = new FeeVaultPod();

feeVaultManager.initialize(owner, whitelister);
feeVaultPod.initialize(
    owner,
    address(feeVaultManager),
    address(orderBookPod),
    feeRecipient
);
```

### Step 2: 配置 AdminFeeVault 受益人

```solidity
// 设置受益人地址
adminFeeVault.setBeneficiary("treasury", 0x1234...);  // Treasury 地址
adminFeeVault.setBeneficiary("team", 0x5678...);      // Team 地址
adminFeeVault.setBeneficiary("liquidity", 0x9abc...); // Liquidity 地址

// 设置分配比例 (默认已配置，可选)
adminFeeVault.setAllocationRatio("treasury", 5000);   // 50%
adminFeeVault.setAllocationRatio("team", 3000);       // 30%
adminFeeVault.setAllocationRatio("liquidity", 2000);  // 20%
```

### Step 3: 授权 FeeVaultPod

```solidity
// ⭐ 关键: 授权 FeeVaultPod 向 AdminFeeVault 推送手续费
adminFeeVault.addAuthorizedPod(address(feeVaultPod));
```

### Step 4: 配置 FeeVaultPod 自动推送

```solidity
// 设置 AdminFeeVault 地址
feeVaultPod.setAdminFeeVault(address(adminFeeVault));

// 设置自动转账阈值 (以 USDT 为例)
// 当 FeeVaultPod 的 USDT 余额达到 1000 USDT 时自动转账
feeVaultPod.setTransferThreshold(USDT_ADDRESS, 1000 * 10**6);

// 可以为不同 Token 设置不同阈值
feeVaultPod.setTransferThreshold(ETH_ADDRESS, 1 * 10**18);  // 1 ETH
```

---

## 📊 使用示例

### 自动推送流程

```solidity
// 1. 用户下单，支付手续费
orderBookManager.placeOrder(...);
    ↓ (OrderBookPod 调用 FeeVaultPod.collectFee)

// 2. FeeVaultPod 累积手续费
// feeBalances[USDT] = 500 USDT (未达到阈值)

// 3. 继续收取手续费
// feeBalances[USDT] = 800 USDT (未达到阈值)

// 4. 再次收取手续费
// feeBalances[USDT] = 1200 USDT (达到阈值!)
    ↓ (自动触发转账)

// 5. FeeVaultPod 自动转账到 AdminFeeVault
// - 转账金额: 1200 USDT
// - 调用: AdminFeeVault.collectFeeFromPod(USDT, 1200, "trade")
// - FeeVaultPod 余额: 1200 → 0

// 6. AdminFeeVault 记录收入
// pendingDistribution[USDT] = 1200 USDT
```

### 手动分配手续费

```solidity
// 管理员调用分配函数 (或通过自动化脚本)
adminFeeVault.distributeFees(USDT_ADDRESS);

// 分配结果:
// - Treasury: 1200 * 50% = 600 USDT
// - Team: 1200 * 30% = 360 USDT
// - Liquidity: 1200 * 20% = 240 USDT
```

### 受益人提取

```solidity
// Treasury 提取
adminFeeVault.withdraw(USDT_ADDRESS, treasuryAddress, 600 * 10**6);

// Team 提取
adminFeeVault.withdraw(USDT_ADDRESS, teamAddress, 360 * 10**6);

// Liquidity 提取
adminFeeVault.withdraw(USDT_ADDRESS, liquidityAddress, 240 * 10**6);
```

---

## 🔧 管理操作

### 调整阈值

```solidity
// 根据 Gas 费用和交易频率调整
feeVaultPod.setTransferThreshold(USDT_ADDRESS, 2000 * 10**6); // 提高到 2000 USDT

// 禁用自动转账 (设为 0)
feeVaultPod.setTransferThreshold(USDT_ADDRESS, 0);
```

### 更换 AdminFeeVault

```solidity
// 部署新的 AdminFeeVault
AdminFeeVault newAdminFeeVault = new AdminFeeVault();
newAdminFeeVault.initialize(owner);

// 更新 FeeVaultPod 配置
feeVaultPod.setAdminFeeVault(address(newAdminFeeVault));

// 授权新的 AdminFeeVault
newAdminFeeVault.addAuthorizedPod(address(feeVaultPod));
```

### 手动触发转账

如果需要在未达到阈值时手动转账，可以使用 `withdrawFee()`:

```solidity
// Owner 手动提取手续费到 AdminFeeVault
feeVaultPod.withdrawFee(
    USDT_ADDRESS,
    address(adminFeeVault),
    amount
);

// 然后调用 AdminFeeVault 记录收入
adminFeeVault.collectFeeFromPod(USDT_ADDRESS, amount, "manual");
```

---

## 📈 监控和查询

### FeeVaultPod 查询

```solidity
// 查询当前手续费余额
uint256 balance = feeVaultPod.getFeeBalance(USDT_ADDRESS);

// 查询转账阈值
uint256 threshold = feeVaultPod.transferThreshold(USDT_ADDRESS);

// 查询 AdminFeeVault 地址
address vault = feeVaultPod.adminFeeVault();
```

### AdminFeeVault 查询

```solidity
// 查询总收集量
uint256 totalCollected = adminFeeVault.getTotalCollected(USDT_ADDRESS);

// 查询待分配金额
uint256 pending = adminFeeVault.getPendingDistribution(USDT_ADDRESS);

// 查询受益人余额
address treasury = adminFeeVault.getBeneficiary("treasury");
uint256 treasuryBalance = adminFeeVault.beneficiaryBalances(treasury, USDT_ADDRESS);
```

### 事件监听

```javascript
// 监听手续费转账事件
feeVaultPod.on("FeeTransferredToAdmin", (token, amount, category, event) => {
    console.log(`Fee transferred: ${amount} ${token} (${category})`);
});

// 监听手续费分配事件
adminFeeVault.on("FeeDistributed", (token, recipient, amount, category, event) => {
    console.log(`Fee distributed: ${amount} ${token} to ${recipient}`);
});

// 监听阈值更新事件
feeVaultPod.on("TransferThresholdUpdated", (token, oldThreshold, newThreshold, event) => {
    console.log(`Threshold updated for ${token}: ${oldThreshold} → ${newThreshold}`);
});
```

---

## ⚠️ 注意事项

### 安全性

1. **授权管理**: 只有授权的 Pod 才能向 AdminFeeVault 推送手续费
2. **防重入保护**: `_transferToAdminVault()` 使用 `nonReentrant` 修饰符
3. **Owner 权限**: 只有 Owner 可以配置阈值和 AdminFeeVault 地址

### Gas 优化

1. **阈值设置**: 阈值过低会导致频繁转账，增加 Gas 成本
2. **批量转账**: 建议根据交易频率设置合理阈值
3. **示例配置**:
   - 高频交易市场: 1000-5000 USDT
   - 中频交易市场: 500-1000 USDT
   - 低频交易市场: 100-500 USDT

### 兼容性

1. **支持 ETH 和 ERC20**: 自动识别 Token 类型
2. **多 Token 支持**: 每个 Token 独立配置阈值
3. **可禁用**: 设置阈值为 0 即可禁用自动转账

---

## 🎉 总结

FeeVaultPod 与 AdminFeeVault 的集成提供了：

- ✅ 自动化手续费收集和分配
- ✅ 灵活的阈值配置
- ✅ 透明的受益人分配机制
- ✅ 完整的事件日志和监控
- ✅ Gas 优化的批量转账
- ✅ 安全的权限控制

通过合理配置，可以实现高效、透明、自动化的平台手续费管理！
