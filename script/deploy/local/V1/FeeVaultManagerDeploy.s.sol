// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";

import {FeeVaultManager} from "../../../../src/core/FeeVaultManager.sol";
import {FeeVaultManagerProxy} from "../../../../src/core/proxies/FeeVaultManagerProxy.sol";

contract FeeVaultManagerDeploy is Script {
    address public owner;
    FeeVaultManager public feeVaultManager;
    FeeVaultManagerProxy public feeVaultManagerProxy;

    function setUp(address deployer) public {
        owner = deployer;
    }

    function run() public {
        vm.startPrank(owner);

        feeVaultManager = new FeeVaultManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        feeVaultManagerProxy = new FeeVaultManagerProxy(address(feeVaultManager), initData);

        vm.stopPrank();
    }

    function getImplementationAndProxy() external view returns (address implementation, address proxy) {
        implementation = address(feeVaultManager);
        proxy = address(feeVaultManagerProxy);
    }
}
