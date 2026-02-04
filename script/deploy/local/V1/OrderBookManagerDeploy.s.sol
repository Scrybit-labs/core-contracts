// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";

import {OrderBookManager} from "../../../../src/core/OrderBookManager.sol";
import {OrderBookManagerProxy} from "../../../../src/core/proxies/OrderBookManagerProxy.sol";

contract OrderBookManagerDeploy is Script {
    address public owner;
    OrderBookManager public orderBookManager;
    OrderBookManagerProxy public orderBookManagerProxy;

    function setUp(address deployer) public {
        owner = deployer;
    }
    function run() public {
        vm.startPrank(owner);

        orderBookManager = new OrderBookManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        orderBookManagerProxy = new OrderBookManagerProxy(address(orderBookManager), initData);

        vm.stopPrank();
    }

    function getImplementationAndProxy() external view returns (address implementation, address proxy) {
        implementation = address(orderBookManager);
        proxy = address(orderBookManagerProxy);
    }
}
