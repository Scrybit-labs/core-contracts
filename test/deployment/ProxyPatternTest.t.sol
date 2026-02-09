// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IDeployScript {
    function getImplementationAndProxy() external view returns (address implementation, address proxy);
}

interface IUUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

contract DummyUUPS is UUPSUpgradeable {
    function _authorizeUpgrade(address) internal override {}
}

contract ProxyPatternTest is Test {
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

    function test_ProxiesUseERC1967Storage() public {
        _assertDeploymentSlot(address(deployer.mockOracleAdapterDeploy()));
        _assertDeploymentSlot(address(deployer.eventManagerDeploy()));
        _assertDeploymentSlot(address(deployer.feeVaultManagerDeploy()));
        _assertDeploymentSlot(address(deployer.fundingManagerDeploy()));
        _assertDeploymentSlot(address(deployer.orderBookManagerDeploy()));
    }

    function test_OnlyOwnerCanUpgrade() public {
        address newImplementation = address(new DummyUUPS());
        address[] memory proxies = new address[](5);
        proxies[0] = address(deployer.mockOracleAdapter());
        proxies[1] = address(deployer.eventManager());
        proxies[2] = address(deployer.feeVaultManager());
        proxies[3] = address(deployer.fundingManager());
        proxies[4] = address(deployer.orderBookManager());

        for (uint256 i = 0; i < proxies.length; i++) {
            vm.prank(address(0xBEEF));
            vm.expectRevert();
            IUUPSUpgradeable(proxies[i]).upgradeToAndCall(newImplementation, bytes(""));

            vm.prank(owner);
            IUUPSUpgradeable(proxies[i]).upgradeToAndCall(newImplementation, bytes(""));
            assertEq(_getImplementation(proxies[i]), newImplementation);
        }
    }

    function _assertDeploymentSlot(address deployScript) internal view {
        (address implementation, address proxy) = IDeployScript(deployScript).getImplementationAndProxy();
        assertEq(_getImplementation(proxy), implementation);
    }

    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }
}
