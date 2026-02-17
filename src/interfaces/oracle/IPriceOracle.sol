// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPriceOracle
/// @notice Adapter interface for synchronous token price feeds used by FundingManager
/// @dev This is the adapter interface (owned by us), not an external oracle interface.
///      FundingManager imports this interface and calls it via typed reference.
///      Adapters implement this interface and internally handle oracle-specific logic.
interface IPriceOracle {
    /// @notice Get the USD price of a token
    /// @param token The token address
    /// @return price The price in USD (1e18 precision, e.g., 1e18 = $1.00)
    function getTokenPrice(address token) external view returns (uint256 price);
}
