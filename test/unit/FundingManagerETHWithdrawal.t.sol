// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {FundingManager} from "../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../src/core/proxies/FundingManagerProxy.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";

contract FundingManagerHarness is FundingManager {
    function exposed_withdraw(address user, address tokenAddress, address payable withdrawAddress, uint256 usdAmount)
        external
    {
        _withdraw(user, tokenAddress, withdrawAddress, usdAmount);
    }
}

contract ReceiveOk {
    receive() external payable {}
}

contract NoReceive {
    // Intentionally no receive or fallback.
}

contract FundingManagerETHWithdrawalTest is Test {
    using stdStorage for StdStorage;

    FundingManagerHarness internal fundingManager;
    address internal owner;
    address internal feeVault;
    address internal user;

    ReceiveOk internal receiver;
    NoReceive internal noReceive;

    function setUp() public {
        owner = makeAddr("owner");
        feeVault = makeAddr("feeVault");
        user = makeAddr("user");

        FundingManagerHarness impl = new FundingManagerHarness();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy proxy = new FundingManagerProxy(address(impl), initData);
        fundingManager = FundingManagerHarness(payable(address(proxy)));

        vm.startPrank(owner);
        fundingManager.setFeeVaultManager(feeVault);
        fundingManager.configureToken(fundingManager.NATIVE_TOKEN(), 18, true);
        vm.stopPrank();

        receiver = new ReceiveOk();
        noReceive = new NoReceive();

        vm.deal(address(fundingManager), 100 ether);
    }

    function testWithdrawETH_Success() public {
        uint256 usdAmount = 2 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setUserUsdBalance(user, usdAmount);
        _setTokenLiquidity(nativeToken, usdAmount);

        uint256 beforeBalance = user.balance;
        fundingManager.exposed_withdraw(user, nativeToken, payable(user), usdAmount);

        assertEq(user.balance, beforeBalance + usdAmount);
        assertEq(fundingManager.userUsdBalances(user), 0);
        assertEq(fundingManager.tokenLiquidity(nativeToken), 0);
    }

    function testWithdrawETH_ToContractRecipient() public {
        uint256 usdAmount = 1 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setUserUsdBalance(user, usdAmount);
        _setTokenLiquidity(nativeToken, usdAmount);

        uint256 beforeBalance = address(receiver).balance;
        fundingManager.exposed_withdraw(user, nativeToken, payable(address(receiver)), usdAmount);

        assertEq(address(receiver).balance, beforeBalance + usdAmount);
    }

    function testWithdrawETH_ToContractWithoutReceive_Reverts() public {
        uint256 usdAmount = 1 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setUserUsdBalance(user, usdAmount);
        _setTokenLiquidity(nativeToken, usdAmount);

        vm.expectRevert(Errors.FailedCall.selector);
        fundingManager.exposed_withdraw(user, nativeToken, payable(address(noReceive)), usdAmount);
    }

    function testWithdrawETH_RevertsOnInsufficientBalance() public {
        uint256 usdAmount = 2 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setUserUsdBalance(user, 1 ether);
        _setTokenLiquidity(nativeToken, usdAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IFundingManager.InsufficientUsdBalance.selector, user, usdAmount, 1 ether)
        );
        fundingManager.exposed_withdraw(user, nativeToken, payable(user), usdAmount);
    }

    function testWithdrawLiquidity_ETH_Success() public {
        uint256 amount = 3 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setTokenLiquidity(nativeToken, amount);
        uint256 beforeBalance = user.balance;

        vm.prank(feeVault);
        fundingManager.withdrawLiquidity(nativeToken, amount, user);

        assertEq(user.balance, beforeBalance + amount);
        assertEq(fundingManager.tokenLiquidity(nativeToken), 0);
    }

    function testWithdrawLiquidity_ETH_ToContractWithoutReceive_Reverts() public {
        uint256 amount = 1 ether;
        address nativeToken = fundingManager.NATIVE_TOKEN();

        _setTokenLiquidity(nativeToken, amount);

        vm.prank(feeVault);
        vm.expectRevert(Errors.FailedCall.selector);
        fundingManager.withdrawLiquidity(nativeToken, amount, address(noReceive));
    }

    function _setUserUsdBalance(address account, uint256 usdAmount) internal {
        stdstore
            .target(address(fundingManager))
            .sig("userUsdBalances(address)")
            .with_key(account)
            .checked_write(usdAmount);
    }

    function _setTokenLiquidity(address token, uint256 amount) internal {
        stdstore
            .target(address(fundingManager))
            .sig("tokenLiquidity(address)")
            .with_key(token)
            .checked_write(amount);
    }
}
