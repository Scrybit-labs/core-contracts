// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOracle} from "./IOracle.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/**
 * @title IMockOracleAdapter
 * @notice MockOracleAdapter 接口
 */
interface IMockOracleAdapter is IOracle, IPriceOracle {
    /**
     * @notice 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _mockOracle MockOracle 地址
     */
    function initialize(address initialOwner, address _mockOracle) external;

    /**
     * @notice 获取 oracleConsumer 地址
     */
    function oracleConsumer() external view returns (address);

    /**
     * @notice 获取 mockOracle 地址
     */
    function mockOracle() external view returns (address);

    /**
     * @notice 获取请求对应的事件 ID
     * @param requestId MockOracle 请求 ID
     */
    function oracleRequestToEventId(uint256 requestId) external view returns (uint256);

    /**
     * @notice 获取事件结果数量
     * @param eventId 事件 ID
     */
    function eventNumOutcomes(uint256 eventId) external view returns (uint8);

    /**
     * @notice 获取事件请求 ID
     * @param eventId 事件 ID
     */
    function eventRequests(uint256 eventId) external view returns (bytes32);

    /**
     * @notice 获取请求计数器
     */
    function requestCounter() external view returns (uint256);

    /**
     * @notice MockOracle 回调结果
     * @param requestId MockOracle 请求 ID
     * @param winningOutcomeIndex 获胜结果索引
     */
    function fulfillMockResult(uint256 requestId, uint8 winningOutcomeIndex) external;

    /**
     * @notice 设置 oracleConsumer 地址
     * @param _oracleConsumer 新地址
     */
    function setOracleConsumer(address _oracleConsumer) external;

    /**
     * @notice 设置 mockOracle 地址
     * @param _mockOracle 新地址
     */
    function setMockOracle(address _mockOracle) external;

    /**
     * @notice 设置事件结果数量
     * @param eventId 事件 ID
     * @param numOutcomes 结果数量
     */
    function setEventNumOutcomes(uint256 eventId, uint8 numOutcomes) external;
}
