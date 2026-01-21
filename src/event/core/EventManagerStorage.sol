// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IEventManager.sol";
import "../../interfaces/event/IEventPod.sol";

/**
 * @title EventManagerStorage
 * @notice EventManager 的存储层合约
 * @dev 存储与逻辑分离,便于合约升级
 */
abstract contract EventManagerStorage is IEventManager {
    // ============ 状态变量 State Variables ============

    /// @notice Pod 白名单映射
    mapping(IEventPod => bool) public podIsWhitelisted;

    /// @notice 白名单 Pod 数组(用于遍历)
    IEventPod[] public whitelistedPods;

    /// @notice Pod 在数组中的索引(用于快速删除)
    mapping(IEventPod => uint256) internal podIndex;

    /// @notice 事件 ID 到 Pod 的路由映射
    mapping(uint256 => IEventPod) public eventIdToPod;

    /// @notice 预言机授权映射
    mapping(address => bool) public authorizedOracles;

    /// @notice 下一个事件 ID(自增计数器)
    uint256 public nextEventId;

    /// @notice 当前用于负载均衡的 Pod 索引(轮询)
    uint256 internal currentPodIndex;

    /// @notice OrderBookManager 合约地址 (用于注册事件到订单簿)
    address public orderBookManager;

    /// @notice EventPod 到 OrderBookPod 的映射 (一对一)
    /// @dev 每个 EventPod 对应一个 OrderBookPod,实现完全隔离
    mapping(IEventPod => address) public eventPodToOrderBookPod;

    /// @notice 预留升级空间(OpenZeppelin 升级模式)
    /// @dev 减去已使用的 slot 数量: 9 个映射/变量 = 9 slots
    uint256[41] private _gap;
}
