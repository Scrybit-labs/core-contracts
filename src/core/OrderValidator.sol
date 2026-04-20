// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OrderStruct, OrderKey} from "../library/OrderStruct.sol";
import {IOrderValidator} from "../interfaces/core/IOrderValidator.sol";

/**
 * @title OrderValidator
 * @notice Abstract contract for order validation and EIP712 signature verification
 * @dev Inherits from EIP712Upgradeable for typed structured data signing
 */
abstract contract OrderValidator is EIP712Upgradeable, IOrderValidator {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice Tick size for price alignment (10 basis points = 0.1%)
    uint128 public constant TICK_SIZE = 10;

    /// @notice Maximum price (10000 = 100%)
    uint128 public constant MAX_PRICE = 10000;

    // ============ State Variables ============

    /// @notice Tracks filled amount for each order (reserved for future off-chain order matching)
    mapping(OrderKey => uint128) public orderFilledAmount;

    /// @notice Tracks cancelled orders (reserved for future off-chain order matching)
    mapping(OrderKey => bool) public orderCancelled;

    // ============ Abstract Functions ============

    /**
     * @notice Get the outcome count for an event
     * @dev Must be implemented by inheriting contract to enable event/outcome validation
     * @param eventId The event ID to check
     * @return The number of outcomes for the event (0 if event not registered)
     */
    function _getEventOutcomeCount(uint256 eventId) internal view virtual returns (uint8);

    // ============ Validation Functions ============

    /**
     * @notice Validate order parameters
     * @dev Checks maker address, event/outcome validity, price alignment, amount, and expiry
     * @param maker The maker address
     * @param eventId The event ID
     * @param outcomeIndex The outcome index
     * @param price The order price (in basis points)
     * @param amount The order amount
     * @param expiry The order expiry timestamp (0 for no expiry)
     * @return valid Whether all validations passed
     * @return reason The reason for validation failure (empty if valid)
     */
    function validateOrderParams(
        address maker,
        uint256 eventId,
        uint8 outcomeIndex,
        uint128 price,
        uint128 amount,
        uint64 expiry
    ) external view returns (bool valid, string memory reason) {
        // Validate maker address
        if (maker == address(0)) {
            return (false, "Invalid maker address");
        }

        // Validate eventId and outcomeIndex
        uint8 outcomeCount = _getEventOutcomeCount(eventId);
        if (outcomeCount == 0) {
            return (false, "Event not registered");
        }
        if (outcomeIndex >= outcomeCount) {
            return (false, "Outcome index out of range");
        }

        // Validate price range
        if (price == 0 || price > MAX_PRICE) {
            return (false, "Price out of range");
        }

        // Validate price alignment with tick size
        if (price % TICK_SIZE != 0) {
            return (false, "Price not aligned with tick size");
        }

        // Validate amount
        if (amount == 0) {
            return (false, "Amount must be greater than zero");
        }

        // Validate expiry (if non-zero)
        if (expiry != 0 && expiry < block.timestamp) {
            return (false, "Order expired");
        }

        // All validations passed
        return (true, "");
    }

    /**
     * @notice Verify an order signature using EIP712
     * @dev Uses ECDSA to recover signer and compare with maker
     * @param order The order to verify
     * @param signature The signature bytes
     * @return True if the signature is valid
     */
    function verifyOrderSignature(OrderStruct.Order calldata order, bytes calldata signature)
        external
        view
        returns (bool)
    {
        bytes32 orderHash = getOrderHash(order);
        address signer = orderHash.recover(signature);
        return signer == order.maker;
    }

    /**
     * @notice Get the EIP712 hash of an order
     * @dev Uses _hashTypedDataV4 from EIP712Upgradeable
     * @param order The order to hash
     * @return The EIP712 hash
     */
    function getOrderHash(OrderStruct.Order calldata order) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                OrderStruct.ORDER_TYPEHASH, order.side, order.maker, order.expiry, order.salt, order.price, order.amount
            )
        );
        return _hashTypedDataV4(structHash);
    }

    // ============ Internal State Management ============

    /**
     * @notice Mark an order as partially or fully filled
     * @param key The order key
     * @param amount The amount filled
     */
    function _markFilled(OrderKey key, uint128 amount) internal {
        orderFilledAmount[key] += amount;
    }

    /**
     * @notice Mark an order as cancelled
     * @param key The order key
     */
    function _markCancelled(OrderKey key) internal {
        orderCancelled[key] = true;
    }

    /**
     * @notice Check if an order is cancelled
     * @param key The order key
     * @return True if the order is cancelled
     */
    function _isCancelled(OrderKey key) internal view returns (bool) {
        return orderCancelled[key];
    }

    /**
     * @notice Get the filled amount for an order
     * @param key The order key
     * @return The filled amount
     */
    function _getFilledAmount(OrderKey key) internal view returns (uint128) {
        return orderFilledAmount[key];
    }

    /**
     * @dev Storage gap for future upgrades
     * @notice Reserves 50 storage slots for future state variables
     */
    uint256[50] private __gap;
}
