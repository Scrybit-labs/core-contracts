// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title DeploymentConstants
 * @notice Constants used throughout the deployment scripts
 */
library DeploymentConstants {
    // Oracle defaults
    uint256 constant DEFAULT_REQUEST_TIMEOUT = 1 hours;
    uint256 constant DEFAULT_MIN_CONFIRMATIONS = 1;
}
