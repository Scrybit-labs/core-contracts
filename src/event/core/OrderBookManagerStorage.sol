// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IOrderBookManager.sol";
import "../../interfaces/event/IOrderBookPod.sol";

abstract contract OrderBookManagerStorage is IOrderBookManager {
    /// @notice Pod 白名单映射
    mapping(IOrderBookPod => bool) public podIsWhitelisted;

    /// @notice 事件到 Pod 的映射
    mapping(uint256 => IOrderBookPod) public eventIdToPod;

    /// @notice 授权的调用者映射 (EventManager/EventPod 等)
    mapping(address => bool) public authorizedCallers;

    /// @notice 预留升级空间 (从 99 改为 98)
    uint256[98] private _gap;
}
