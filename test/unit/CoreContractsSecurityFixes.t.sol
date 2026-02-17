// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {EventManager} from "../../src/core/EventManager.sol";
import {FeeVaultManager} from "../../src/core/FeeVaultManager.sol";
import {FundingManager} from "../../src/core/FundingManager.sol";
import {OrderBookManager} from "../../src/core/OrderBookManager.sol";
import {EventManagerProxy} from "../../src/core/proxies/EventManagerProxy.sol";
import {FeeVaultManagerProxy} from "../../src/core/proxies/FeeVaultManagerProxy.sol";
import {FundingManagerProxy} from "../../src/core/proxies/FundingManagerProxy.sol";
import {OrderBookManagerProxy} from "../../src/core/proxies/OrderBookManagerProxy.sol";
import {MockOracleAdapter} from "../../src/oracle/mock/MockOracleAdapter.sol";

contract FundingManagerHarness is FundingManager {
    function exposedDeposit(address user, address tokenAddress, uint256 amount, uint256 ethValue) external {
        _deposit(user, tokenAddress, amount, ethValue);
    }
}

contract CoreContractsSecurityFixesTest is Test {
    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");
    }

    function _deployFundingManagerWithManagers()
        internal
        returns (FundingManager fm, address orderBook, address eventMgr)
    {
        FundingManager fmImpl = new FundingManager();
        bytes memory fmInitData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy fmProxy = new FundingManagerProxy(address(fmImpl), fmInitData);
        fm = FundingManager(payable(address(fmProxy)));

        orderBook = makeAddr("orderBook");
        eventMgr = makeAddr("eventMgr");

        vm.prank(owner);
        fm.setOrderBookManager(orderBook);
        vm.prank(owner);
        fm.setEventManager(eventMgr);
    }

    function testInitialize_AllContracts_UUPSUpgradeableInit() public {
        // FundingManager
        FundingManager fmImpl = new FundingManager();
        bytes memory fmInitData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy fmProxy = new FundingManagerProxy(address(fmImpl), fmInitData);
        FundingManager fm = FundingManager(payable(address(fmProxy)));
        assertEq(fm.owner(), owner);

        // EventManager
        EventManager emImpl = new EventManager();
        bytes memory emInitData = abi.encodeWithSignature("initialize(address,address)", owner, address(0));
        EventManagerProxy emProxy = new EventManagerProxy(address(emImpl), emInitData);
        EventManager em = EventManager(address(emProxy));
        assertEq(em.owner(), owner);

        // OrderBookManager
        OrderBookManager obmImpl = new OrderBookManager();
        bytes memory obmInitData = abi.encodeWithSignature("initialize(address)", owner);
        OrderBookManagerProxy obmProxy = new OrderBookManagerProxy(address(obmImpl), obmInitData);
        OrderBookManager obm = OrderBookManager(address(obmProxy));
        assertEq(obm.owner(), owner);

        // FeeVaultManager
        FeeVaultManager fvmImpl = new FeeVaultManager();
        bytes memory fvmInitData = abi.encodeWithSignature("initialize(address)", owner);
        FeeVaultManagerProxy fvmProxy = new FeeVaultManagerProxy(address(fvmImpl), fvmInitData);
        FeeVaultManager fvm = FeeVaultManager(payable(address(fvmProxy)));
        assertEq(fvm.owner(), owner);

        // Verify upgrades are permitted for the owner
        FundingManager newFmImpl = new FundingManager();
        vm.prank(owner);
        fm.upgradeToAndCall(address(newFmImpl), "");

        EventManager newEmImpl = new EventManager();
        vm.prank(owner);
        em.upgradeToAndCall(address(newEmImpl), "");

        OrderBookManager newObmImpl = new OrderBookManager();
        vm.prank(owner);
        obm.upgradeToAndCall(address(newObmImpl), "");

        FeeVaultManager newFvmImpl = new FeeVaultManager();
        vm.prank(owner);
        fvm.upgradeToAndCall(address(newFvmImpl), "");
    }

    function testReceive_RevertsOnDirectETHTransfer() public {
        FundingManager fmImpl = new FundingManager();
        bytes memory fmInitData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy fmProxy = new FundingManagerProxy(address(fmImpl), fmInitData);
        FundingManager fm = FundingManager(payable(address(fmProxy)));

        vm.deal(address(this), 1 ether);
        (bool success, bytes memory returndata) = address(fm).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(
            returndata,
            abi.encodeWithSignature("Error(string)", "FundingManager: direct ETH transfers not supported")
        );
    }

    function testDeposit_ETHAmountMismatch_RevertsEarly() public {
        address user = makeAddr("user");
        FundingManagerHarness fmImpl = new FundingManagerHarness();
        bytes memory fmInitData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy fmProxy = new FundingManagerProxy(address(fmImpl), fmInitData);
        FundingManagerHarness fm = FundingManagerHarness(payable(address(fmProxy)));

        address nativeToken = fm.NATIVE_TOKEN();
        vm.prank(owner);
        fm.configureToken(nativeToken, 18, true);

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert("FundingManager: ETH amount mismatch");
        fm.exposedDeposit(user, nativeToken, 0.5 ether, 0.25 ether);
    }

    function testMarkEventSettled_CalledByOrderBookManager_Succeeds() public {
        (FundingManager fm, address orderBook, ) = _deployFundingManagerWithManagers();
        uint256 eventId = 1;

        vm.prank(orderBook);
        fm.registerEvent(eventId, 2);

        vm.prank(orderBook);
        fm.markEventSettled(eventId, 0);

        assertTrue(fm.isEventSettled(eventId));
    }

    function testMarkEventSettled_InvalidOutcome_Reverts() public {
        (FundingManager fm, address orderBook, ) = _deployFundingManagerWithManagers();
        uint256 eventId = 1;

        vm.prank(orderBook);
        fm.registerEvent(eventId, 2);

        vm.prank(orderBook);
        vm.expectRevert("FundingManager: invalid winning outcome");
        fm.markEventSettled(eventId, 5);
    }

    function testMarkEventSettled_UnregisteredEvent_Reverts() public {
        (FundingManager fm, address orderBook, ) = _deployFundingManagerWithManagers();

        vm.prank(orderBook);
        vm.expectRevert("FundingManager: event not registered");
        fm.markEventSettled(999, 0);
    }

    function testMarkEventSettled_ValidOutcome_SetsWinner() public {
        (FundingManager fm, address orderBook, ) = _deployFundingManagerWithManagers();
        uint256 eventId = 1;

        vm.prank(orderBook);
        fm.registerEvent(eventId, 3);

        vm.prank(orderBook);
        fm.markEventSettled(eventId, 2);

        assertTrue(fm.isEventSettled(eventId));
        assertEq(fm.eventWinningOutcome(eventId), 2);
    }

    function testMarkEventSettled_CalledByEventManager_Reverts() public {
        (FundingManager fm, address orderBook, address eventMgr) = _deployFundingManagerWithManagers();
        uint256 eventId = 1;

        vm.prank(orderBook);
        fm.registerEvent(eventId, 2);

        vm.prank(eventMgr);
        vm.expectRevert("FundingManager: only orderBookManager");
        fm.markEventSettled(eventId, 0);
    }

    function testGetTokenPrice_WithMockOracle_Returns1e18() public {
        (FundingManager fm, , ) = _deployFundingManagerWithManagers();
        address usdcToken = makeAddr("usdc");

        vm.prank(owner);
        fm.configureToken(usdcToken, 6, true);

        MockOracleAdapter mockOracleAdapter = new MockOracleAdapter();
        vm.prank(owner);
        fm.setPriceOracleAdapter(address(mockOracleAdapter));

        uint256 price = fm.getTokenPrice(usdcToken);
        assertEq(price, 1e18);
    }

    function testGetTokenPrice_WithoutOracle_Returns1e18() public {
        (FundingManager fm, , ) = _deployFundingManagerWithManagers();
        address usdcToken = makeAddr("usdc");

        vm.prank(owner);
        fm.configureToken(usdcToken, 6, true);

        uint256 price = fm.getTokenPrice(usdcToken);
        assertEq(price, 1e18);
    }

    function testNormalizeToUsd_WithPriceOracle_SameAsWithout() public {
        (FundingManager fm, , ) = _deployFundingManagerWithManagers();
        address usdcToken = makeAddr("usdc");
        uint256 amount = 100e6;

        vm.prank(owner);
        fm.configureToken(usdcToken, 6, true);

        uint256 withoutOracle = fm.normalizeToUsd(usdcToken, amount);

        MockOracleAdapter mockOracleAdapter = new MockOracleAdapter();
        vm.prank(owner);
        fm.setPriceOracleAdapter(address(mockOracleAdapter));

        uint256 withOracle = fm.normalizeToUsd(usdcToken, amount);

        assertEq(withoutOracle, withOracle);
        assertEq(withOracle, 100e18);
    }
}
