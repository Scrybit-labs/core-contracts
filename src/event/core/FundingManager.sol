// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./FundingManagerStorage.sol";

/**
 * @title FundingManager
 * @notice 资金管理器 - 负责资金池管理和 Pod 路由
 * @dev Manager 层负责协调,Pod 层负责执行
 */
contract FundingManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    FundingManagerStorage
{
    using SafeERC20 for IERC20;

    // ============ Modifiers ============

    /// @notice 仅白名单管理员可调用
    modifier onlyFundingPodWhitelister() {
        require(
            msg.sender == fundingPodWhitelister || msg.sender == owner(),
            "FundingManager: not the whitelister or owner"
        );
        _;
    }

    /// @notice 仅白名单 Pod 可调用
    modifier onlyWhitelistedPod(IFundingPod pod) {
        require(podIsWhitelistedForDeposit[pod], "FundingManager: pod not whitelisted");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param _initialOwner 初始所有者地址
     * @param _fundingPodWhitelister 白名单管理员地址
     */
    function initialize(address _initialOwner, address _fundingPodWhitelister) external initializer {
        __Ownable_init(_initialOwner);
        __Pausable_init();

        fundingPodWhitelister = _fundingPodWhitelister;
    }

    // ============ Pod 管理功能 ============

    /**
     * @notice 添加 Pod 到白名单
     * @param fundingPodsToWhitelist Pod 地址列表
     * @param thirdPartyTransfersForbiddenValues 是否禁止第三方转账(预留)
     */
    function addStrategiesToDepositWhitelist(
        IFundingPod[] calldata fundingPodsToWhitelist,
        bool[] calldata thirdPartyTransfersForbiddenValues
    ) external onlyFundingPodWhitelister {
        require(
            fundingPodsToWhitelist.length == thirdPartyTransfersForbiddenValues.length,
            "FundingManager: length mismatch"
        );

        for (uint256 i = 0; i < fundingPodsToWhitelist.length; i++) {
            IFundingPod pod = fundingPodsToWhitelist[i];
            require(address(pod) != address(0), "FundingManager: invalid pod address");
            require(!podIsWhitelistedForDeposit[pod], "FundingManager: pod already whitelisted");

            podIsWhitelistedForDeposit[pod] = true;

            // 添加到数组并记录索引
            podIndex[pod] = whitelistedPods.length;
            whitelistedPods.push(pod);

            emit PodWhitelisted(address(pod));
        }
    }

    /**
     * @notice 从白名单移除 Pod
     * @param fundingPodsToRemoveFromWhitelist Pod 地址列表
     */
    function removeStrategiesFromDepositWhitelist(
        IFundingPod[] calldata fundingPodsToRemoveFromWhitelist
    ) external onlyFundingPodWhitelister {
        for (uint256 i = 0; i < fundingPodsToRemoveFromWhitelist.length; i++) {
            IFundingPod pod = fundingPodsToRemoveFromWhitelist[i];
            require(podIsWhitelistedForDeposit[pod], "FundingManager: pod not whitelisted");

            podIsWhitelistedForDeposit[pod] = false;

            // 从数组中删除(swap-and-pop)
            uint256 index = podIndex[pod];
            uint256 lastIndex = whitelistedPods.length - 1;

            if (index != lastIndex) {
                IFundingPod lastPod = whitelistedPods[lastIndex];
                whitelistedPods[index] = lastPod;
                podIndex[lastPod] = index;
            }

            whitelistedPods.pop();
            delete podIndex[pod];

            emit PodRemovedFromWhitelist(address(pod));
        }
    }

    /**
     * @notice 检查 Pod 是否在白名单中
     * @param fundingPod Pod 地址
     * @return isWhitelisted 是否在白名单
     */
    function isPodWhitelisted(IFundingPod fundingPod) external view returns (bool) {
        return podIsWhitelistedForDeposit[fundingPod];
    }

    // ============ 入金功能 Deposit Functions ============

    /**
     * @notice ETH 入金到 Pod
     * @param fundingPod 目标 Pod
     * @return success 是否成功
     */
    function depositEthIntoPod(
        IFundingPod fundingPod
    ) external payable whenNotPaused onlyWhitelistedPod(fundingPod) nonReentrant returns (bool) {
        require(msg.value > 0, "FundingManager: deposit amount must be greater than 0");

        // 转账 ETH 到 Pod
        (bool sent, ) = address(fundingPod).call{value: msg.value}("");
        require(sent, "FundingManager: failed to send ETH");

        // 调用 Pod 的 deposit 函数 (传入真实用户地址)
        fundingPod.deposit(msg.sender, fundingPod.ETHAddress(), msg.value);

        return true;
    }

    /**
     * @notice ERC20 Token 入金到 Pod
     * @param fundingPod 目标 Pod
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function depositErc20IntoPod(
        IFundingPod fundingPod,
        IERC20 tokenAddress,
        uint256 amount
    ) external whenNotPaused onlyWhitelistedPod(fundingPod) nonReentrant {
        require(amount > 0, "FundingManager: deposit amount must be greater than 0");

        // 从用户转账到 Pod
        tokenAddress.safeTransferFrom(msg.sender, address(fundingPod), amount);

        // 调用 Pod 的 deposit 函数 (传入真实用户地址)
        fundingPod.deposit(msg.sender, address(tokenAddress), amount);
    }

    // ============ 提现功能 Withdraw Functions ============

    /**
     * @notice 从 Pod 提现
     * @param fundingPod Pod 地址
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function withdrawFromPod(
        IFundingPod fundingPod,
        address tokenAddress,
        uint256 amount
    ) external whenNotPaused onlyWhitelistedPod(fundingPod) nonReentrant {
        require(amount > 0, "FundingManager: withdraw amount must be greater than 0");

        // 调用 Pod 的 withdraw 函数 (传入真实用户地址)
        fundingPod.withdraw(msg.sender, tokenAddress, payable(msg.sender), amount);
    }

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
    ) external onlyOwner nonReentrant {
        require(recipient != address(0), "FundingManager: invalid recipient");
        require(amount > 0, "FundingManager: withdraw amount must be greater than 0");

        // 调用 Pod 的 withdraw 函数 (管理员指定接收者和金额)
        fundingPod.withdraw(recipient, tokenAddress, payable(recipient), amount);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取 Pod 总余额
     * @param fundingPod Pod 地址
     * @param tokenAddress Token 地址
     * @return balance 总余额
     */
    function getPodBalance(
        IFundingPod fundingPod,
        address tokenAddress
    ) external view returns (uint256) {
        return fundingPod.tokenBalances(tokenAddress);
    }

    /**
     * @notice 获取白名单 Pod 数量
     * @return count Pod 数量
     */
    function getWhitelistedPodCount() external view returns (uint256) {
        return whitelistedPods.length;
    }

    /**
     * @notice 获取指定索引的白名单 Pod
     * @param index Pod 索引
     * @return pod Pod 地址
     */
    function getWhitelistedPodAt(uint256 index) external view returns (IFundingPod) {
        require(index < whitelistedPods.length, "FundingManager: index out of bounds");
        return whitelistedPods[index];
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 更新白名单管理员
     * @param _fundingPodWhitelister 新管理员地址
     */
    function setFundingPodWhitelister(address _fundingPodWhitelister) external onlyOwner {
        require(_fundingPodWhitelister != address(0), "FundingManager: invalid address");
        fundingPodWhitelister = _fundingPodWhitelister;
    }

    // ============ 紧急控制 Emergency Control ============

    /**
     * @notice 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ 接收 ETH ============

    receive() external payable {}
}
