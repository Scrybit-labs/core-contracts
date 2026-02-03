// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/core/FundingManager.sol";

contract MockERC20 {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public immutable decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 tokenDecimals) {
        decimals = tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract FundingManagerLimitsTest is Test {
    FundingManager internal fundingManager;
    MockERC20 internal token;

    function setUp() public {
        FundingManager fundingManagerImpl = new FundingManager();
        bytes memory initData = abi.encodeCall(
            FundingManager.initialize,
            (address(this), address(this), address(this))
        );
        fundingManager = FundingManager(payable(address(new ERC1967Proxy(address(fundingManagerImpl), initData))));

        token = new MockERC20(18);
        token.mint(address(this), 100e18);
        token.approve(address(fundingManager), type(uint256).max);

        fundingManager.configureToken(address(token), 18, true);
    }

    function testDepositBelowMinPerTxnReverts() public {
        fundingManager.setMinTokenBalanceUsd(1e18);

        vm.expectRevert("FundingManager: deposit below minimum");
        fundingManager.deposit(address(token), 5e17);
    }

    function testDepositBelowMinTokenBalanceReverts() public {
        address user = address(0xBEEF);
        token.mint(user, 10e18);
        vm.prank(user);
        token.approve(address(fundingManager), type(uint256).max);

        vm.prank(user);
        vm.expectRevert("FundingManager: token balance below minimum");
        fundingManager.deposit(address(token), 6e18);

        vm.prank(user);
        fundingManager.deposit(address(token), 5e18);
        assertEq(fundingManager.userUsdBalances(user), 5e18);
    }

    function testDepositMeetsMinTokenBalanceAndBalances() public {
        fundingManager.deposit(address(token), 5e18);

        assertEq(fundingManager.userUsdBalances(address(this)), 5e18);

        (address[] memory tokens, uint256[] memory balances) = fundingManager.getAllTokenBalances(address(this));
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(token));
        assertEq(balances[0], 95e18);

        assertEq(fundingManager.getMinDepositPerTxnUsd(), 1e18);
        assertEq(fundingManager.getMinTokenBalanceUsd(), 5e18);
        assertEq(fundingManager.getTokenPrice(address(token)), 1e18);

        fundingManager.withdrawDirect(address(token), 2e18);
        (address[] memory updatedTokens, uint256[] memory updatedBalances) = fundingManager.getAllTokenBalances(
            address(this)
        );
        assertEq(updatedTokens.length, 1);
        assertEq(updatedTokens[0], address(token));
        assertEq(updatedBalances[0], 97e18);
    }

    function testMintCompleteSetAfterSettlementReverts() public {
        fundingManager.deposit(address(token), 5e18);
        fundingManager.registerEvent(1, 2);
        fundingManager.markEventSettled(1, 0);

        vm.expectRevert("FundingManager: event already settled");
        fundingManager.mintCompleteSetDirect(1, 1e18);
    }

    function testSetMinDepositPerTxnUsdOnlyOwner() public {
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        fundingManager.setMinDepositPerTxnUsd(2e18);
    }

    function testSetMinTokenBalanceUsdOnlyOwner() public {
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        fundingManager.setMinTokenBalanceUsd(2e18);
    }
}
