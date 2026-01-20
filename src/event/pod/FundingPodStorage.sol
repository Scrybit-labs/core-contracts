// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IFundingPod.sol";

/**
 * @title FundingPodStorage
 * @notice FundingPod 的存储层合约
 * @dev 存储与逻辑分离,便于合约升级
 */
abstract contract FundingPodStorage is IFundingPod {
    // ============ 常量 Constants ============

    /// @notice ETH 地址表示
    address public constant ETHAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // ============ 基础状态变量 Basic State Variables ============

    /// @notice FundingManager 合约地址
    address public fundingManager;

    /// @notice OrderBookPod 合约地址(用于调用权限控制)
    address public orderBookPod;

    /// @notice EventPod 合约地址(用于调用权限控制)
    address public eventPod;

    /// @notice 支持的 Token 列表
    address[] public SupportTokens;

    /// @notice Token 是否支持映射
    mapping(address => bool) public IsSupportToken;

    // ============ 余额管理 Balance Management ============

    /// @notice Pod 总 Token 余额: token => totalBalance
    mapping(address => uint256) public tokenBalances;

    /// @notice 用户可用余额: user => token => balance
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    /// @notice 用户锁定余额: user => token => eventId => outcomeId => lockedAmount
    /// @dev 四层嵌套映射,精确跟踪每个订单的锁定资金
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256)))) public lockedBalances;

    /// @notice 用户在事件中的总锁定额: user => token => eventId => totalLocked
    /// @dev 用于优化查询,避免遍历所有 outcomeId
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userEventTotalLocked;

    // ============ 事件奖金池管理 Event Prize Pool ============

    /// @notice 事件奖金池: eventId => token => prizePool
    mapping(uint256 => mapping(address => uint256)) public eventPrizePool;

    /// @notice 事件结算状态: eventId => settled
    mapping(uint256 => bool) public eventSettled;

    /// @notice 事件获胜结果: eventId => winningOutcomeId
    mapping(uint256 => uint256) public eventWinningOutcome;

    // ============ 统计信息 Statistics ============

    /// @notice 总入金量: token => totalDeposited
    mapping(address => uint256) public totalDeposited;

    /// @notice 总提现量: token => totalWithdrawn
    mapping(address => uint256) public totalWithdrawn;

    /// @notice 预留升级空间(OpenZeppelin 升级模式)
    /// @dev 减去已使用的 slot 数量: 约 14 个映射/变量
    uint256[86] private _gap;
}
