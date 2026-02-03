// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";

import {MockOracle} from "../../../../../src/oracle/mock/MockOracle.sol";
import {MockOracleAdapter} from "../../../../../src/oracle/mock/MockOracleAdapter.sol";
import {MockOracleAdapterProxy} from "../../../../../src/oracle/mock/MockOracleAdapterProxy.sol";

import {MockOracleDeploy} from "./MockOracleDeploy.s.sol";

contract MockOracleAdapterDeploy is Script {
    address public owner;
    MockOracle public mockOracle;
    MockOracleAdapter public mockOracleAdapter;
    MockOracleAdapterProxy public mockOracleAdapterProxy;

    MockOracleDeploy public mockOracleDeploy = new MockOracleDeploy();

    function setUp(address deployer) public {
        owner = deployer;
        mockOracleDeploy.setUp(deployer);
        mockOracleDeploy.run();
        mockOracle = mockOracleDeploy.getMockOracleInstance();
    }

    function run() public {
        vm.startPrank(owner);

        mockOracleAdapter = new MockOracleAdapter();
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", owner, address(mockOracle));
        mockOracleAdapterProxy = new MockOracleAdapterProxy(address(mockOracleAdapter), initData);

        vm.stopPrank();
    }

    function getImplementationAndProxy() external view returns (address implementation, address proxy) {
        implementation = address(mockOracleAdapter);
        proxy = address(mockOracleAdapterProxy);
    }
}
