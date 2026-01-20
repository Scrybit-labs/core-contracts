// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IFeeVaultManager.sol";
import "../../interfaces/event/IFeeVaultPod.sol";

/**
 * @title FeeVaultManagerStorage
 * @notice FeeVaultManager 的存储层合约
 * @dev 存储与逻辑分离,便于合约升级
 */
abstract contract FeeVaultManagerStorage is IFeeVaultManager {
    // ============ Pod 管理 Pod Management ============

    /// @notice Pod 白名单映射
    mapping(IFeeVaultPod => bool) public podIsWhitelisted;

    /// @notice 事件到 Pod 的映射
    mapping(uint256 => IFeeVaultPod) public eventIdToPod;

    // ============ 预留升级空间 Upgrade Reserve ============

    /// @notice 预留 storage slots
    uint256[98] private __gap;
}
