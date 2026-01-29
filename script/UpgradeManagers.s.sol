// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/event/pod/EventManager.sol";
import "../src/event/pod/OrderBookManager.sol";
import "../src/event/pod/FundingManager.sol";
import "../src/event/pod/FeeVaultManager.sol";

/**
 * @title UpgradeManagers
 * @notice Script to upgrade Manager implementations using UUPS pattern
 * @dev Set environment variables before running:
 *      EVENT_MANAGER_PROXY - Address of EventManager proxy
 *      ORDER_BOOK_MANAGER_PROXY - Address of OrderBookManager proxy
 *      FUNDING_MANAGER_PROXY - Address of FundingManager proxy
 *      FEE_VAULT_MANAGER_PROXY - Address of FeeVaultManager proxy
 *
 * Note: The deployer must be the owner of the Manager contracts to upgrade (UUPS pattern)
 */
contract UpgradeManagers is Script {
    function run() external {
        address eventManagerProxyAddress = vm.envAddress("EVENT_MANAGER_PROXY");
        address orderBookManagerProxyAddress = vm.envAddress("ORDER_BOOK_MANAGER_PROXY");
        address fundingManagerProxyAddress = vm.envAddress("FUNDING_MANAGER_PROXY");
        address feeVaultManagerProxyAddress = vm.envAddress("FEE_VAULT_MANAGER_PROXY");

        vm.startBroadcast();

        console.log("=== Deploying New Implementations ===");

        EventManager newEventManagerImpl = new EventManager();
        OrderBookManager newOrderBookManagerImpl = new OrderBookManager();
        FundingManager newFundingManagerImpl = new FundingManager();
        FeeVaultManager newFeeVaultManagerImpl = new FeeVaultManager();

        console.log("EventManager new impl:", address(newEventManagerImpl));
        console.log("OrderBookManager new impl:", address(newOrderBookManagerImpl));
        console.log("FundingManager new impl:", address(newFundingManagerImpl));
        console.log("FeeVaultManager new impl:", address(newFeeVaultManagerImpl));
        console.log("");

        console.log("=== Upgrading Proxies (UUPS) ===");

        EventManager eventManager = EventManager(eventManagerProxyAddress);
        eventManager.upgradeToAndCall(address(newEventManagerImpl), "");
        console.log("EventManager upgraded");

        OrderBookManager orderBookManager = OrderBookManager(orderBookManagerProxyAddress);
        orderBookManager.upgradeToAndCall(address(newOrderBookManagerImpl), "");
        console.log("OrderBookManager upgraded");

        FundingManager fundingManager = FundingManager(payable(fundingManagerProxyAddress));
        fundingManager.upgradeToAndCall(address(newFundingManagerImpl), "");
        console.log("FundingManager upgraded");

        FeeVaultManager feeVaultManager = FeeVaultManager(payable(feeVaultManagerProxyAddress));
        feeVaultManager.upgradeToAndCall(address(newFeeVaultManagerImpl), "");
        console.log("FeeVaultManager upgraded");

        vm.stopBroadcast();

        console.log("=== Upgrade Complete ===");
    }
}
