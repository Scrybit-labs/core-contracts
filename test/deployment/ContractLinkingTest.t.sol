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

    function test_EventManagerLinksToOracleAdapter() public {
        assertTrue(eventManager.defaultOracleAdapter() != address(0));
    }

    function test_EventManagerLinksToOrderBookManager() public {
        assertEq(eventManager.orderBookManager(), address(orderBookManager));
    }

    function test_FeeVaultManagerLinksToOrderBookManager() public {
        assertEq(feeVaultManager.orderBookManager(), address(orderBookManager));
    }

    function test_FeeVaultManagerLinksToFundingManager() public {
        assertEq(feeVaultManager.fundingManager(), address(fundingManager));
    }

    function test_FundingManagerLinksToOrderBookManager() public {
        assertEq(fundingManager.orderBookManager(), address(orderBookManager));
    }

    function test_FundingManagerLinksToEventManager() public {
        assertEq(fundingManager.eventManager(), address(eventManager));
    }

    function test_FundingManagerLinksToFeeVaultManager() public {
        assertEq(fundingManager.feeVaultManager(), address(feeVaultManager));
    }

    function test_OrderBookManagerLinksToEventManager() public {
        assertEq(orderBookManager.eventManager(), address(eventManager));
    }

    function test_OrderBookManagerLinksToFundingManager() public {
        assertEq(orderBookManager.fundingManager(), address(fundingManager));
    }

    function test_OrderBookManagerLinksToFeeVaultManager() public {
        assertEq(orderBookManager.feeVaultManager(), address(feeVaultManager));
    }

    function test_OracleAdapterLinksBackToEventManager() public {
        assertEq(mockOracleAdapter.oracleConsumer(), address(eventManager));
    }

    function test_AllManagersHaveCorrectOwner() public {
        assertEq(IOwnable(address(eventManager)).owner(), owner);
        assertEq(IOwnable(address(feeVaultManager)).owner(), owner);
        assertEq(IOwnable(address(fundingManager)).owner(), owner);
        assertEq(IOwnable(address(orderBookManager)).owner(), owner);
    }
}
