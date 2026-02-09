// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library EfficientHashLib {
    function hash(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }
}
