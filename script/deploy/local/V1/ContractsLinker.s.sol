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
        if (eventManager.defaultOracleAdapter() == address(0)) {
            eventManager.setDefaultOracleAdapter(address(mockOracleAdapter));
        }
        if (mockOracleAdapter.oracleConsumer() == address(0)) {
            mockOracleAdapter.setOracleConsumer(address(eventManager));
        }
        eventManager.setOrderBookManager(address(orderBookManager));

        // FeeVaultManager
        feeVaultManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setFundingManager(address(fundingManager));

        // FundingManager
        fundingManager.setOrderBookManager(address(orderBookManager));
        fundingManager.setEventManager(address(eventManager));
        fundingManager.setFeeVaultManager(address(feeVaultManager));

        // OrderBookManager
        orderBookManager.setEventManager(address(eventManager));
        orderBookManager.setFundingManager(address(fundingManager));
        orderBookManager.setFeeVaultManager(address(feeVaultManager));

        vm.stopPrank();
    }
}
