// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/oracle/mock/MockOracle.sol";
import "../../src/oracle/mock/MockOracleAdapter.sol";
import "../../src/interfaces/oracle/IOracle.sol";

contract MockOracleConsumer is IOracleConsumer {
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

contract MockOracleAdapterTest is Test {
    function testMockOracleFlow() public {
        MockOracleConsumer consumer = new MockOracleConsumer();
        MockOracle mockOracle = new MockOracle();
        MockOracleAdapter adapterImpl = new MockOracleAdapter();
        bytes memory initData = abi.encodeCall(
            MockOracleAdapter.initialize,
            (address(this), address(consumer), address(mockOracle))
        );
        MockOracleAdapter adapter = MockOracleAdapter(
            payable(address(new ERC1967Proxy(address(adapterImpl), initData)))
        );
        adapter.setEventNumOutcomes(1, 3);
        mockOracle.setMockResult(1, 2);

        vm.prank(address(consumer));
        bytes32 requestId = adapter.requestEventResult(1, "test event");

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
