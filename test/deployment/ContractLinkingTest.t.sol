// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IMockOracleAdapter} from "../../src/interfaces/oracle/IMockOracleAdapter.sol";
import {IEventManager} from "../../src/interfaces/core/IEventManager.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract ContractLinkingTest is Test {
    Deploy public deployer;

    IMockOracleAdapter public mockOracleAdapter;
    IEventManager public eventManager;
    IFeeVaultManager public feeVaultManager;
    IFundingManager public fundingManager;
    IOrderBookManager public orderBookManager;

    address public owner;
    uint256 public ownerPrivateKey;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(ownerPrivateKey));

        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        mockOracleAdapter = IMockOracleAdapter(address(deployer.mockOracleAdapter()));
        eventManager = IEventManager(address(deployer.eventManager()));
        feeVaultManager = IFeeVaultManager(address(deployer.feeVaultManager()));
        fundingManager = IFundingManager(address(deployer.fundingManager()));
        orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));

        owner = deployer.initialOwner();
    }

    function test_EventManagerLinksToOracleAdapter() public view {
        assertTrue(eventManager.defaultOracleAdapter() != address(0));
        assertTrue(eventManager.defaultOracleAdapter() == address(mockOracleAdapter));
    }

    function test_EventManagerLinksToOrderBookManager() public view {
        assertEq(eventManager.orderBookManager(), address(orderBookManager));
    }

    function test_FeeVaultManagerLinksToOrderBookManager() public view {
        assertEq(feeVaultManager.orderBookManager(), address(orderBookManager));
    }

    function test_FeeVaultManagerLinksToFundingManager() public view {
        assertEq(feeVaultManager.fundingManager(), address(fundingManager));
    }

    function test_FundingManagerLinksToOrderBookManager() public view {
        assertEq(fundingManager.orderBookManager(), address(orderBookManager));
    }

    function test_FundingManagerLinksToEventManager() public view {
        assertEq(fundingManager.eventManager(), address(eventManager));
    }

    function test_FundingManagerLinksToFeeVaultManager() public view {
        assertEq(fundingManager.feeVaultManager(), address(feeVaultManager));
    }

    function test_FundingManagerLinksToPriceOracleAdapter() public view {
        assertEq(address(fundingManager.priceOracleAdapter()), address(mockOracleAdapter));
    }

    function test_OrderBookManagerLinksToEventManager() public view {
        assertEq(orderBookManager.eventManager(), address(eventManager));
    }

    function test_OrderBookManagerLinksToFundingManager() public view {
        assertEq(orderBookManager.fundingManager(), address(fundingManager));
    }

    function test_OrderBookManagerLinksToFeeVaultManager() public view {
        assertEq(orderBookManager.feeVaultManager(), address(feeVaultManager));
    }

    function test_OracleAdapterLinksBackToEventManager() public view {
        assertEq(mockOracleAdapter.oracleConsumer(), address(eventManager));
    }

    function test_AllManagersHaveCorrectOwner() public view {
        assertEq(IOwnable(address(eventManager)).owner(), owner);
        assertEq(IOwnable(address(feeVaultManager)).owner(), owner);
        assertEq(IOwnable(address(fundingManager)).owner(), owner);
        assertEq(IOwnable(address(orderBookManager)).owner(), owner);
    }
}
