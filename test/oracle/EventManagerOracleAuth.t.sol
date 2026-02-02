// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/core/EventManager.sol";

contract EventManagerOracleAuthTest is Test {
    function testAuthorizeAndDeauthorizeOracle() public {
        EventManager eventManager = new EventManager();
        eventManager.initialize(address(this), address(0), address(0));

        address oracle = address(0x1234);

        eventManager.addAuthorizedOracleAdapter(oracle);
        assertTrue(eventManager.authorizedOracleAdapters(oracle));

        eventManager.removeAuthorizedOracleAdapter(oracle);
        assertTrue(!eventManager.authorizedOracleAdapters(oracle));
    }
}
