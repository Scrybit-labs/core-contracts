// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/oracle/OracleManager.sol";
import "../src/oracle/OracleAdapter.sol";
import "../src/event/pod/EventPod.sol";
import "../src/event/pod/OrderBookPod.sol";
import "../src/event/pod/FundingPod.sol";
import "../src/event/pod/FeeVaultPod.sol";

import "./config/DeploymentConfig.sol";

/**
 * @title SimpleDeploy
 * @notice Direct-to-consumer deployment script (single pod instances)
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
        OracleAdapter oracleAdapter =
            OracleAdapter(payable(address(new ERC1967Proxy(address(oracleAdapterImpl), initData))));

        // Deploy Pod implementations
        console.log("Deploying Pod implementations...");
        EventPod eventPodImpl = new EventPod();
        OrderBookPod orderBookPodImpl = new OrderBookPod();
        FundingPod fundingPodImpl = new FundingPod();
        FeeVaultPod feeVaultPodImpl = new FeeVaultPod();

        console.log("EventPod implementation:", address(eventPodImpl));
        console.log("OrderBookPod implementation:", address(orderBookPodImpl));
        console.log("FundingPod implementation:", address(fundingPodImpl));
        console.log("FeeVaultPod implementation:", address(feeVaultPodImpl));
        console.log("");

        // Deploy proxies with initialization (UUPS pattern using ERC1967Proxy)
        console.log("Deploying Pod proxies...");

        bytes memory eventPodInitData = abi.encodeCall(
            EventPod.initialize,
            (config.initialOwner, address(0), address(oracleAdapter))
        );
        EventPod eventPod = EventPod(address(new ERC1967Proxy(address(eventPodImpl), eventPodInitData)));

        bytes memory feeVaultPodInitData = abi.encodeCall(FeeVaultPod.initialize, (config.initialOwner, address(0)));
        FeeVaultPod feeVaultPod =
            FeeVaultPod(payable(address(new ERC1967Proxy(address(feeVaultPodImpl), feeVaultPodInitData))));

        bytes memory fundingPodInitData = abi.encodeCall(
            FundingPod.initialize,
            (config.initialOwner, address(0), address(eventPod))
        );
        FundingPod fundingPod =
            FundingPod(payable(address(new ERC1967Proxy(address(fundingPodImpl), fundingPodInitData))));

        bytes memory orderBookPodInitData = abi.encodeCall(
            OrderBookPod.initialize,
            (config.initialOwner, address(eventPod), address(fundingPod), address(feeVaultPod))
        );
        OrderBookPod orderBookPod =
            OrderBookPod(address(new ERC1967Proxy(address(orderBookPodImpl), orderBookPodInitData)));

        console.log("EventPod proxy:", address(eventPod));
        console.log("OrderBookPod proxy:", address(orderBookPod));
        console.log("FundingPod proxy:", address(fundingPod));
        console.log("FeeVaultPod proxy:", address(feeVaultPod));
        console.log("");

        // Wire pod references
        eventPod.setOrderBookPod(address(orderBookPod));
        fundingPod.setOrderBookPod(address(orderBookPod));
        feeVaultPod.setOrderBookPod(address(orderBookPod));

        // Configure oracle
        oracleAdapter.setOracleConsumer(address(eventPod));
        oracleAdapter.addAuthorizedEventPod(address(eventPod));
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
        console.log("Pod Proxies:");
        console.log("  EventPod:", address(eventPod));
        console.log("  OrderBookPod:", address(orderBookPod));
        console.log("  FundingPod:", address(fundingPod));
        console.log("  FeeVaultPod:", address(feeVaultPod));
        console.log("");
        console.log("Pod Implementations:");
        console.log("  EventPod impl:", address(eventPodImpl));
        console.log("  OrderBookPod impl:", address(orderBookPodImpl));
        console.log("  FundingPod impl:", address(fundingPodImpl));
        console.log("  FeeVaultPod impl:", address(feeVaultPodImpl));
        console.log("");
        console.log("Oracle System:");
        console.log("  OracleManager:", address(oracleManager));
        console.log("  OracleAdapter:", address(oracleAdapter));
        console.log("==========================================");
    }
}
