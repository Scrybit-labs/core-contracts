// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./FundingManagerStorage.sol";
import "../../interfaces/event/IPodFactory.sol";
import "../../interfaces/event/IPodDeployer.sol";

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

    /// @notice 仅 Factory 可调用
    modifier onlyFactory() {
        require(msg.sender == factory, "FundingManager: only factory");
        _;
    }

    // ============ Constructor & Initializer ============

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param _initialOwner 初始所有者地址
     */
    function initialize(address _initialOwner) external initializer {
        __Ownable_init(_initialOwner);
        __Pausable_init();
    }

    // ============ Pod 部署功能 Pod Deployment ============

    /**
     * @notice 部署 FundingPod (仅 Factory 可调用)
     * @param vendorId Vendor ID
     * @param vendorAddress Vendor 地址
     * @param orderBookPod OrderBookPod 地址
     * @param eventPod EventPod 地址
     * @return fundingPod FundingPod 地址
     */
    function deployFundingPod(
        uint256 vendorId,
        address vendorAddress,
        address orderBookPod,
        address eventPod
    ) external onlyFactory returns (address fundingPod) {
        require(vendorId > 0, "FundingManager: invalid vendorId");
        require(vendorToFundingPod[vendorId] == address(0), "FundingManager: pod already deployed");

        // 调用 PodDeployer
        fundingPod = IPodDeployer(podDeployer).deployFundingPod(
            vendorId,
            vendorAddress,
            address(this),  // fundingManager
            orderBookPod,
            eventPod
        );

        // 记录部署
        vendorToFundingPod[vendorId] = fundingPod;
        fundingPodIsDeployed[fundingPod] = true;

        emit FundingPodDeployed(vendorId, fundingPod);

        return fundingPod;
    }

    /**
     * @notice 获取 vendor 的 FundingPod 地址
     * @param vendorId Vendor ID
     * @return fundingPod FundingPod 地址
     */
    function getVendorFundingPod(uint256 vendorId) external view returns (address) {
        return vendorToFundingPod[vendorId];
    }

    /**
     * @notice 设置 PodDeployer 地址
     * @param _podDeployer PodDeployer 合约地址
     */
    function setPodDeployer(address _podDeployer) external onlyOwner {
        require(_podDeployer != address(0), "FundingManager: invalid podDeployer");
        podDeployer = _podDeployer;
    }

    // ============ Vendor-Based 入金/提现功能 ============

    /**
     * @notice ETH 入金到 Vendor 的 Pod
     * @param vendorId Vendor ID
     * @return success 是否成功
     */
    function depositEthIntoVendorPod(uint256 vendorId) external payable whenNotPaused nonReentrant returns (bool) {
        require(msg.value > 0, "FundingManager: deposit amount must be greater than 0");

        // 从内部映射获取 vendor 的 FundingPod
        address fundingPodAddress = vendorToFundingPod[vendorId];
        require(fundingPodAddress != address(0), "FundingManager: vendor not found");

        IFundingPod fundingPod = IFundingPod(fundingPodAddress);

        // 转账 ETH 到 Pod
        (bool sent, ) = address(fundingPod).call{value: msg.value}("");
        require(sent, "FundingManager: failed to send ETH");

        // 调用 Pod 的 deposit 函数 (pod will use msg.sender internally)
        fundingPod.deposit(fundingPod.ETHAddress(), msg.value);

        return true;
    }

    /**
     * @notice ERC20 Token 入金到 Vendor 的 Pod
     * @param vendorId Vendor ID
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function depositErc20IntoVendorPod(
        uint256 vendorId,
        IERC20 tokenAddress,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "FundingManager: deposit amount must be greater than 0");

        // 从内部映射获取 vendor 的 FundingPod
        address fundingPodAddress = vendorToFundingPod[vendorId];
        require(fundingPodAddress != address(0), "FundingManager: vendor not found");

        IFundingPod fundingPod = IFundingPod(fundingPodAddress);

        // 从用户转账到 Pod
        tokenAddress.safeTransferFrom(msg.sender, address(fundingPod), amount);

        // 调用 Pod 的 deposit 函数 (pod will use msg.sender internally)
        fundingPod.deposit(address(tokenAddress), amount);
    }

    /**
     * @notice 从 Vendor 的 Pod 提现
     * @param vendorId Vendor ID
     * @param tokenAddress Token 地址
     * @param amount 金额
     */
    function withdrawFromVendorPod(
        uint256 vendorId,
        address tokenAddress,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "FundingManager: withdraw amount must be greater than 0");

        // 从内部映射获取 vendor 的 FundingPod
        address fundingPodAddress = vendorToFundingPod[vendorId];
        require(fundingPodAddress != address(0), "FundingManager: vendor not found");

        IFundingPod fundingPod = IFundingPod(fundingPodAddress);

        // 调用 Pod 的 withdraw 函数 (pod will use msg.sender internally for user auth)
        fundingPod.withdraw(tokenAddress, payable(msg.sender), amount);
    }

    // ============ 查询功能 View Functions ============

    /**
     * @notice 获取 Vendor Pod 的总余额
     * @param vendorId Vendor ID
     * @param tokenAddress Token 地址
     * @return balance 总余额
     */
    function getVendorPodBalance(uint256 vendorId, address tokenAddress) external view returns (uint256) {
        address fundingPodAddress = vendorToFundingPod[vendorId];
        require(fundingPodAddress != address(0), "FundingManager: vendor not found");

        IFundingPod fundingPod = IFundingPod(fundingPodAddress);
        return fundingPod.tokenBalances(tokenAddress);
    }

    // ============ 管理功能 Admin Functions ============

    /**
     * @notice 设置 PodFactory 地址
     * @param _factory PodFactory 合约地址
     */
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "FundingManager: invalid factory");
        factory = _factory;
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
