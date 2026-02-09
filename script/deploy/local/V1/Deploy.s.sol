// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {MockOracleAdapterDeploy} from "../oracle/mock/MockOracleAdapterDeploy.s.sol";
import {EventManagerDeploy} from "./EventManagerDeploy.s.sol";
import {FeeVaultManagerDeploy} from "./FeeVaultManagerDeploy.s.sol";
import {FundingManagerDeploy} from "./FundingManagerDeploy.s.sol";
import {OrderBookManagerDeploy} from "./OrderBookManagerDeploy.s.sol";

import {IMockOracleAdapter} from "../../../../src/interfaces/oracle/IMockOracleAdapter.sol";
import {IEventManager} from "../../../../src/interfaces/core/IEventManager.sol";
import {IFeeVaultManager} from "../../../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../../../src/interfaces/core/IOrderBookManager.sol";
import {ContractsLinker} from "./ContractsLinker.s.sol";

contract Deploy is Script {
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public initialOwner;

    MockOracleAdapterDeploy public mockOracleAdapterDeploy;
    IMockOracleAdapter public mockOracleAdapter;

    EventManagerDeploy public eventManagerDeploy;
    IEventManager public eventManager;

    FeeVaultManagerDeploy public feeVaultManagerDeploy;
    IFeeVaultManager public feeVaultManager;

    FundingManagerDeploy public fundingManagerDeploy;
    IFundingManager public fundingManager;

    OrderBookManagerDeploy public orderBookManagerDeploy;
    IOrderBookManager public orderBookManager;

    ContractsLinker public linker;

    function setUp() public {
        uint256 ownerPrivKey = vm.envUint("SEPOLIA_PRIV_KEY");
        initialOwner = vm.addr(ownerPrivKey);

        vm.deal(initialOwner, 10000e18);

        mockOracleAdapterDeploy = new MockOracleAdapterDeploy();
        eventManagerDeploy = new EventManagerDeploy();
        feeVaultManagerDeploy = new FeeVaultManagerDeploy();
        fundingManagerDeploy = new FundingManagerDeploy();
        orderBookManagerDeploy = new OrderBookManagerDeploy();

        linker = new ContractsLinker();

        mockOracleAdapterDeploy.setUp(initialOwner);
        eventManagerDeploy.setUp(initialOwner);
        feeVaultManagerDeploy.setUp(initialOwner);
        fundingManagerDeploy.setUp(initialOwner);
        orderBookManagerDeploy.setUp(initialOwner);
    }

    function run() public {
        _deployOracleAdapter();
        _deployEventManager();
        _deployFeeVaultManager();
        _deployFundingManager();
        _deployOrderBookManager();
        _linkContractDeps();
    }

    function _deployOracleAdapter() internal {
        mockOracleAdapterDeploy.run();
        (, address proxy) = mockOracleAdapterDeploy.getImplementationAndProxy();
        mockOracleAdapter = IMockOracleAdapter(proxy);
    }
    function _deployEventManager() internal {
        eventManagerDeploy.run();
        (, address proxy) = eventManagerDeploy.getImplementationAndProxy();
        eventManager = IEventManager(proxy);
    }
    function _deployFeeVaultManager() internal {
        feeVaultManagerDeploy.run();
        (, address proxy) = feeVaultManagerDeploy.getImplementationAndProxy();
        feeVaultManager = IFeeVaultManager(proxy);
    }
    function _deployFundingManager() internal {
        fundingManagerDeploy.run();
        (, address proxy) = fundingManagerDeploy.getImplementationAndProxy();
        fundingManager = IFundingManager(proxy);
    }
    function _deployOrderBookManager() internal {
        orderBookManagerDeploy.run();
        (, address proxy) = orderBookManagerDeploy.getImplementationAndProxy();
        orderBookManager = IOrderBookManager(proxy);
    }

    function _linkContractDeps() internal {
        linker.setUp(
            initialOwner,
            address(mockOracleAdapter),
            address(eventManager),
            address(feeVaultManager),
            address(fundingManager),
            address(orderBookManager)
        );
        linker.run();
    }
}
