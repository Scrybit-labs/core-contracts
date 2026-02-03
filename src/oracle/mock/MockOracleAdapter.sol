// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../interfaces/oracle/IOracle.sol";

interface IMockOracle {
    function requestResult(uint256 eventId, uint8 numOutcomes) external returns (uint256 requestId);
    function requestCounter() external view returns (uint256);
}

/**
 * @title MockOracleAdapter
 * @notice Adapter that wraps MockOracle and translates callbacks to EventManager.
 */
contract MockOracleAdapter is Initializable, OwnableUpgradeable, UUPSUpgradeable, IOracle {
    struct OracleRequest {
        bytes32 requestId;
        uint256 eventId;
        address requester;
        uint256 timestamp;
        bool fulfilled;
    }

    address public oracleConsumer;
    address public mockOracle;

    mapping(uint256 => uint256) public oracleRequestToEventId;
    mapping(uint256 => uint8) public eventNumOutcomes;
    mapping(uint256 => bytes32) public eventRequests;

    mapping(bytes32 => OracleRequest) private requests;
    mapping(uint256 => uint8) private eventResults;
    mapping(uint256 => bool) private eventResultConfirmed;

    uint256 public requestCounter;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _mockOracle) external initializer {
        __Ownable_init(initialOwner);
        mockOracle = _mockOracle;
    }

    function requestEventResult(
        uint256 eventId,
        string calldata eventDescription
    ) external override returns (bytes32 requestId) {
        require(oracleConsumer != address(0), "MockOracleAdapter: oracleConsumer not set");
        require(msg.sender == oracleConsumer, "MockOracleAdapter: only oracle consumer");
        require(mockOracle != address(0), "MockOracleAdapter: mockOracle not set");

        bytes32 existingRequestId = eventRequests[eventId];
        if (existingRequestId != bytes32(0) && !requests[existingRequestId].fulfilled) {
            revert ResultAlreadySubmitted(existingRequestId);
        }

        uint8 numOutcomes = eventNumOutcomes[eventId];
        require(numOutcomes > 0, "MockOracleAdapter: outcomes not set");

        uint256 expectedRequestId = IMockOracle(mockOracle).requestCounter() + 1;
        requestId = bytes32(expectedRequestId);

        requests[requestId] = OracleRequest({
            requestId: requestId,
            eventId: eventId,
            requester: msg.sender,
            timestamp: block.timestamp,
            fulfilled: false
        });

        oracleRequestToEventId[expectedRequestId] = eventId;
        eventRequests[eventId] = requestId;

        emit ResultRequested(requestId, eventId, msg.sender, eventDescription, block.timestamp);

        uint256 oracleRequestId = IMockOracle(mockOracle).requestResult(eventId, numOutcomes);
        require(oracleRequestId == expectedRequestId, "MockOracleAdapter: unexpected requestId");
        requestCounter += 1;
    }

    function submitResult(
        bytes32 requestId,
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyOwner {
        _recordResult(requestId, eventId, winningOutcomeIndex, proof);
    }

    function fulfillMockResult(uint256 requestId, uint8 winningOutcomeIndex) external {
        require(msg.sender == mockOracle, "MockOracleAdapter: only mock oracle");

        uint256 storedEventId = oracleRequestToEventId[requestId];
        require(storedEventId != 0, "MockOracleAdapter: unknown request");

        _recordResult(bytes32(requestId), storedEventId, winningOutcomeIndex, bytes(""));
    }

    function cancelRequest(bytes32 requestId) external override {
        OracleRequest storage request = requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert RequestNotFound(requestId);
        }
        require(msg.sender == request.requester || msg.sender == owner(), "MockOracleAdapter: unauthorized");
        if (request.fulfilled) {
            revert ResultAlreadySubmitted(requestId);
        }
        request.fulfilled = true;
    }

    function getRequest(
        bytes32 requestId
    ) external view override returns (uint256 eventId, address requester, uint256 timestamp, bool fulfilled) {
        OracleRequest storage request = requests[requestId];
        return (request.eventId, request.requester, request.timestamp, request.fulfilled);
    }

    function getEventResult(
        uint256 eventId
    ) external view override returns (uint8 winningOutcomeIndex, bool confirmed) {
        return (eventResults[eventId], eventResultConfirmed[eventId]);
    }

    function setOracleConsumer(address _oracleConsumer) external onlyOwner {
        require(_oracleConsumer != address(0), "MockOracleAdapter: invalid address");
        oracleConsumer = _oracleConsumer;
    }

    function setMockOracle(address _mockOracle) external onlyOwner {
        require(_mockOracle != address(0), "MockOracleAdapter: invalid address");
        mockOracle = _mockOracle;
    }

    function setEventNumOutcomes(uint256 eventId, uint8 numOutcomes) external onlyOwner {
        require(numOutcomes > 0, "MockOracleAdapter: invalid outcomes");
        eventNumOutcomes[eventId] = numOutcomes;
    }

    function _recordResult(bytes32 requestId, uint256 eventId, uint8 winningOutcomeIndex, bytes memory proof) internal {
        OracleRequest storage request = requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert RequestNotFound(requestId);
        }
        if (request.eventId != eventId) {
            revert InvalidEventId(eventId);
        }
        if (request.fulfilled) {
            revert ResultAlreadySubmitted(requestId);
        }

        request.fulfilled = true;
        eventResults[eventId] = winningOutcomeIndex;
        eventResultConfirmed[eventId] = true;

        emit ResultSubmitted(requestId, eventId, winningOutcomeIndex, msg.sender, block.timestamp);
        emit ResultConfirmed(eventId, winningOutcomeIndex, 1, block.timestamp);

        require(oracleConsumer != address(0), "MockOracleAdapter: oracleConsumer not set");
        IOracleConsumer(oracleConsumer).fulfillResult(eventId, winningOutcomeIndex, proof);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[50] private __gap;
}
