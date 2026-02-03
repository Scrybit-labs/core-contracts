// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../interfaces/oracle/IOracle.sol";

/**
 * @title SimpleOracleAdapter
 * @notice Minimal standalone oracle adapter with manual result submission.
 */
contract SimpleOracleAdapter is Initializable, OwnableUpgradeable, UUPSUpgradeable, IOracle {
    struct OracleRequest {
        bytes32 requestId;
        uint256 eventId;
        address requester;
        uint256 timestamp;
        bool fulfilled;
    }

    address public oracleConsumer;

    mapping(address => bool) public authorizedOracles;
    mapping(uint256 => bytes32) public eventRequests;
    mapping(bytes32 => uint256) public requestToEvent;
    mapping(bytes32 => OracleRequest) private requests;
    mapping(uint256 => uint8) private eventResults;
    mapping(uint256 => bool) private eventResultConfirmed;

    uint256 public requestCounter;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _oracleConsumer) external initializer {
        __Ownable_init(initialOwner);
        oracleConsumer = _oracleConsumer;
    }

    modifier onlyAuthorizedOracle() {
        if (!authorizedOracles[msg.sender]) {
            revert UnauthorizedOracle(msg.sender);
        }
        _;
    }

    function requestEventResult(
        uint256 eventId,
        string calldata eventDescription
    ) external override returns (bytes32 requestId) {
        require(oracleConsumer != address(0), "SimpleOracleAdapter: oracleConsumer not set");
        require(msg.sender == oracleConsumer, "SimpleOracleAdapter: only oracle consumer");

        bytes32 existingRequestId = eventRequests[eventId];
        if (existingRequestId != bytes32(0) && !requests[existingRequestId].fulfilled) {
            revert ResultAlreadySubmitted(existingRequestId);
        }

        requestCounter += 1;
        requestId = keccak256(abi.encodePacked(address(this), eventId, requestCounter));

        requests[requestId] = OracleRequest({
            requestId: requestId,
            eventId: eventId,
            requester: msg.sender,
            timestamp: block.timestamp,
            fulfilled: false
        });

        eventRequests[eventId] = requestId;
        requestToEvent[requestId] = eventId;

        emit ResultRequested(requestId, eventId, msg.sender, eventDescription, block.timestamp);
    }

    function submitResult(
        bytes32 requestId,
        uint256 eventId,
        uint8 winningOutcomeIndex,
        bytes calldata proof
    ) external override onlyAuthorizedOracle {
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

        require(oracleConsumer != address(0), "SimpleOracleAdapter: oracleConsumer not set");
        IOracleConsumer(oracleConsumer).fulfillResult(eventId, winningOutcomeIndex, proof);
    }

    function cancelRequest(bytes32 requestId) external override {
        OracleRequest storage request = requests[requestId];
        if (request.requestId == bytes32(0)) {
            revert RequestNotFound(requestId);
        }
        require(msg.sender == request.requester || msg.sender == owner(), "SimpleOracleAdapter: unauthorized");
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

    function addAuthorizedOracle(address oracle) external onlyOwner {
        require(oracle != address(0), "SimpleOracleAdapter: invalid address");
        authorizedOracles[oracle] = true;
    }

    function removeAuthorizedOracle(address oracle) external onlyOwner {
        authorizedOracles[oracle] = false;
    }

    function setOracleConsumer(address _oracleConsumer) external onlyOwner {
        require(_oracleConsumer != address(0), "SimpleOracleAdapter: invalid address");
        oracleConsumer = _oracleConsumer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[50] private __gap;
}
