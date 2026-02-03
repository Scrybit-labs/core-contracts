// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {FundingManager} from "../../../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../../../src/core/proxies/FundingManagerProxy.sol";

contract FundingManagerDeploy is Script {
    address public owner;
    FundingManager public fundingManager;
    FundingManagerProxy public fundingManagerProxy;

    function setUp(address deployer) public {
        owner = deployer;
    }
    function run() public {
        vm.startPrank(owner);

        fundingManager = new FundingManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        fundingManagerProxy = new FundingManagerProxy(address(fundingManager), initData);

        vm.stopPrank();
    }

    function getImplementationAndProxy() external view returns (address implementation, address proxy) {
        implementation = address(fundingManager);
        proxy = address(fundingManagerProxy);
    }
}
