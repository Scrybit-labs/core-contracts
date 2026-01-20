// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IFundingManager.sol";

/**
 * @title FundingManagerStorage
 * @notice FundingManager 的存储层合约
 * @dev 存储与逻辑分离,便于合约升级
 */
abstract contract FundingManagerStorage is IFundingManager {
    // ============ 状态变量 State Variables ============

    /// @notice Pod 白名单管理员(预留,当前由 owner 管理)
    address public fundingPodWhitelister;

    /// @notice Pod 白名单映射
    mapping(IFundingPod => bool) public podIsWhitelistedForDeposit;

    /// @notice 白名单 Pod 数组(用于遍历)
    IFundingPod[] public whitelistedPods;

    /// @notice Pod 在数组中的索引(用于快速删除)
    mapping(IFundingPod => uint256) internal podIndex;

    /// @notice 紧急提现配置映射(预留)
    mapping(IFundingPod => bool) public emergencyWithdrawEnabled;

    /// @notice 预留升级空间(OpenZeppelin 升级模式)
    /// @dev 减去已使用的 slot 数量: 5 个映射/变量
    uint256[45] private _gap;
}
