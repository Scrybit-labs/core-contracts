// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/oracle/OracleManager.sol";
import "../src/oracle/OracleAdapter.sol";
import "../src/core/EventManager.sol";
import "../src/core/OrderBookManager.sol";
import "../src/core/FundingManager.sol";
import "../src/core/FeeVaultManager.sol";

import "./config/DeploymentConfig.sol";

/**
 * @title SimpleDeploy
 * @notice Direct-to-consumer deployment script (single manager instances)
 */
contract SimpleDeploy is Script, DeploymentConfig {
    NetworkConfig public config;

    function run() external {
        config = getConfig();

        vm.startBroadcast();

        console.log("=== Starting Simple Deployment ===");
        console.log("Network:", config.networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Initial Owner:", config.initialOwner);
        console.log("");

        // OracleManager (proxy)
        OracleManager oracleManagerImpl = new OracleManager();
        bytes memory initData = abi.encodeCall(OracleManager.initialize, (config.initialOwner));
        OracleManager oracleManager = OracleManager(address(new ERC1967Proxy(address(oracleManagerImpl), initData)));

        // OracleAdapter (proxy, consumer wired later)
        OracleAdapter oracleAdapterImpl = new OracleAdapter();
        initData = abi.encodeCall(OracleAdapter.initialize, (config.initialOwner, address(0)));
        OracleAdapter oracleAdapter = OracleAdapter(
            payable(address(new ERC1967Proxy(address(oracleAdapterImpl), initData)))
        );

        // Deploy Manager implementations
        console.log("Deploying Manager implementations...");
        EventManager eventManagerImpl = new EventManager();
        OrderBookManager orderBookManagerImpl = new OrderBookManager();
        FundingManager fundingManagerImpl = new FundingManager();
        FeeVaultManager feeVaultManagerImpl = new FeeVaultManager();

        console.log("EventManager implementation:", address(eventManagerImpl));
        console.log("OrderBookManager implementation:", address(orderBookManagerImpl));
        console.log("FundingManager implementation:", address(fundingManagerImpl));
        console.log("FeeVaultManager implementation:", address(feeVaultManagerImpl));
        console.log("");

        // Deploy proxies with initialization (UUPS pattern using ERC1967Proxy)
        console.log("Deploying Manager proxies...");

        bytes memory eventManagerInitData = abi.encodeCall(
            EventManager.initialize,
            (config.initialOwner, address(0), address(oracleAdapter))
        );
        EventManager eventManager = EventManager(
            address(new ERC1967Proxy(address(eventManagerImpl), eventManagerInitData))
        );

        bytes memory feeVaultManagerInitData = abi.encodeCall(
            FeeVaultManager.initialize,
            (config.initialOwner, address(0))
        );
        FeeVaultManager feeVaultManager = FeeVaultManager(
            payable(address(new ERC1967Proxy(address(feeVaultManagerImpl), feeVaultManagerInitData)))
        );

        bytes memory fundingManagerInitData = abi.encodeCall(
            FundingManager.initialize,
            (config.initialOwner, address(0), address(eventManager))
        );
        FundingManager fundingManager = FundingManager(
            payable(address(new ERC1967Proxy(address(fundingManagerImpl), fundingManagerInitData)))
        );

        bytes memory orderBookManagerInitData = abi.encodeCall(
            OrderBookManager.initialize,
            (config.initialOwner, address(eventManager), address(fundingManager), address(feeVaultManager))
        );
        OrderBookManager orderBookManager = OrderBookManager(
            address(new ERC1967Proxy(address(orderBookManagerImpl), orderBookManagerInitData))
        );

        console.log("EventManager proxy:", address(eventManager));
        console.log("OrderBookManager proxy:", address(orderBookManager));
        console.log("FundingManager proxy:", address(fundingManager));
        console.log("FeeVaultManager proxy:", address(feeVaultManager));
        console.log("");

        // Wire manager references
        eventManager.setOrderBookManager(address(orderBookManager));
        fundingManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setFundingManager(address(fundingManager));
        fundingManager.setFeeVaultManager(address(feeVaultManager));

        // Configure supported tokens (optional env vars)
        address usdt = vm.envOr("USDT_ADDRESS", address(0));
        if (usdt != address(0)) {
            fundingManager.configureToken(usdt, 6, true);
            console.log("Configured USDT:", usdt);
        }

        address usdc = vm.envOr("USDC_ADDRESS", address(0));
        if (usdc != address(0)) {
            fundingManager.configureToken(usdc, 6, true);
            console.log("Configured USDC:", usdc);
        }

        address dai = vm.envOr("DAI_ADDRESS", address(0));
        if (dai != address(0)) {
            fundingManager.configureToken(dai, 18, true);
            console.log("Configured DAI:", dai);
        }

        // Configure oracle
        oracleAdapter.setOracleConsumer(address(eventManager));
        oracleAdapter.addAuthorizedEventManager(address(eventManager));
        oracleAdapter.setRequestTimeout(config.requestTimeout);
        oracleAdapter.setMinConfirmations(config.minConfirmations);

        oracleManager.addOracleAdapter(address(oracleAdapter), "DefaultAdapter");
        oracleManager.setDefaultAdapter(address(oracleAdapter));

        for (uint256 i = 0; i < config.initialOracles.length; i++) {
            oracleManager.authorizeOracle(config.initialOracles[i], address(oracleAdapter));
            console.log("Added authorized oracle:", config.initialOracles[i]);
        }

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("Manager Proxies:");
        console.log("  EventManager:", address(eventManager));
        console.log("  OrderBookManager:", address(orderBookManager));
        console.log("  FundingManager:", address(fundingManager));
        console.log("  FeeVaultManager:", address(feeVaultManager));
        console.log("");
        console.log("Manager Implementations:");
        console.log("  EventManager impl:", address(eventManagerImpl));
        console.log("  OrderBookManager impl:", address(orderBookManagerImpl));
        console.log("  FundingManager impl:", address(fundingManagerImpl));
        console.log("  FeeVaultManager impl:", address(feeVaultManagerImpl));
        console.log("");
        console.log("Oracle System:");
        console.log("  OracleManager:", address(oracleManager));
        console.log("  OracleAdapter:", address(oracleAdapter));
        console.log("==========================================");
    }
}
