// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/core/EventManager.sol";
import "../../src/interfaces/core/IEventManager.sol";
import "../../src/oracle/simple/SimpleOracleAdapter.sol";

contract OrderBookManagerStub {
    function registerEvent(uint256, uint8) external {}
    function deactivateEvent(uint256) external {}
    function settleEvent(uint256, uint8) external {}
}

contract EventManagerStatusTest is Test {
    function _buildOutcomes() internal pure returns (IEventManager.Outcome[] memory outcomes) {
        outcomes = new IEventManager.Outcome[](2);
        outcomes[0] = IEventManager.Outcome({name: "YES", description: "YES"});
        outcomes[1] = IEventManager.Outcome({name: "NO", description: "NO"});
    }

    function testUpdateEventStatusCannotSettle() public {
        OrderBookManagerStub orderBookManager = new OrderBookManagerStub();
        EventManager eventManagerImpl = new EventManager();
        bytes memory initData = abi.encodeCall(
            EventManager.initialize,
            (address(this), address(orderBookManager), address(0))
        );
        EventManager eventManager = EventManager(address(new ERC1967Proxy(address(eventManagerImpl), initData)));

        uint256 eventId = eventManager.createEvent(
            "Test Event",
            "Test Description",
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            _buildOutcomes(),
            keccak256("TEST")
        );

        eventManager.updateEventStatus(eventId, IEventManager.EventStatus.Active);

        vm.expectRevert("EventManager: invalid status transition");
        eventManager.updateEventStatus(eventId, IEventManager.EventStatus.Settled);
    }

    function testRequestOracleResultAfterDeadline() public {
        OrderBookManagerStub orderBookManager = new OrderBookManagerStub();
        SimpleOracleAdapter oracleAdapterImpl = new SimpleOracleAdapter();
        bytes memory oracleInitData = abi.encodeCall(SimpleOracleAdapter.initialize, (address(this), address(0)));
        SimpleOracleAdapter oracleAdapter = SimpleOracleAdapter(
            payable(address(new ERC1967Proxy(address(oracleAdapterImpl), oracleInitData)))
        );

        EventManager eventManagerImpl = new EventManager();
        bytes memory initData = abi.encodeCall(
            EventManager.initialize,
            (address(this), address(orderBookManager), address(oracleAdapter))
        );
        EventManager eventManager = EventManager(address(new ERC1967Proxy(address(eventManagerImpl), initData)));
        oracleAdapter.setOracleConsumer(address(eventManager));

        uint256 deadline = block.timestamp + 1 days;
        uint256 settlementTime = block.timestamp + 2 days;

        uint256 eventId = eventManager.createEvent(
            "Test Event",
            "Test Description",
            deadline,
            settlementTime,
            _buildOutcomes(),
            keccak256("TEST")
        );

        eventManager.updateEventStatus(eventId, IEventManager.EventStatus.Active);

        vm.warp(deadline + 1);
        bytes32 requestId = eventManager.requestOracleResult(eventId);

        assertTrue(requestId != bytes32(0));
        assertEq(eventManager.eventOracleRequests(eventId), requestId);
    }
}
