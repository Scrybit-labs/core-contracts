// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script} from "forge-std/Script.sol";

import {IMockOracleAdapter} from "../../../../src/interfaces/oracle/IMockOracleAdapter.sol";
import {IEventManager} from "../../../../src/interfaces/core/IEventManager.sol";
import {IFeeVaultManager} from "../../../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../../../src/interfaces/core/IOrderBookManager.sol";

contract ContractsLinker is Script {
    address public owner;

    IMockOracleAdapter public mockOracleAdapter;
    IEventManager public eventManager;
    IFeeVaultManager public feeVaultManager;
    IFundingManager public fundingManager;
    IOrderBookManager public orderBookManager;

    function setUp(
        address _owner,
        address _mockOracleAdapter,
        address _eventManager,
        address _feeVaultManager,
        address _fundingManager,
        address _orderBookManager
    ) public {
        owner = _owner;

        mockOracleAdapter = IMockOracleAdapter(_mockOracleAdapter);
        eventManager = IEventManager(_eventManager);
        feeVaultManager = IFeeVaultManager(_feeVaultManager);
        fundingManager = IFundingManager(_fundingManager);
        orderBookManager = IOrderBookManager(_orderBookManager);
    }

    function run() public {
        vm.startPrank(owner);

        // EventManager and OracleAdapter
        if (eventManager.defaultOracleAdapter() != address(mockOracleAdapter)) {
            eventManager.setDefaultOracleAdapter(address(mockOracleAdapter));
        }
        if (mockOracleAdapter.oracleConsumer() != address(eventManager)) {
            mockOracleAdapter.setOracleConsumer(address(eventManager));
        }
        if (eventManager.orderBookManager() == address(0)) {
            eventManager.setOrderBookManager(address(orderBookManager));
        } else {
            _ensureAddress(eventManager.orderBookManager(), address(orderBookManager));
        }

        // FeeVaultManager
        if (feeVaultManager.orderBookManager() == address(0)) {
            feeVaultManager.setOrderBookManager(address(orderBookManager));
        } else {
            _ensureAddress(feeVaultManager.orderBookManager(), address(orderBookManager));
        }
        if (feeVaultManager.fundingManager() == address(0)) {
            feeVaultManager.setFundingManager(address(fundingManager));
        } else {
            _ensureAddress(feeVaultManager.fundingManager(), address(fundingManager));
        }

        // FundingManager
        if (fundingManager.orderBookManager() == address(0)) {
            fundingManager.setOrderBookManager(address(orderBookManager));
        } else {
            _ensureAddress(fundingManager.orderBookManager(), address(orderBookManager));
        }
        if (fundingManager.eventManager() == address(0)) {
            fundingManager.setEventManager(address(eventManager));
        } else {
            _ensureAddress(fundingManager.eventManager(), address(eventManager));
        }
        if (fundingManager.feeVaultManager() == address(0)) {
            fundingManager.setFeeVaultManager(address(feeVaultManager));
        } else {
            _ensureAddress(fundingManager.feeVaultManager(), address(feeVaultManager));
        }
        if (address(fundingManager.priceOracleAdapter()) != address(mockOracleAdapter)) {
            fundingManager.setPriceOracleAdapter(address(mockOracleAdapter));
        }

        // OrderBookManager
        if (orderBookManager.eventManager() == address(0)) {
            orderBookManager.setEventManager(address(eventManager));
        } else {
            _ensureAddress(orderBookManager.eventManager(), address(eventManager));
        }
        if (orderBookManager.fundingManager() == address(0)) {
            orderBookManager.setFundingManager(address(fundingManager));
        } else {
            _ensureAddress(orderBookManager.fundingManager(), address(fundingManager));
        }
        if (orderBookManager.feeVaultManager() == address(0)) {
            orderBookManager.setFeeVaultManager(address(feeVaultManager));
        } else {
            _ensureAddress(orderBookManager.feeVaultManager(), address(feeVaultManager));
        }

        vm.stopPrank();
    }

    function _ensureAddress(address current, address expected) internal pure {
        require(current == expected, "ContractsLinker: address mismatch");
    }
}
