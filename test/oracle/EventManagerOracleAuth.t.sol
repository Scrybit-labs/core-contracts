// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/core/EventManager.sol";

contract EventManagerOracleAuthTest is Test {
    function testAuthorizeAndDeauthorizeOracle() public {
        EventManager eventManagerImpl = new EventManager();
        bytes memory initData = abi.encodeCall(EventManager.initialize, (address(this), address(0), address(0)));
        EventManager eventManager = EventManager(address(new ERC1967Proxy(address(eventManagerImpl), initData)));

        address oracle = address(0x1234);

        eventManager.addAuthorizedOracleAdapter(oracle);
        assertTrue(eventManager.authorizedOracleAdapters(oracle));

        eventManager.removeAuthorizedOracleAdapter(oracle);
        assertTrue(!eventManager.authorizedOracleAdapters(oracle));
    }
}
