// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {MockOracle} from "../../../src/oracle/mock/MockOracle.sol";
import {MockOracleAdapter} from "../../../src/oracle/mock/MockOracleAdapter.sol";
import {MockOracleAdapterProxy} from "../../../src/oracle/mock/MockOracleAdapterProxy.sol";

import {EventManager} from "../../../src/core/EventManager.sol";
import {EventManagerProxy} from "../../../src/core/proxies/EventManagerProxy.sol";
import {FeeVaultManager} from "../../../src/core/FeeVaultManager.sol";
import {FeeVaultManagerProxy} from "../../../src/core/proxies/FeeVaultManagerProxy.sol";
import {FundingManager} from "../../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../../src/core/proxies/FundingManagerProxy.sol";
import {OrderBookManager} from "../../../src/core/OrderBookManager.sol";
import {OrderBookManagerProxy} from "../../../src/core/proxies/OrderBookManagerProxy.sol";
import {OrderStorage} from "../../../src/core/OrderStorage.sol";
import {OrderStorageProxy} from "../../../src/core/proxies/OrderStorageProxy.sol";

import {IEventManager} from "../../../src/interfaces/core/IEventManager.sol";
import {IFeeVaultManager} from "../../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../../src/interfaces/core/IOrderBookManager.sol";

import {IMockOracleAdapter} from "../../../src/interfaces/oracle/IMockOracleAdapter.sol";

/// @notice 生产部署脚本，使用 vm.startBroadcast 广播真实交易
/// @dev 所有合约部署与链接在单一 broadcast 上下文中完成，替代 local/ 下基于 vm.startPrank 的测试脚本
contract DeployV1 is Script {
    function run() external {
        uint256 deployerPrivKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivKey);

        vm.startBroadcast(deployerPrivKey);

        // 1. 部署 MockOracle
        MockOracle mockOracle = new MockOracle();

        // 2. 部署 MockOracleAdapter + 代理
        MockOracleAdapter mockOracleAdapterImpl = new MockOracleAdapter();
        bytes memory oracleAdapterInitData =
            abi.encodeWithSignature("initialize(address,address)", owner, address(mockOracle));
        MockOracleAdapterProxy mockOracleAdapterProxy =
            new MockOracleAdapterProxy(address(mockOracleAdapterImpl), oracleAdapterInitData);

        // 3. 部署 EventManager + 代理
        EventManager eventManagerImpl = new EventManager();
        bytes memory eventManagerInitData =
            abi.encodeWithSignature("initialize(address,address)", owner, address(mockOracleAdapterProxy));
        EventManagerProxy eventManagerProxy = new EventManagerProxy(address(eventManagerImpl), eventManagerInitData);

        // 4. 部署 FeeVaultManager + 代理
        FeeVaultManager feeVaultManagerImpl = new FeeVaultManager();
        bytes memory feeVaultManagerInitData = abi.encodeWithSignature("initialize(address)", owner);
        FeeVaultManagerProxy feeVaultManagerProxy =
            new FeeVaultManagerProxy(address(feeVaultManagerImpl), feeVaultManagerInitData);

        // 5. 部署 FundingManager + 代理
        FundingManager fundingManagerImpl = new FundingManager();
        bytes memory fundingManagerInitData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy fundingManagerProxy =
            new FundingManagerProxy(address(fundingManagerImpl), fundingManagerInitData);

        // 6. 部署 OrderBookManager + 代理
        OrderBookManager orderBookManagerImpl = new OrderBookManager();
        bytes memory orderBookManagerInitData = abi.encodeWithSignature("initialize(address)", owner);
        OrderBookManagerProxy orderBookManagerProxy =
            new OrderBookManagerProxy(address(orderBookManagerImpl), orderBookManagerInitData);

        // 7. 部署 OrderStorage + 代理
        OrderStorage orderStorageImpl = new OrderStorage();
        bytes memory orderStorageInitData = abi.encodeWithSignature("initialize(address)", owner);
        OrderStorageProxy orderStorageProxy =
            new OrderStorageProxy(address(orderStorageImpl), orderStorageInitData);

        // 8. 建立合约间依赖关系
        IEventManager eventManager = IEventManager(address(eventManagerProxy));
        IFeeVaultManager feeVaultManager = IFeeVaultManager(address(feeVaultManagerProxy));
        IFundingManager fundingManager = IFundingManager(address(fundingManagerProxy));
        IOrderBookManager orderBookManager = IOrderBookManager(address(orderBookManagerProxy));
        IMockOracleAdapter mockOracleAdapter = IMockOracleAdapter(address(mockOracleAdapterProxy));

        eventManager.setDefaultOracleAdapter(address(mockOracleAdapter));
        eventManager.setOrderBookManager(address(orderBookManager));

        mockOracleAdapter.setOracleConsumer(address(eventManager));

        feeVaultManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setFundingManager(address(fundingManager));

        fundingManager.setOrderBookManager(address(orderBookManager));
        fundingManager.setEventManager(address(eventManager));
        fundingManager.setFeeVaultManager(address(feeVaultManager));
        fundingManager.setPriceOracleAdapter(address(mockOracleAdapter));

        orderBookManager.setEventManager(address(eventManager));
        orderBookManager.setFundingManager(address(fundingManager));
        orderBookManager.setFeeVaultManager(address(feeVaultManager));
        OrderBookManager(address(orderBookManagerProxy)).setOrderStorage(address(orderStorageProxy));

        OrderStorage(address(orderStorageProxy)).setOrderBookManager(address(orderBookManagerProxy));

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("Deployer:                  ", owner);
        console.log("MockOracle:                ", address(mockOracle));
        console.log("MockOracleAdapter (proxy): ", address(mockOracleAdapterProxy));
        console.log("EventManager (proxy):      ", address(eventManagerProxy));
        console.log("FeeVaultManager (proxy):   ", address(feeVaultManagerProxy));
        console.log("FundingManager (proxy):    ", address(fundingManagerProxy));
        console.log("OrderBookManager (proxy):  ", address(orderBookManagerProxy));
        console.log("OrderStorage (proxy):      ", address(orderStorageProxy));
    }
}
