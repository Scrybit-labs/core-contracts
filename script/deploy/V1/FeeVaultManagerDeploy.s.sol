// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";

import {FeeVaultManager} from "../../../src/core/FeeVaultManager.sol";

contract EventManagerDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
