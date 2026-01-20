// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IFundingPod.sol";

/**
 * @title IFundingManager
 * @notice 资金管理器接口 - 负责资金池管理和 Pod 路由
 * @dev Manager 层负责协调,Pod 层负责执行
 */
interface IFundingManager {
    // ============ 事件 Events ============

    /// @notice Pod 添加到白名单事件
    event PodWhitelisted(address indexed pod);

    /// @notice Pod 从白名单移除事件
    event PodRemovedFromWhitelist(address indexed pod);

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param fundingPodsToWhitelist Pod 地址列表
     * @param thirdPartyTransfersForbiddenValues 是否禁止第三方转账(预留)
     */
    function addStrategiesToDepositWhitelist(
        IFundingPod[] calldata fundingPodsToWhitelist,
        bool[] calldata thirdPartyTransfersForbiddenValues
    ) external;

    /**
     * @notice 从白名单移除 Pod
     * @param fundingPodsToRemoveFromWhitelist Pod 地址列表
     */
    function removeStrategiesFromDepositWhitelist(IFundingPod[] calldata fundingPodsToRemoveFromWhitelist) external;

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param fundingPod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IFundingPod fundingPod) external view returns (bool);

    // ============ 入金功能 Deposit Functions ============

    /**
     * @notice ETH 入金到 Pod
     * @param fundingPod 目标 Pod
     * @return success 是否成功
     */
    function depositEthIntoPod(IFundingPod fundingPod) external payable returns (bool);

    /**
     * @notice ERC20 Token 入金到 Pod
     * @param fundingPod 目标 Pod
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function depositErc20IntoPod(IFundingPod fundingPod, IERC20 tokenAddress, uint256 amount) external;

    // ============ 提现功能 Withdraw Functions ============

    /**
     * @notice 从 Pod 提现
     * @param fundingPod Pod 地址
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function withdrawFromPod(IFundingPod fundingPod, address tokenAddress, uint256 amount) external;

    /**
     * @notice 紧急提现(管理员功能)
     * @param fundingPod Pod 地址
     * @param tokenAddress Token 地址
     * @param recipient 接收地址
     * @param amount 金额
     */
    function emergencyWithdraw(
        IFundingPod fundingPod,
        address tokenAddress,
        address recipient,
        uint256 amount
    ) external;

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取 Pod 总余额
     * @param fundingPod Pod 地址
     * @param tokenAddress Token 地址
     * @return balance 总余额
     */
    function getPodBalance(IFundingPod fundingPod, address tokenAddress) external view returns (uint256);
}
