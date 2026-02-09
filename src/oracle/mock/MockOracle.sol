// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IMockOracleAdapter {
    function fulfillMockResult(uint256 requestId, uint8 outcome) external;
}

/**
 * @title MockOracle
 * @notice Simulates an external oracle with immediate callbacks.
 */
contract MockOracle is Ownable {
    mapping(uint256 => uint8) public mockResults;
    mapping(uint256 => bool) public hasResult;
    uint256 public requestCounter;

    constructor() Ownable(msg.sender) {}

    function setMockResult(uint256 eventId, uint8 outcome) external onlyOwner {
        mockResults[eventId] = outcome;
        hasResult[eventId] = true;
    }

    function requestResult(uint256 eventId, uint8 numOutcomes) external returns (uint256 requestId) {
        require(numOutcomes > 0, "MockOracle: invalid outcomes");

        requestCounter += 1;
        requestId = requestCounter;

        uint8 outcome = 0;
        if (hasResult[eventId]) {
            outcome = mockResults[eventId];
            require(outcome < numOutcomes, "MockOracle: outcome out of range");
        }

        IMockOracleAdapter(msg.sender).fulfillMockResult(requestId, outcome);
    }
}
