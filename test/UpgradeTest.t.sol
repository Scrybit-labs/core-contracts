// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../src/event/pod/EventManager.sol";
import "../src/event/pod/OrderBookManager.sol";
import "../src/event/pod/FundingManager.sol";
import "../src/event/pod/FeeVaultManager.sol";
import "../src/interfaces/event/IEventManager.sol";

contract EventManagerV2 is EventManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract OrderBookManagerV2 is OrderBookManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract FundingManagerV2 is FundingManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract FeeVaultManagerV2 is FeeVaultManager {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract UpgradeTest is Test {
    address internal owner;

    EventManager internal eventManager;
    OrderBookManager internal orderBookManager;
    FundingManager internal fundingManager;
    FeeVaultManager internal feeVaultManager;

    function setUp() public {
        owner = address(this);

        EventManager eventManagerImpl = new EventManager();
        OrderBookManager orderBookManagerImpl = new OrderBookManager();
        FundingManager fundingManagerImpl = new FundingManager();
        FeeVaultManager feeVaultManagerImpl = new FeeVaultManager();

        bytes memory eventManagerInitData = abi.encodeCall(
            EventManager.initialize,
            (owner, address(0), address(0xBEEF))
        );
        eventManager = EventManager(address(new ERC1967Proxy(address(eventManagerImpl), eventManagerInitData)));

        bytes memory feeVaultManagerInitData = abi.encodeCall(FeeVaultManager.initialize, (owner, address(0)));
        feeVaultManager = FeeVaultManager(payable(address(new ERC1967Proxy(address(feeVaultManagerImpl), feeVaultManagerInitData))));

        bytes memory fundingManagerInitData = abi.encodeCall(
            FundingManager.initialize,
            (owner, address(0), address(eventManager))
        );
        fundingManager = FundingManager(payable(address(new ERC1967Proxy(address(fundingManagerImpl), fundingManagerInitData))));

        bytes memory orderBookManagerInitData = abi.encodeCall(
            OrderBookManager.initialize,
            (owner, address(eventManager), address(fundingManager), address(feeVaultManager))
        );
        orderBookManager = OrderBookManager(address(new ERC1967Proxy(address(orderBookManagerImpl), orderBookManagerInitData)));

        eventManager.setOrderBookManager(address(orderBookManager));
        fundingManager.setOrderBookManager(address(orderBookManager));
        feeVaultManager.setOrderBookManager(address(orderBookManager));
    }

    function testUpgradePreservesStateAndAddsFunctionality() public {
        IEventManager.Outcome[] memory outcomes = new IEventManager.Outcome[](2);
        outcomes[0] = IEventManager.Outcome({name: "YES", description: "YES"});
        outcomes[1] = IEventManager.Outcome({name: "NO", description: "NO"});

        uint256 eventId = eventManager.createEvent(
            "Test Event",
            "Test Description",
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            outcomes
        );
        assertEq(eventId, 1);
        assertEq(eventManager.nextEventId(), 2);

        EventManagerV2 newEventManagerImpl = new EventManagerV2();
        OrderBookManagerV2 newOrderBookManagerImpl = new OrderBookManagerV2();
        FundingManagerV2 newFundingManagerImpl = new FundingManagerV2();
        FeeVaultManagerV2 newFeeVaultManagerImpl = new FeeVaultManagerV2();

        eventManager.upgradeToAndCall(address(newEventManagerImpl), "");
        orderBookManager.upgradeToAndCall(address(newOrderBookManagerImpl), "");
        fundingManager.upgradeToAndCall(address(newFundingManagerImpl), "");
        feeVaultManager.upgradeToAndCall(address(newFeeVaultManagerImpl), "");

        EventManagerV2 upgradedEventManager = EventManagerV2(address(eventManager));
        OrderBookManagerV2 upgradedOrderBookManager = OrderBookManagerV2(address(orderBookManager));
        FundingManagerV2 upgradedFundingManager = FundingManagerV2(payable(address(fundingManager)));
        FeeVaultManagerV2 upgradedFeeVaultManager = FeeVaultManagerV2(payable(address(feeVaultManager)));

        assertEq(upgradedEventManager.version(), 2);
        assertEq(upgradedOrderBookManager.version(), 2);
        assertEq(upgradedFundingManager.version(), 2);
        assertEq(upgradedFeeVaultManager.version(), 2);

        assertEq(upgradedEventManager.nextEventId(), 2);
        assertEq(upgradedOrderBookManager.nextOrderId(), 1);
        assertEq(upgradedFundingManager.orderBookManager(), address(orderBookManager));
        assertEq(upgradedFeeVaultManager.orderBookManager(), address(orderBookManager));
    }

    function testUpgradeOnlyOwner() public {
        EventManagerV2 newEventManagerImpl = new EventManagerV2();
        address attacker = address(0xBEEF);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker)
        );
        eventManager.upgradeToAndCall(address(newEventManagerImpl), "");
    }

    function testImplementationCannotBeInitialized() public {
        EventManager impl = new EventManager();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(owner, address(0), address(0));
    }
}
