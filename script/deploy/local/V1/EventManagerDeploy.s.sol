// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";

import {EventManager} from "../../../../src/core/EventManager.sol";
import {EventManagerProxy} from "../../../../src/core/proxies/EventManagerProxy.sol";
import {MockOracleAdapterProxy} from "../../../../src/oracle/mock/MockOracleAdapterProxy.sol";
import {MockOracleAdapterDeploy} from "../oracle/mock/MockOracleAdapterDeploy.s.sol";

contract EventManagerDeploy is Script {
    MockOracleAdapterDeploy public mockOracleAdapterDeploy;
    MockOracleAdapterProxy public mockOracleAdapterProxy;

    EventManager public eventManager;
    EventManagerProxy public eventManagerProxy;
    address public owner;

    function setUp(address deployer) public {
        mockOracleAdapterDeploy = new MockOracleAdapterDeploy();

        mockOracleAdapterDeploy.setUp(deployer);
        mockOracleAdapterDeploy.run();
        (, address proxy) = mockOracleAdapterDeploy.getImplementationAndProxy();
        mockOracleAdapterProxy = MockOracleAdapterProxy(payable(proxy));
        owner = deployer;
    }

    function run() public {
        vm.startPrank(owner);

        eventManager = new EventManager();
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            owner,
            address(mockOracleAdapterProxy)
        );
        eventManagerProxy = new EventManagerProxy(address(eventManager), initData);
        // Move linking to separate script
        // MockOracleAdapter(mockOracleAdapterProxy).setOracleConsumer(eventManagerProxy);

        vm.stopPrank();
    }

    function getImplementationAndProxy() external view returns (address implementation, address proxy) {
        implementation = address(eventManager);
        proxy = address(eventManagerProxy);
    }
}
