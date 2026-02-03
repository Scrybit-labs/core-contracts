// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";

import {MockOracle} from "../../../../../src/oracle/mock/MockOracle.sol";

contract MockOracleDeploy is Script {
    MockOracle public mockOracle;
    address public deployer;

    function setUp(address _deployer) public {
        deployer = _deployer;
    }

    function run() public {
        vm.prank(deployer);
        mockOracle = new MockOracle();
    }

    function getMockOracleInstance() external view returns (MockOracle _mockOracle) {
        _mockOracle = mockOracle;
    }
}
