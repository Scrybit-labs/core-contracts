🗂️ 去中心化预测市场 BaaS 平台 - 完整开发清单树

📋 合约部分项目状态概览

- 整体完成度: ~40%
- 核心撮合引擎: ✅ 已完成
- 资金管理系统: ⚠️ 框架完成,核心功能缺失
- 事件管理系统: ❌ 待开发
- 费用管理系统: ❌ 待开发

---

🏗️ 模块一: EventManager & EventPod (事件管理系统)

📝 合约文件

- src/event/core/EventManager.sol - ❌ 空壳
- src/event/core/EventManagerStorage.sol - ❌ 空壳
- src/event/pod/EventPod.sol - ❌ 空壳
- src/event/pod/EventPodStorage.sol - ❌ 空壳
- src/interfaces/event/IEventManager.sol - ❌ 空接口
- src/interfaces/event/IEventPod.sol - ❌ 空接口

🎯 核心功能清单

1.1 EventManagerStorage 数据结构设计

- 定义 Pod 白名单映射 mapping(IEventPod => bool) public podIsWhitelisted
- 定义事件到 Pod 的路由映射 mapping(uint256 => IEventPod) public eventIdToPod
- 定义预言机注册映射 mapping(address => bool) public authorizedOracles
- 添加升级预留空间 uint256[96] private \_\_gap

  1.2 EventManager 管理功能

- addPodToWhitelist(IEventPod pod) - 添加 Pod 白名单
- removePodFromWhitelist(IEventPod pod) - 移除 Pod
- createEvent(...) - 创建事件并分配到 Pod
- registerOracle(address oracle) - 注册预言机
- getEventPod(uint256 eventId) - 查询事件所属 Pod
- 继承 Initializable, OwnableUpgradeable, PausableUpgradeable
- 实现负载均衡算法(轮询/最小负载)

  1.3 EventPodStorage 数据结构设计

- 定义 Event 结构体:
  struct Event {
  uint256 eventId;
  string title;
  string description;
  uint256 deadline; // 下注截止时间
  uint256 settlementTime; // 预计结算时间
  EventStatus status; // 状态枚举
  address creator; // 创建者地址
  uint256[] outcomeIds; // 结果选项 ID 列表
  }
- 定义状态枚举 enum EventStatus { Created, Active, Settled, Cancelled }
- 定义 Outcome 结构体(结果名称、描述)
- 事件存储映射 mapping(uint256 => Event) public events
- 结果存储映射 mapping(uint256 => mapping(uint256 => Outcome)) public outcomes
- 添加升级预留空间

  1.4 EventPod 执行功能

- addEvent(...) - 添加事件到 Pod
- updateEventStatus(uint256 eventId, EventStatus status) - 更新状态
- settleEvent(uint256 eventId, uint256 winningOutcomeId) - 接收预言机结果
- cancelEvent(uint256 eventId) - 取消事件
- getEvent(uint256 eventId) - 查询事件详情
- listActiveEvents() - 列出进行中事件
- 事件状态机验证(防止非法状态转换)
- 权限控制: onlyEventManager 修饰符
- 预言机地址验证

  1.5 链下服务接口预留

- 事件创建时发出 EventCreated(eventId, title, deadline, outcomes) 事件
- 状态更新时发出 EventStatusChanged(eventId, oldStatus, newStatus) 事件
- 结算时发出 EventSettled(eventId, winningOutcomeId, settlementTime) 事件
- 取消时发出 EventCancelled(eventId, reason) 事件

  1.6 与其他模块集成

- 调用 OrderBookManager.registerEventToPod() 注册订单簿
- 调用 OrderBookPod.settleEvent() 触发结算
- 调用 FundingPod 相关接口(待定义)

---

💰 模块二: FundingManager & FundingPod (资金管理系统)

📝 合约文件

- src/event/core/FundingManager.sol - ⚠️ 框架完成
- src/event/core/FundingManagerStorage.sol - ⚠️ 基础结构
- src/event/pod/FundingPod.sol - ⚠️ 框架完成
- src/event/pod/FundingPodStorage.sol - ⚠️ 基础结构
- src/interfaces/event/IFundingManager.sol - ⚠️ 部分接口
- src/interfaces/event/IFundingPod.sol - ⚠️ 部分接口

🎯 核心功能清单

2.1 FundingManagerStorage 扩展

- Pod 白名单映射 (已实现)
- 紧急提现配置映射
- 全局资金统计(可选)

  2.2 FundingManager 扩展功能

- depositErc20IntoPod() - 已实现
- withdrawFromPod() - 用户提现接口
- emergencyWithdraw() - 紧急提现(管理员)
- getPodBalance() - 查询 Pod 总余额
- Pod 白名单验证(当前为 TODO)
- 批量入金功能(Gas 优化)

  2.3 FundingPodStorage 扩展 ⭐ 核心缺失

- 用户可用余额 mapping(address => mapping(address => uint256)) public userTokenBalances ✅
- 用户锁定余额(按事件和结果):
  mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256))))
  public lockedBalances; // user → token → eventId → outcomeId → amount
- 事件奖金池:
  mapping(uint256 => mapping(address => uint256)) public eventPrizePool;
  // eventId → token → totalAmount
- 事件结算状态 mapping(uint256 => bool) public eventSettled
- 用户在事件中的总锁定额(优化查询)

  2.4 FundingPod 核心功能 ⭐⭐⭐ 最高优先级

- deposit() - 已实现
- lockOnOrderPlaced() - 下单时锁定资金
  - 验证用户可用余额充足
  - 从 userTokenBalances 转移到 lockedBalances
  - 记录锁定的事件和结果 ID
  - 发出 FundsLocked 事件
- unlockOnOrderCancelled() - 撤单时解锁资金
  - 从 lockedBalances 转回 userTokenBalances
  - 发出 FundsUnlocked 事件
- settleMatchedOrder() - 撮合成交时资金转移
  - Buyer: 锁定资金 → 持仓(记录在 OrderBookPod)
  - Seller: 锁定资金 → 对手方持仓
  - 不转移资金,仅改变锁定类型
- settleEvent() - 事件结算时分配奖金 ⭐⭐⭐
  - 接收 winningOutcomeId
  - 计算奖金池总额(所有锁定资金)
  - 遍历获胜者持仓,按比例分配奖金
  - 解锁获胜者资金到可用余额
  - 清零失败者锁定余额
  - 发出 EventSettled 事件
- withdraw() - 用户提现
  - 验证可用余额充足
  - 转账 ERC20 Token 到用户地址
  - 更新余额
  - 发出 WithdrawToken 事件
- 权限控制:

  - onlyOrderBookPod - 限制资金锁定/解锁调用者
  - onlyEventPod - 限制事件结算调用者

    2.5 关键算法设计

撮合结算算法(settleMatchedOrder):
// 买家锁定资金:
lockedBalances[buyer][token][eventId][outcomeId] -= matchedAmount \* buyPrice / 10000;

// 卖家锁定资金:
lockedBalances[seller][token][eventId][outcomeId] += matchedAmount \* (10000 - sellPrice) / 10000;

// 持仓更新在 OrderBookPod 中进行

事件结算算法(settleEvent):
// 1. 计算奖金池
uint256 prizePool = eventPrizePool[eventId][token];

// 2. 获取所有获胜者持仓(需要 OrderBookPod 提供接口)
address[] memory winners = orderBookPod.getPositionHolders(eventId, winningOutcomeId);

// 3. 按持仓比例分配
for (uint256 i = 0; i < winners.length; i++) {
uint256 position = orderBookPod.getPosition(eventId, winningOutcomeId, winners[i]);
uint256 reward = prizePool \* position / totalWinningPositions;
userTokenBalances[winners[i]][token] += reward;
lockedBalances[winners[i]][token][eventId][winningOutcomeId] = 0;
}

2.6 链下服务接口预留

- FundsLocked(user, token, amount, eventId, outcomeId)
- FundsUnlocked(user, token, amount, eventId, outcomeId)
- OrderSettled(buyOrderId, sellOrderId, amount, token)
- EventSettled(eventId, winningOutcomeId, prizePool, winnersCount)
- WithdrawToken(user, token, amount)

---

📊 模块三: OrderBookManager & OrderBookPod (订单簿系统)

📝 合约文件

- src/event/core/OrderBookManager.sol - ✅ 已完成
- src/event/core/OrderBookManagerStorage.sol - ✅ 已完成
- src/event/pod/OrderBookPod.sol - ✅ 核心已完成
- src/event/pod/OrderBookPodStorage.sol - ✅ 已完成
- src/interfaces/event/IOrderBookManager.sol - ✅ 已完成
- src/interfaces/event/IOrderBookPod.sol - ✅ 已完成

🎯 功能状态检查

3.1 已完成功能 ✅

- Pod 白名单管理
- 事件路由注册
- 订单创建 placeOrder()
- 订单撮合引擎 \_matchOrder()
- 订单取消 cancelOrder()
- 价格等级维护(买卖分离订单簿)
- 持仓管理 positions 映射
- 事件结算 settleEvent() 框架
- 批量撤单 \_cancelAllPendingOrders()

  3.2 需要补充的功能 ⚠️

- 在 placeOrder() 中调用 FundingPod.lockOnOrderPlaced()
- 在 \_matchOrder() 中调用 FundingPod.settleMatchedOrder()
- 在 cancelOrder() 中调用 FundingPod.unlockOnOrderCancelled()
- 实现 \_settlePositions() 函数(当前为空)
- 添加 getPositionHolders() 接口(供 FundingPod 查询获胜者)
- 添加费用收取调用 FeeVaultPod.collectTradingFee()

  3.3 需要新增的查询接口

- getPositionHolders(uint256 eventId, uint256 outcomeId) returns (address[])
  - 用于事件结算时遍历所有持仓用户
  - 需要维护用户注册表: mapping(uint256 => mapping(uint256 => address[])) private positionHolders
- getTotalPositions(uint256 eventId, uint256 outcomeId) returns (uint256)
  - 返回某个结果的总持仓量
- getUserPositionsByEvent(address user, uint256 eventId) returns (uint256[] memory outcomes, uint256[] memory amounts)

  - 用户在某事件的所有持仓

    3.4 数据结构优化

- 维护持仓用户列表(用于结算遍历):
  // 需要添加到 OrderBookPodStorage
  mapping(uint256 => mapping(uint256 => address[])) private positionHolders;
  mapping(uint256 => mapping(uint256 => mapping(address => bool))) private hasPosition;

---

💸 模块四: FeeVaultManager & FeeVaultPod (费用管理系统)

📝 合约文件

- src/event/core/FeeVaultManager.sol - ❌ 空壳
- src/event/core/FeeVaultManagerStorage.sol - ❌ 空壳
- src/event/pod/FeeVaultPod.sol - ❌ 空壳
- src/event/pod/FeeVaultPodStorage.sol - ❌ 空壳
- src/interfaces/event/IFeeVaultManager.sol - ❌ 空接口
- src/interfaces/event/IFeeVaultPod.sol - ❌ 空接口

🎯 核心功能清单

4.1 FeeVaultManagerStorage 数据结构设计

- Pod 白名单映射 mapping(IFeeVaultPod => bool) public podIsWhitelisted
- 项目到 Pod 的映射 mapping(uint256 => IFeeVaultPod) public projectIdToPod
- 全局费率配置:
  struct FeeConfig {
  uint256 tradingFeeRate; // 交易手续费率(基点,1bp=0.01%)
  uint256 platformCutRate; // 平台抽成比例(基点)
  uint256 minFee; // 最小手续费
  uint256 maxFee; // 最大手续费(封顶)
  }
  FeeConfig public defaultFeeConfig;
  mapping(uint256 => FeeConfig) public projectFeeConfig; // 项目定制费率
- AdminFeeVault 地址 address public adminFeeVault

  4.2 FeeVaultManager 管理功能

- setDefaultFeeConfig(...) - 设置默认费率
- setProjectFeeConfig(uint256 projectId, ...) - 设置项目费率
- registerProject(uint256 projectId, IFeeVaultPod pod) - 注册项目
- setAdminFeeVault(address vault) - 设置平台费用金库地址
- calculateTradingFee(uint256 amount, uint256 projectId) - 计算手续费
- 继承 Initializable, OwnableUpgradeable

  4.3 FeeVaultPodStorage 数据结构设计

- 项目 ID uint256 public projectId
- 费用累积:
  mapping(address => uint256) public collectedFees; // token → amount
  mapping(address => uint256) public platformFees; // 待转给平台的部分
  mapping(address => uint256) public projectFees; // 项目方可提取部分
- 费用统计:
  mapping(uint256 => mapping(address => uint256)) public eventFees; // eventId → token → fees
  uint256 public totalFeesCollected;
  uint256 public lastSettlementTime;

  4.4 FeeVaultPod 核心功能

- collectTradingFee(address token, uint256 amount, uint256 eventId) - 收取交易手续费
  - 从 FundingPod 接收手续费转账
  - 按比例分配项目方和平台方
  - 更新统计数据
  - 发出 FeeCollected 事件
- withdrawProjectFee(address token, address recipient, uint256 amount) - 项目方提取费用
  - 验证调用者权限(项目 owner)
  - 转账到指定地址
  - 更新余额
  - 发出 ProjectFeeWithdrawn 事件
- settlePlatformFee(address token) - 定期转账平台抽成到 AdminFeeVault
  - 计算累积的平台费用
  - 转账到 AdminFeeVault
  - 清零 platformFees 计数器
  - 发出 PlatformFeeTransferred 事件
- getFeeBalance(address token) - 查询费用余额
- getProjectFeeBalance(address token) - 查询项目方可提取余额
- 权限控制: onlyOrderBookPod, onlyProjectOwner

  4.5 手续费收取时机设计

选项 A: 撮合时实时收取
// 在 OrderBookPod.\_matchOrder() 中
uint256 fee = FeeVaultManager.calculateTradingFee(matchedAmount, projectId);
FundingPod.transferFee(buyer, token, fee, feeVaultPod);
FeeVaultPod.collectTradingFee(token, fee, eventId);

选项 B: 结算时统一收取
// 在 FundingPod.settleEvent() 中
for (winner in winners) {
uint256 reward = calculateReward(winner);
uint256 fee = reward \* feeRate / 10000;
transferToUser(winner, reward - fee);
transferToFeeVault(fee);
}

建议: 采用选项 A(撮合时收取),更公平且 Gas 分摊

4.6 链下服务接口预留

- FeeCollected(token, amount, eventId, timestamp)
- ProjectFeeWithdrawn(projectId, token, amount, recipient)
- PlatformFeeTransferred(token, amount, timestamp)

---

🏛️ 模块五: AdminFeeVault (平台费用金库)

📝 合约文件

- src/admin/AdminFeeVault.sol - ❌ 不存在,需要创建

🎯 核心功能清单

5.1 合约创建

- 创建 src/admin/ 目录
- 创建 AdminFeeVault.sol 合约
- 创建 src/interfaces/IAdminFeeVault.sol 接口

  5.2 数据结构设计

contract AdminFeeVault is Ownable, ReentrancyGuard {
// 多 Token 余额
mapping(address => uint256) public tokenBalances;

      // 费用来源记录(可选,用于审计)
      struct FeeRecord {
          address token;
          uint256 amount;
          address from;       // 来自哪个 FeeVaultPod
          uint256 timestamp;
      }
      FeeRecord[] public feeHistory;

      // 提现记录
      struct WithdrawalRecord {
          address token;
          uint256 amount;
          address to;
          uint256 timestamp;
      }
      WithdrawalRecord[] public withdrawalHistory;

      // 授权接收者列表(只有 FeeVaultPod 可以转入)
      mapping(address => bool) public authorizedSenders;

}

5.3 核心功能

- receiveFee(address token, uint256 amount) - 接收平台抽成
  - 验证调用者为授权的 FeeVaultPod
  - 使用 safeTransferFrom 接收 Token
  - 更新 tokenBalances
  - 记录 feeHistory
  - 发出 FeeReceived 事件
- withdraw(address token, address to, uint256 amount) - 提取费用
  - onlyOwner 权限
  - 验证余额充足
  - 转账到指定地址
  - 记录 withdrawalHistory
  - 发出 FeeWithdrawn 事件
- addAuthorizedSender(address sender) - 添加授权发送者(FeeVaultPod)
- removeAuthorizedSender(address sender) - 移除授权
- getBalance(address token) - 查询余额
- getFeeHistory(uint256 offset, uint256 limit) - 查询历史记录
- 紧急暂停功能 pause()

  5.4 安全考虑

- 继承 ReentrancyGuard 防止重入攻击
- 使用 SafeERC20 安全转账
- 添加提现限额和冷却时间(可选)
- 考虑使用多签钱包作为 Owner(如 Gnosis Safe)

---

🔗 模块六: 预言机集成 (dapplink-oracle-contracts)

📝 合约文件

- src/oracle/OracleRegistry.sol - ❌ 需要创建
- src/oracle/OracleConsumer.sol - ❌ 需要创建(EventPod 实现)
- src/interfaces/IOracle.sol - ❌ 需要创建

🎯 核心功能清单

6.1 预言机接口设计

interface IOracle {
// 请求事件结果
function requestEventResult(
uint256 eventId,
string calldata eventDescription
) external returns (bytes32 requestId);

      // 获取请求状态
      function getRequestStatus(bytes32 requestId) external view returns (
          bool fulfilled,
          uint256 result,
          uint256 timestamp
      );

}

interface IOracleConsumer {
// EventPod 需要实现此接口
function fulfillResult(
uint256 eventId,
uint256 winningOutcomeId,
bytes calldata proof
) external;
}

6.2 OracleRegistry 功能

- 预言机注册与管理
- 预言机信誉评分
- 多预言机共识机制(可选)
- 结果提交时间窗口限制
- 恶意预言机惩罚(Slashing)

  6.3 EventPod 集成

- 实现 IOracleConsumer 接口
- 在 fulfillResult() 中验证:
  - 调用者为授权预言机
  - 事件状态为 Active
  - 结果 ID 合法
  - 包含有效的 Proof(Merkle Proof 或签名)
- 调用 OrderBookPod.settleEvent() 触发结算
- 发出 OracleResultReceived 事件

  6.4 链下预言机服务接口

- HTTP API: POST /oracle/request - 创建结果请求
- WebSocket: 订阅事件结果更新
- 数据源配置: 定义从哪里获取真实结果(API/链上数据)

---

🌐 模块七: 链下服务 (event-rs-service)

📝 服务组件

- 事件监听与索引服务(GO)
- REST API 服务器
- WebSocket 推送服务
- 数据库(PostgreSQL 推荐)

🎯 核心功能清单

7.1 事件监听器

- 监听 EventCreated - 索引新事件
- 监听 OrderPlaced - 索引新订单
- 监听 OrderMatched - 更新订单状态
- 监听 OrderCancelled - 标记订单取消
- 监听 EventSettled - 更新事件结果
- 监听所有资金变动事件
- 监听所有费用事件
- 处理区块重组(Reorg)

  7.2 数据库设计

-- events 表
CREATE TABLE events (
event_id BIGINT PRIMARY KEY,
title VARCHAR(255),
description TEXT,
deadline TIMESTAMP,
status VARCHAR(50),
winning_outcome_id INT,
created_at TIMESTAMP
);

-- outcomes 表
CREATE TABLE outcomes (
outcome_id BIGINT,
event_id BIGINT,
name VARCHAR(255),
PRIMARY KEY (event_id, outcome_id)
);

-- orders 表
CREATE TABLE orders (
order_id BIGINT PRIMARY KEY,
user_address VARCHAR(42),
event_id BIGINT,
outcome_id BIGINT,
order_type VARCHAR(10), -- BUY/SELL
price INT,
amount BIGINT,
filled_amount BIGINT,
status VARCHAR(50),
created_at TIMESTAMP
);

-- positions 表
CREATE TABLE positions (
user_address VARCHAR(42),
event_id BIGINT,
outcome_id BIGINT,
amount BIGINT,
PRIMARY KEY (user_address, event_id, outcome_id)
);

7.3 REST API 端点

- GET /events - 事件列表(支持分页、过滤、排序)
- GET /events/:eventId - 事件详情
- GET /events/:eventId/orderbook - 订单簿快照
- GET /events/:eventId/trades - 成交历史
- GET /users/:address/orders - 用户订单
- GET /users/:address/positions - 用户持仓
- GET /users/:address/balances - 用户余额
- GET /users/:address/history - 用户交易历史
- GET /stats - 平台统计数据

  7.4 WebSocket 推送

- subscribe:events - 订阅新事件
- subscribe:orderbook:{eventId} - 订阅订单簿更新
- subscribe:trades:{eventId} - 订阅成交流
- subscribe:user:{address} - 订阅用户更新

---

🧪 模块八: 测试与质量保证

📝 测试文件结构

test/
├── unit/
│ ├── EventManager.t.sol
│ ├── EventPod.t.sol
│ ├── OrderBookManager.t.sol
│ ├── OrderBookPod.t.sol
│ ├── FundingManager.t.sol
│ ├── FundingPod.t.sol
│ ├── FeeVaultManager.t.sol
│ ├── FeeVaultPod.t.sol
│ └── AdminFeeVault.t.sol
├── integration/
│ ├── EndToEndTrading.t.sol
│ ├── EventSettlement.t.sol
│ └── MultiPodScenarios.t.sol
├── security/
│ ├── ReentrancyTests.t.sol
│ ├── AccessControlTests.t.sol
│ └── OracleManipulation.t.sol
└── utils/
└── TestHelpers.sol

🎯 测试清单

8.1 单元测试 (每个合约 >90% 覆盖率)

- EventManager 测试(15-20 个测试用例)
  - 事件创建成功/失败场景
  - Pod 白名单管理
  - 预言机注册
  - 权限控制
- EventPod 测试
  - 事件状态转换
  - 结算触发
  - 边界条件
- OrderBookPod 测试(已部分完成,需补充)
  - 撮合引擎各种价格场景
  - 部分成交逻辑
  - 持仓计算正确性
- FundingPod 测试 ⭐⭐⭐
  - 资金锁定/解锁
  - 撮合结算资金变化
  - 事件结算奖金分配
  - 提现功能
- FeeVaultPod 测试
  - 费用收取计算
  - 费用分配比例
  - 提取权限
- AdminFeeVault 测试

  - 多 Token 管理
  - 权限控制
  - 提现限额

    8.2 集成测试

- 完整交易流程:
  a. 用户入金
  b. 创建事件
  c. 下买单
  d. 下卖单
  e. 自动撮合
  f. 验证资金变化
  g. 验证费用收取
  h. 预言机提交结果
  i. 事件结算
  j. 获胜者奖金分配
  k. 用户提现
- 多 Pod 场景:
  - 同时多个事件在不同 Pod 运行
  - Pod 故障隔离测试
  - 跨 Pod 用户操作
- 极端场景:

  - 大额订单撮合
  - 订单簿深度测试(1000+ 订单)
  - Gas limit 边界测试
  - 并发下单压力测试

    8.3 安全测试

- 重入攻击测试
  - 提现重入
  - 撮合重入
  - 结算重入
- 权限绕过测试
  - 未授权调用 Pod 函数
  - 普通用户调用管理员函数
  - 伪造预言机结果
- 整数溢出测试
  - 大额资金计算
  - 持仓累加
  - 费用计算
- 预言机操纵测试
  - 重复提交结果
  - 过期结果提交
  - 无效结果 ID
- 前端运行攻击(Front-running)

  - 抢先下单
  - 抢先撤单
  - MEV 防护

    8.4 Gas 优化测试

- 生成 Gas 报告 forge test --gas-report
- 对比优化前后数据
- 关键函数 Gas 消耗基准:

  - placeOrder: < 150,000 gas
  - cancelOrder: < 50,000 gas
  - matchOrder: < 200,000 gas
  - settleEvent: < 500,000 gas (取决于持仓数量)

    8.5 测试工具集成

- Slither 静态分析 slither .
- Mythril 符号执行 myth analyze
- Echidna 模糊测试
- Foundry Fuzz Testing
- 测试覆盖率报告 forge coverage

---

🚀 模块九: 部署与运维

🎯 部署清单

9.1 部署脚本编写

- 创建 script/DeployCore.s.sol - 部署核心合约
- 创建 script/DeployPods.s.sol - 部署 Pod 合约
- 创建 script/SetupPermissions.s.sol - 配置权限
- 创建 script/Initialize.s.sol - 初始化配置

  9.2 部署顺序

1. 部署 AdminFeeVault
2. 部署 FeeVaultManager
3. 部署 FundingManager
4. 部署 OrderBookManager
5. 部署 EventManager
6. 部署多个 FeeVaultPod
7. 部署多个 FundingPod
8. 部署多个 OrderBookPod
9. 部署多个 EventPod
10. 配置 Manager → Pod 映射
11. 配置 Pod 白名单
12. 配置 AdminFeeVault 地址
13. 配置预言机地址
14. 转移 Owner 权限到多签钱包

9.3 测试网部署

- Sepolia 测试网部署
  - 配置 RPC 和私钥
  - 获取测试 ETH
  - 部署合约
  - 验证合约 forge verify-contract
- RootHash 测试网部署
  - 配置 RPC
  - 部署
  - Blockscout 验证
- 测试网测试

  - 完整流程测试
  - 前端集成测试
  - 用户 Beta 测试

    9.4 主网部署准备

- 安全审计报告通过
- Bug 赏金计划启动
- 多签钱包设置(3/5 或 4/7)
- Timelock 合约部署(48 小时延迟)
- 紧急暂停多签配置
- 保险协议集成(如 Nexus Mutual)
- 前端部署到 IPFS
- 域名和 DNS 配置

  9.5 监控与告警

- 链上监控: Tenderly/Defender
- 事件监听告警
- Gas price 监控
- 合约余额监控
- 异常交易检测
- 预言机状态监控

---

📚 模块十: 文档与工具

🎯 文档清单

10.1 技术文档

- 架构设计文档(已有 README.md,需扩展)
- 合约接口文档(NatSpec 注释)
- 数据流图
- 状态机图
- Gas 优化报告
- 安全审计报告

  10.2 开发者文档

- 快速开始指南
- 本地开发环境搭建
- 测试指南
- 部署指南
- 贡献指南
- API 参考手册

  10.3 用户文档

- 产品介绍
- 用户操作指南
- FAQ
- 风险提示
- 术语表

  10.4 工具开发

- 前端 SDK (TypeScript)
  - 合约交互封装
  - 类型定义
  - 工具函数
- 命令行工具
  - 合约部署工具
  - 事件查询工具
  - 批量操作工具
- Subgraph (The Graph)
  - 事件索引
  - GraphQL API

---

🎨 模块十一: 前端 Dapp

🎯 功能清单

11.1 页面结构

Dapp 前端
├── 首页 (Home)
│ ├── 平台介绍
│ ├── 热门事件
│ └── 数据统计
├── 市场页 (Markets)
│ ├── 事件列表
│ ├── 搜索/过滤
│ └── 分类导航
├── 事件详情页 (Event Detail)
│ ├── 事件信息
│ ├── 订单簿
│ ├── 交易界面
│ ├── 成交历史
│ └── 图表分析
├── 用户中心 (Portfolio)
│ ├── 资产总览
│ ├── 持仓列表
│ ├── 订单历史
│ ├── 交易历史
│ └── 入金/提现
├── 创建事件页 (Create) [管理员]
│ ├── 事件信息表单
│ ├── 结果选项配置
│ └── 预言机配置
└── 管理后台 (Admin)
├── 事件管理
├── 费用管理
├── 系统配置
└── 数据看板

11.2 核心组件

- Web3 钱包连接 (RainbowKit/ConnectKit)
- 订单簿组件(买卖盘展示)
- 下单表单(限价单)
- 持仓卡片
- 余额显示与管理
- 交易确认弹窗
- 加载状态与错误处理
- 实时数据更新(WebSocket)

  11.3 技术栈建议

- 框架: React 18+ / Next.js 14+
- Web3: wagmi + viem / ethers.js
- UI: TailwindCSS + shadcn/ui
- 状态: Zustand / Jotai
- 图表: Recharts / TradingView
- 实时通信: Socket.io-client

---

📊 进度跟踪

当前完成度

- ✅ OrderBookPod 撮合引擎: 100%
- ✅ OrderBookManager: 100%
- ⚠️ FundingPod 框架: 30% (核心功能缺失)
- ❌ EventManager/EventPod: 0%
- ❌ FeeVaultManager/Pod: 0%
- ❌ AdminFeeVault: 0%
- ❌ 预言机集成: 0%
- ❌ 链下服务: 0%
- ❌ 测试用例: 5% (仅空目录)
- ❌ 前端 Dapp: 0% (暂时不需要)

总体进度: ~15%
