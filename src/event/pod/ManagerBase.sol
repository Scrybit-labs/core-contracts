// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title ManagerBase
 * @notice Upgradeable base with ownership, pausing, and UUPS support
 */
abstract contract ManagerBase is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ===== Upgradeable storage gap =====
    uint256[50] private __gap;

    function __ManagerBase_init(address initialOwner) internal onlyInitializing {
        __Ownable_init(initialOwner);
        __Pausable_init();
    }

    function __ManagerBase_init_unchained(address) internal onlyInitializing {}

    /**
     * @notice Authorizes upgrade to new implementation
     * @dev Only owner can upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
