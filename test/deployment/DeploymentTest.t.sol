// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IMockOracleAdapter} from "../../src/interfaces/oracle/IMockOracleAdapter.sol";
import {IEventManager} from "../../src/interfaces/core/IEventManager.sol";
import {IFeeVaultManager} from "../../src/interfaces/core/IFeeVaultManager.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {IOrderBookManager} from "../../src/interfaces/core/IOrderBookManager.sol";

interface IDeployScript {
    function getImplementationAndProxy() external view returns (address implementation, address proxy);
}

interface IOwnable {
    function owner() external view returns (address);
}

interface IContractsLinker {
    function run() external;
}

contract DeploymentTest is Test {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    Deploy public deployer;

    address public owner;
    uint256 public ownerPrivateKey;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(ownerPrivateKey));

        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        owner = deployer.initialOwner();
    }

    function test_DeploymentCompletes() public {
        assertTrue(address(deployer.eventManager()) != address(0));
        assertTrue(address(deployer.feeVaultManager()) != address(0));
        assertTrue(address(deployer.fundingManager()) != address(0));
        assertTrue(address(deployer.orderBookManager()) != address(0));
        assertTrue(address(deployer.mockOracleAdapter()) != address(0));
    }

    function test_OracleAdapterDeployed() public {
        (address implementation, address proxy) =
            IDeployScript(address(deployer.mockOracleAdapterDeploy())).getImplementationAndProxy();

        _assertProxyDeployment(proxy, implementation);
        assertEq(proxy, address(deployer.mockOracleAdapter()));
    }

    function test_EventManagerDeployed() public {
        _assertManagerDeployment(address(deployer.eventManagerDeploy()), address(deployer.eventManager()));
    }

    function test_FeeVaultManagerDeployed() public {
        _assertManagerDeployment(address(deployer.feeVaultManagerDeploy()), address(deployer.feeVaultManager()));
    }

    function test_FundingManagerDeployed() public {
        _assertManagerDeployment(address(deployer.fundingManagerDeploy()), address(deployer.fundingManager()));
    }

    function test_OrderBookManagerDeployed() public {
        _assertManagerDeployment(address(deployer.orderBookManagerDeploy()), address(deployer.orderBookManager()));
    }

    function test_LinkingIsIdempotent() public {
        IContractsLinker linker = IContractsLinker(address(deployer.linker()));
        linker.run();
        linker.run();

        IEventManager eventManager = IEventManager(address(deployer.eventManager()));
        IFeeVaultManager feeVaultManager = IFeeVaultManager(address(deployer.feeVaultManager()));
        IFundingManager fundingManager = IFundingManager(address(deployer.fundingManager()));
        IOrderBookManager orderBookManager = IOrderBookManager(address(deployer.orderBookManager()));
        IMockOracleAdapter mockOracleAdapter = IMockOracleAdapter(address(deployer.mockOracleAdapter()));

        assertEq(eventManager.defaultOracleAdapter(), address(mockOracleAdapter));
        assertEq(eventManager.orderBookManager(), address(orderBookManager));
        assertEq(mockOracleAdapter.oracleConsumer(), address(eventManager));

        assertEq(feeVaultManager.orderBookManager(), address(orderBookManager));
        assertEq(feeVaultManager.fundingManager(), address(fundingManager));

        assertEq(fundingManager.orderBookManager(), address(orderBookManager));
        assertEq(fundingManager.eventManager(), address(eventManager));
        assertEq(fundingManager.feeVaultManager(), address(feeVaultManager));

        assertEq(orderBookManager.eventManager(), address(eventManager));
        assertEq(orderBookManager.fundingManager(), address(fundingManager));
        assertEq(orderBookManager.feeVaultManager(), address(feeVaultManager));
    }

    function _assertManagerDeployment(address deployScript, address proxy) internal {
        (address implementation, address deployedProxy) = IDeployScript(deployScript).getImplementationAndProxy();
        assertEq(proxy, deployedProxy);
        _assertProxyDeployment(proxy, implementation);
        assertEq(IOwnable(proxy).owner(), owner);
    }

    function _assertProxyDeployment(address proxy, address implementation) internal {
        assertTrue(proxy != address(0));
        assertTrue(implementation != address(0));
        assertGt(proxy.code.length, 0);
        assertEq(_getImplementation(proxy), implementation);
    }

    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }
}
