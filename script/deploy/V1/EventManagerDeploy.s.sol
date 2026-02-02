// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";

import {EventManager} from "../../../src/core/EventManager.sol";

contract EventManagerDeploy is Script {
    EventManager public eventManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

    function getEventManagerV1Salt() public pure returns (string memory salt) {
        salt = "event_manager_v1_deploy";
    }

    function calcEventManagerV1Address() public pure returns (address result) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff)));
    }
}
