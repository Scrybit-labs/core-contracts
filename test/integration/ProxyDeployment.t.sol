// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/oracle/OracleManager.sol";
import "../../src/oracle/OracleAdapter.sol";
import "../../src/core/EventManager.sol";
import "../../src/core/OrderBookManager.sol";
import "../../src/core/FundingManager.sol";
import "../../src/core/FeeVaultManager.sol";

contract ProxyDeploymentTest is Test {
    function testProxyDeploymentWiring() public {
        address owner = address(this);

        OracleManager oracleManagerImpl = new OracleManager();
        bytes memory initData = abi.encodeCall(OracleManager.initialize, (owner));
        OracleManager oracleManager = OracleManager(address(new ERC1967Proxy(address(oracleManagerImpl), initData)));

        OracleAdapter oracleAdapterImpl = new OracleAdapter();
        initData = abi.encodeCall(OracleAdapter.initialize, (owner, address(0)));
        OracleAdapter oracleAdapter = OracleAdapter(
            payable(address(new ERC1967Proxy(address(oracleAdapterImpl), initData)))
        );

        EventManager eventManagerImpl = new EventManager();
        OrderBookManager orderBookManagerImpl = new OrderBookManager();
        FundingManager fundingManagerImpl = new FundingManager();
        FeeVaultManager feeVaultManagerImpl = new FeeVaultManager();

        bytes memory eventManagerInitData = abi.encodeCall(
            EventManager.initialize,
            (owner, address(0), address(oracleAdapter))
        );
        EventManager eventManager = EventManager(
            address(new ERC1967Proxy(address(eventManagerImpl), eventManagerInitData))
        );

        bytes memory feeVaultManagerInitData = abi.encodeCall(FeeVaultManager.initialize, (owner, address(0)));
        FeeVaultManager feeVaultManager = FeeVaultManager(
            payable(address(new ERC1967Proxy(address(feeVaultManagerImpl), feeVaultManagerInitData)))
        );

        bytes memory fundingManagerInitData = abi.encodeCall(
            FundingManager.initialize,
            (owner, address(0), address(eventManager))
        );
        FundingManager fundingManager = FundingManager(
            payable(address(new ERC1967Proxy(address(fundingManagerImpl), fundingManagerInitData)))
        );

        bytes memory orderBookManagerInitData = abi.encodeCall(
            OrderBookManager.initialize,
            (owner, address(eventManager), address(fundingManager), address(feeVaultManager))
        );
        OrderBookManager orderBookManager = OrderBookManager(
            address(new ERC1967Proxy(address(orderBookManagerImpl), orderBookManagerInitData))
        );

        eventManager.setOrderBookManager(address(orderBookManager));
        fundingManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setOrderBookManager(address(orderBookManager));

        oracleAdapter.setOracleConsumer(address(eventManager));
        oracleAdapter.addAuthorizedEventManager(address(eventManager));
        oracleAdapter.setRequestTimeout(2 days);
        oracleAdapter.setMinConfirmations(2);

        oracleManager.addOracleAdapter(address(oracleAdapter), "DefaultAdapter");
        oracleManager.setDefaultAdapter(address(oracleAdapter));

        assertEq(eventManager.orderBookManager(), address(orderBookManager));
        assertEq(fundingManager.orderBookManager(), address(orderBookManager));
        assertEq(feeVaultManager.orderBookManager(), address(orderBookManager));

        assertEq(oracleAdapter.oracleConsumer(), address(eventManager));
        assertTrue(oracleAdapter.authorizedEventManagers(address(eventManager)));
        assertEq(oracleAdapter.requestTimeout(), 2 days);
        assertEq(oracleAdapter.minConfirmations(), 2);
        assertEq(oracleManager.defaultAdapter(), address(oracleAdapter));
    }
}
