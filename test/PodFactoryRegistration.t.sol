// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PodFactory} from "../src/event/factory/PodFactory.sol";
import {IPodFactory} from "../src/interfaces/event/IPodFactory.sol";

contract DummyImplementation {}

contract MockPodDeployer {
    mapping(uint256 => address) public podImplementations;

    function setPodImplementation(uint256 podType, address implementation) external {
        podImplementations[podType] = implementation;
    }

    function getPodImplementation(uint256 podType) external view returns (address implementation) {
        return podImplementations[podType];
    }

    function predictPodAddress(uint256 vendorId, uint256 podType) external view returns (address predictedAddress) {
        bytes32 salt = keccak256(abi.encodePacked(vendorId, podType));
        return Clones.predictDeterministicAddress(podImplementations[podType], salt, address(this));
    }
}

contract MockEventManager {
    address public podDeployer;
    address public lastCaller;
    uint256 public lastVendorId;
    address public lastVendorAddress;
    uint256 public deployCalls;

    constructor(address _podDeployer) {
        podDeployer = _podDeployer;
    }

    function deployEventPod(uint256 vendorId, address vendorAddress) external returns (address eventPod) {
        lastCaller = msg.sender;
        lastVendorId = vendorId;
        lastVendorAddress = vendorAddress;
        deployCalls++;
        eventPod = MockPodDeployer(podDeployer).predictPodAddress(vendorId, 0);
    }
}

contract MockOrderBookManager {
    address public podDeployer;
    address public lastCaller;
    uint256 public lastVendorId;
    address public lastVendorAddress;
    address public lastEventPod;
    address public lastFundingPod;
    address public lastFeeVaultPod;
    uint256 public deployCalls;

    constructor(address _podDeployer) {
        podDeployer = _podDeployer;
    }

    function deployOrderBookPod(
        uint256 vendorId,
        address vendorAddress,
        address eventPod,
        address fundingPod,
        address feeVaultPod
    ) external returns (address orderBookPod) {
        lastCaller = msg.sender;
        lastVendorId = vendorId;
        lastVendorAddress = vendorAddress;
        lastEventPod = eventPod;
        lastFundingPod = fundingPod;
        lastFeeVaultPod = feeVaultPod;
        deployCalls++;
        orderBookPod = MockPodDeployer(podDeployer).predictPodAddress(vendorId, 1);
    }
}

contract MockFundingManager {
    address public podDeployer;
    address public lastCaller;
    uint256 public lastVendorId;
    address public lastVendorAddress;
    address public lastOrderBookPod;
    address public lastEventPod;
    uint256 public deployCalls;

    constructor(address _podDeployer) {
        podDeployer = _podDeployer;
    }

    function deployFundingPod(
        uint256 vendorId,
        address vendorAddress,
        address orderBookPod,
        address eventPod
    ) external returns (address fundingPod) {
        lastCaller = msg.sender;
        lastVendorId = vendorId;
        lastVendorAddress = vendorAddress;
        lastOrderBookPod = orderBookPod;
        lastEventPod = eventPod;
        deployCalls++;
        fundingPod = MockPodDeployer(podDeployer).predictPodAddress(vendorId, 3);
    }
}

contract MockFeeVaultManager {
    address public podDeployer;
    address public lastCaller;
    uint256 public lastVendorId;
    address public lastVendorAddress;
    address public lastFeeRecipient;
    address public lastOrderBookPod;
    uint256 public deployCalls;

    constructor(address _podDeployer) {
        podDeployer = _podDeployer;
    }

    function deployFeeVaultPod(
        uint256 vendorId,
        address vendorAddress,
        address feeRecipient,
        address orderBookPod
    ) external returns (address feeVaultPod) {
        lastCaller = msg.sender;
        lastVendorId = vendorId;
        lastVendorAddress = vendorAddress;
        lastFeeRecipient = feeRecipient;
        lastOrderBookPod = orderBookPod;
        deployCalls++;
        feeVaultPod = MockPodDeployer(podDeployer).predictPodAddress(vendorId, 2);
    }
}

contract PodFactoryRegistrationTest is Test {
    PodFactory private factory;
    MockPodDeployer private deployer;
    MockEventManager private eventManager;
    MockOrderBookManager private orderBookManager;
    MockFundingManager private fundingManager;
    MockFeeVaultManager private feeVaultManager;

    function setUp() public {
        deployer = new MockPodDeployer();
        deployer.setPodImplementation(0, address(new DummyImplementation()));
        deployer.setPodImplementation(1, address(new DummyImplementation()));
        deployer.setPodImplementation(2, address(new DummyImplementation()));
        deployer.setPodImplementation(3, address(new DummyImplementation()));

        eventManager = new MockEventManager(address(deployer));
        orderBookManager = new MockOrderBookManager(address(deployer));
        fundingManager = new MockFundingManager(address(deployer));
        feeVaultManager = new MockFeeVaultManager(address(deployer));

        PodFactory impl = new PodFactory();
        bytes memory initData = abi.encodeCall(PodFactory.initialize, (address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        factory = PodFactory(address(proxy));
        factory.setPodDeployer(address(deployer));
        factory.setEventManager(address(eventManager));
        factory.setOrderBookManager(address(orderBookManager));
        factory.setFundingManager(address(fundingManager));
        factory.setFeeVaultManager(address(feeVaultManager));
    }

    function test_registerVendor_deploysViaManagers_andStoresPodSet() public {
        address vendor = address(0x1000);
        address feeRecipient = address(0x2000);

        uint256 vendorId = factory.registerVendor(vendor, feeRecipient);
        assertEq(vendorId, 1);

        address expectedEventPod = _predictPodAddress(vendorId, 0);
        address expectedOrderBookPod = _predictPodAddress(vendorId, 1);
        address expectedFeeVaultPod = _predictPodAddress(vendorId, 2);
        address expectedFundingPod = _predictPodAddress(vendorId, 3);

        assertEq(eventManager.lastCaller(), address(factory));
        assertEq(eventManager.lastVendorId(), vendorId);
        assertEq(eventManager.lastVendorAddress(), vendor);
        assertEq(eventManager.deployCalls(), 1);

        assertEq(orderBookManager.lastCaller(), address(factory));
        assertEq(orderBookManager.lastVendorId(), vendorId);
        assertEq(orderBookManager.lastVendorAddress(), vendor);
        assertEq(orderBookManager.lastEventPod(), expectedEventPod);
        assertEq(orderBookManager.lastFundingPod(), expectedFundingPod);
        assertEq(orderBookManager.lastFeeVaultPod(), expectedFeeVaultPod);
        assertEq(orderBookManager.deployCalls(), 1);

        assertEq(fundingManager.lastCaller(), address(factory));
        assertEq(fundingManager.lastVendorId(), vendorId);
        assertEq(fundingManager.lastVendorAddress(), vendor);
        assertEq(fundingManager.lastOrderBookPod(), expectedOrderBookPod);
        assertEq(fundingManager.lastEventPod(), expectedEventPod);
        assertEq(fundingManager.deployCalls(), 1);

        assertEq(feeVaultManager.lastCaller(), address(factory));
        assertEq(feeVaultManager.lastVendorId(), vendorId);
        assertEq(feeVaultManager.lastVendorAddress(), vendor);
        assertEq(feeVaultManager.lastFeeRecipient(), feeRecipient);
        assertEq(feeVaultManager.lastOrderBookPod(), expectedOrderBookPod);
        assertEq(feeVaultManager.deployCalls(), 1);

        IPodFactory.VendorInfo memory info = factory.getVendorInfo(vendorId);
        assertEq(info.vendorAddress, vendor);
        assertEq(info.feeRecipient, feeRecipient);
        assertTrue(info.isActive);
        assertEq(info.podSet.eventPod, expectedEventPod);
        assertEq(info.podSet.orderBookPod, expectedOrderBookPod);
        assertEq(info.podSet.feeVaultPod, expectedFeeVaultPod);
        assertEq(info.podSet.fundingPod, expectedFundingPod);

        assertEq(factory.vendorAddressToId(vendor), vendorId);

        IPodFactory.VendorPodSet memory podSet = factory.getVendorPodSet(vendorId);
        assertEq(podSet.eventPod, expectedEventPod);
        assertEq(podSet.orderBookPod, expectedOrderBookPod);
        assertEq(podSet.feeVaultPod, expectedFeeVaultPod);
        assertEq(podSet.fundingPod, expectedFundingPod);
    }

    function test_registerVendor_revertsOnDuplicateVendorAddress() public {
        address vendor = address(0x3000);

        factory.registerVendor(vendor, address(0x4000));

        vm.expectRevert(abi.encodeWithSelector(IPodFactory.VendorAlreadyRegistered.selector));
        factory.registerVendor(vendor, address(0x5000));
    }

    function _predictPodAddress(uint256 vendorId, uint256 podType) internal view returns (address) {
        address implementation = deployer.getPodImplementation(podType);
        bytes32 salt = keccak256(abi.encodePacked(vendorId, podType));
        return Clones.predictDeterministicAddress(implementation, salt, address(deployer));
    }
}
