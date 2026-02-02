// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/oracle/simple/SimpleOracleAdapter.sol";
import "../../src/interfaces/oracle/IOracle.sol";

contract SimpleOracleConsumer is IOracleConsumer {
    uint256 public lastEventId;
    uint8 public lastOutcome;
    bytes public lastProof;
    uint256 public callCount;

    function fulfillResult(uint256 eventId, uint8 winningOutcomeIndex, bytes calldata proof) external override {
        lastEventId = eventId;
        lastOutcome = winningOutcomeIndex;
        lastProof = proof;
        callCount += 1;
    }
}

contract SimpleOracleAdapterTest is Test {
    function testSimpleOracleFlow() public {
        SimpleOracleConsumer consumer = new SimpleOracleConsumer();
        SimpleOracleAdapter adapter = new SimpleOracleAdapter();
        adapter.initialize(address(this), address(consumer));
        adapter.addAuthorizedOracle(address(this));

        vm.prank(address(consumer));
        bytes32 requestId = adapter.requestEventResult(1, "test event");

        adapter.submitResult(requestId, 1, 2, "");

        assertEq(consumer.lastEventId(), 1);
        assertEq(consumer.lastOutcome(), 2);
        assertEq(consumer.callCount(), 1);

        (uint256 eventId, address requester, uint256 timestamp, bool fulfilled) = adapter.getRequest(requestId);
        assertEq(eventId, 1);
        assertEq(requester, address(consumer));
        assertTrue(timestamp > 0);
        assertTrue(fulfilled);

        (uint8 outcome, bool confirmed) = adapter.getEventResult(1);
        assertEq(outcome, 2);
        assertTrue(confirmed);
    }
}
