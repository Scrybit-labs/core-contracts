// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OrderStruct} from "../../library/OrderStruct.sol";

/**
 * @title IOrderValidator
 * @notice Interface for order validation and EIP712 signature verification
 */
interface IOrderValidator {
    /**
     * @notice Validate order parameters
     * @param maker The maker address
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param price The order price
     * @param amount The order amount
     * @param expiry The expiry timestamp (0 for no expiry)
     * @return valid True if the order is valid
     * @return reason The reason for invalidity (empty if valid)
     */
    function validateOrderParams(
        address maker,
        uint256 eventId,
        uint8 outcomeIndex,
        uint128 price,
        uint128 amount,
        uint64 expiry
    ) external view returns (bool valid, string memory reason);

    /**
     * @notice Verify an order signature using EIP712
     * @param order The order to verify
     * @param signature The signature bytes
     * @return True if the signature is valid
     */
    function verifyOrderSignature(OrderStruct.Order calldata order, bytes calldata signature)
        external
        view
        returns (bool);

    /**
     * @notice Get the EIP712 hash of an order
     * @param order The order to hash
     * @return The EIP712 hash
     */
    function getOrderHash(OrderStruct.Order calldata order) external view returns (bytes32);
}
