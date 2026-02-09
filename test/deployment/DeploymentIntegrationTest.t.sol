// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/deploy/local/V1/Deploy.s.sol";
import {IEventManager} from "../../src/interfaces/core/IEventManager.sol";

contract DeploymentIntegrationTest is Test {
    Deploy public deployer;
    IEventManager public eventManager;

    address public owner;
    uint256 public ownerPrivateKey;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        vm.setEnv("SEPOLIA_PRIV_KEY", vm.toString(ownerPrivateKey));

        deployer = new Deploy();
        deployer.setUp();
        deployer.run();

        eventManager = IEventManager(address(deployer.eventManager()));
        owner = deployer.initialOwner();
    }

    function test_CanCreateEventAfterDeployment() public {
        IEventManager.Outcome[] memory outcomes = new IEventManager.Outcome[](2);
        outcomes[0] = IEventManager.Outcome({name: "Yes", description: "Event happens"});
        outcomes[1] = IEventManager.Outcome({name: "No", description: "Event does not happen"});

        uint256 deadline = block.timestamp + 1 days;
        uint256 settlementTime = deadline + 1 days;
        bytes32 eventType = keccak256("SPORTS");

        vm.prank(owner);
        uint256 eventId = eventManager.createEvent(
            "Deployment Integration Test",
            "Ensure deployment wiring supports event creation",
            deadline,
            settlementTime,
            outcomes,
            eventType
        );

        IEventManager.Event memory created = eventManager.getEvent(eventId);
        assertEq(created.eventId, eventId);
        assertEq(created.creator, owner);
        assertEq(created.eventType, eventType);
        assertEq(created.outcomes.length, outcomes.length);
    }
}
