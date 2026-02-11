// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {FundingManager} from "../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../src/core/proxies/FundingManagerProxy.sol";

contract FundingManagerTokenConfigTest is Test {
    FundingManager internal fundingManager;
    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");

        FundingManager impl = new FundingManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy proxy = new FundingManagerProxy(address(impl), initData);
        fundingManager = FundingManager(payable(address(proxy)));
    }

    function testConfigureToken_NewToken_AddsToList() public {
        address token = _tokenAddress(1);

        vm.prank(owner);
        fundingManager.configureToken(token, 18, true);

        address[] memory tokens = fundingManager.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
    }

    function testConfigureToken_SameTokenTwice_NoDuplicate() public {
        address token = _tokenAddress(2);

        vm.prank(owner);
        fundingManager.configureToken(token, 18, true);
        vm.prank(owner);
        fundingManager.configureToken(token, 18, true);

        address[] memory tokens = fundingManager.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
    }

    function testConfigureToken_DisableThenReEnable_NoDuplicate() public {
        address token = _tokenAddress(3);

        vm.prank(owner);
        fundingManager.configureToken(token, 18, true);
        vm.prank(owner);
        fundingManager.configureToken(token, 18, false);
        vm.prank(owner);
        fundingManager.configureToken(token, 18, true);

        address[] memory tokens = fundingManager.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
    }

    function testConfigureToken_ManyTokens_GasEfficient() public {
        for (uint256 i = 1; i <= 60; i++) {
            vm.prank(owner);
            fundingManager.configureToken(_tokenAddress(i), 18, true);
        }

        address[] memory tokens = fundingManager.getSupportedTokens();
        assertEq(tokens.length, 60);
    }

    function testConfigureToken_DisabledToken_NotAddedToList() public {
        address token = _tokenAddress(99);

        vm.prank(owner);
        fundingManager.configureToken(token, 18, false);

        address[] memory tokens = fundingManager.getSupportedTokens();
        assertEq(tokens.length, 0);
    }

    function testFuzz_ConfigureToken_NeverDuplicates(address tokenA, address tokenB, bool enableA, bool enableB) public {
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));

        vm.prank(owner);
        fundingManager.configureToken(tokenA, 18, enableA);
        vm.prank(owner);
        fundingManager.configureToken(tokenB, 18, enableB);
        vm.prank(owner);
        fundingManager.configureToken(tokenA, 18, enableA);

        address[] memory tokens = fundingManager.getSupportedTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                assertTrue(tokens[i] != tokens[j]);
            }
        }

        uint256 expected = 0;
        if (enableA) {
            expected = 1;
        }
        if (enableB) {
            if (tokenB != tokenA) {
                expected += 1;
            } else if (expected == 0) {
                expected = 1;
            }
        }
        assertEq(tokens.length, expected);
    }

    function _tokenAddress(uint256 salt) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(salt)))));
    }
}
