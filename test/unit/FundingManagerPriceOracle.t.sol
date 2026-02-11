// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {FundingManager} from "../../src/core/FundingManager.sol";
import {FundingManagerProxy} from "../../src/core/proxies/FundingManagerProxy.sol";
import {MockOracleAdapter} from "../../src/oracle/mock/MockOracleAdapter.sol";
import {IFundingManager} from "../../src/interfaces/core/IFundingManager.sol";
import {IPriceOracle} from "../../src/interfaces/oracle/IPriceOracle.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract ConfigurablePriceOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getTokenPrice(address token) external view returns (uint256 price) {
        price = prices[token];
        require(price != 0, "PriceOracle: price not set");
    }
}

contract RevertingPriceOracle is IPriceOracle {
    function getTokenPrice(address) external pure returns (uint256) {
        revert("PriceOracle: revert");
    }
}

contract FundingManagerPriceOracleTest is Test {
    event PriceOracleAdapterUpdated(address indexed newAdapter);

    FundingManager internal fundingManager;
    address internal owner;
    address internal token6;
    address internal token8;
    address internal token18;

    function setUp() public {
        owner = makeAddr("owner");

        FundingManager impl = new FundingManager();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        FundingManagerProxy proxy = new FundingManagerProxy(address(impl), initData);
        fundingManager = FundingManager(payable(address(proxy)));

        token6 = makeAddr("token6");
        token8 = makeAddr("token8");
        token18 = makeAddr("token18");

        vm.startPrank(owner);
        fundingManager.configureToken(token6, 6, true);
        fundingManager.configureToken(token8, 8, true);
        fundingManager.configureToken(token18, 18, true);
        vm.stopPrank();
    }

    function testSetPriceOracleAdapter_OwnerCanSet_EmitsEvent() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PriceOracleAdapterUpdated(address(oracle));
        fundingManager.setPriceOracleAdapter(address(oracle));

        assertEq(address(fundingManager.priceOracleAdapter()), address(oracle));
    }

    function testSetPriceOracleAdapter_NonOwnerReverts() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();

        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        fundingManager.setPriceOracleAdapter(address(oracle));
    }

    function testSetPriceOracleAdapter_ZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("FundingManager: invalid address");
        fundingManager.setPriceOracleAdapter(address(0));
    }

    function testSetPriceOracleAdapter_CanUpdate() public {
        ConfigurablePriceOracle oracleA = new ConfigurablePriceOracle();
        ConfigurablePriceOracle oracleB = new ConfigurablePriceOracle();

        vm.startPrank(owner);
        fundingManager.setPriceOracleAdapter(address(oracleA));
        fundingManager.setPriceOracleAdapter(address(oracleB));
        vm.stopPrank();

        assertEq(address(fundingManager.priceOracleAdapter()), address(oracleB));
    }

    function testGetTokenPrice_WithoutOracle_Returns1e18() public {
        uint256 price = fundingManager.getTokenPrice(token6);
        assertEq(price, 1e18);
    }

    function testGetTokenPrice_WithMockOracle_Returns1e18() public {
        MockOracleAdapter mockOracleAdapter = new MockOracleAdapter();

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(mockOracleAdapter));

        uint256 price = fundingManager.getTokenPrice(token6);
        assertEq(price, 1e18);
    }

    function testGetTokenPrice_WithConfigurableOracle_ReturnsConfiguredPrice() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();
        oracle.setPrice(token18, 2000e18);

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        uint256 price = fundingManager.getTokenPrice(token18);
        assertEq(price, 2000e18);
    }

    function testGetTokenPrice_UnsupportedToken_Reverts() public {
        address unsupported = makeAddr("unsupported");

        vm.expectRevert(abi.encodeWithSelector(IFundingManager.TokenIsNotSupported.selector, unsupported));
        fundingManager.getTokenPrice(unsupported);
    }

    function testGetTokenPrice_RevertingOracle_PropagatesRevert() public {
        RevertingPriceOracle oracle = new RevertingPriceOracle();

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        vm.expectRevert("PriceOracle: revert");
        fundingManager.getTokenPrice(token6);
    }

    function testNormalizeToUsd_WithoutOracle_StablecoinBehavior() public {
        uint256 amount = 100e6;
        uint256 usdAmount = fundingManager.normalizeToUsd(token6, amount);
        assertEq(usdAmount, 100e18);
    }

    function testNormalizeToUsd_WithMockOracle_SameAsWithoutOracle() public {
        uint256 amount = 100e6;
        uint256 withoutOracle = fundingManager.normalizeToUsd(token6, amount);

        MockOracleAdapter mockOracleAdapter = new MockOracleAdapter();
        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(mockOracleAdapter));

        uint256 withOracle = fundingManager.normalizeToUsd(token6, amount);
        assertEq(withOracle, withoutOracle);
    }

    function testNormalizeToUsd_WithConfigurableOracle_AppliesPrice() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();
        oracle.setPrice(token18, 2e18);

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        uint256 amount = 100e18;
        uint256 usdAmount = fundingManager.normalizeToUsd(token18, amount);
        assertEq(usdAmount, 200e18);
    }

    function testNormalizeToUsd_DifferentDecimals_Correct() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();
        oracle.setPrice(token8, 10e18);

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        uint256 amount = 5e8;
        uint256 usdAmount = fundingManager.normalizeToUsd(token8, amount);
        assertEq(usdAmount, 50e18);
    }

    function testDenormalizeFromUsd_WithoutOracle_StablecoinBehavior() public {
        uint256 usdAmount = 100e18;
        uint256 tokenAmount = fundingManager.denormalizeFromUsd(token6, usdAmount);
        assertEq(tokenAmount, 100e6);
    }

    function testDenormalizeFromUsd_WithMockOracle_SameAsWithoutOracle() public {
        uint256 usdAmount = 100e18;
        uint256 withoutOracle = fundingManager.denormalizeFromUsd(token6, usdAmount);

        MockOracleAdapter mockOracleAdapter = new MockOracleAdapter();
        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(mockOracleAdapter));

        uint256 withOracle = fundingManager.denormalizeFromUsd(token6, usdAmount);
        assertEq(withOracle, withoutOracle);
    }

    function testDenormalizeFromUsd_WithConfigurableOracle_AppliesPrice() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();
        oracle.setPrice(token18, 2e18);

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        uint256 usdAmount = 200e18;
        uint256 tokenAmount = fundingManager.denormalizeFromUsd(token18, usdAmount);
        assertEq(tokenAmount, 100e18);
    }

    function testDenormalizeFromUsd_RoundTrip_PriceTwoX() public {
        ConfigurablePriceOracle oracle = new ConfigurablePriceOracle();
        oracle.setPrice(token6, 2e18);

        vm.prank(owner);
        fundingManager.setPriceOracleAdapter(address(oracle));

        uint256 amount = 123e6;
        uint256 usdAmount = fundingManager.normalizeToUsd(token6, amount);
        uint256 roundTrip = fundingManager.denormalizeFromUsd(token6, usdAmount);

        assertEq(roundTrip, amount);
    }

    function testMulDiv_OneToOneIdentity() public {
        uint256 value = 987654321;
        uint256 result = FixedPointMathLib.mulDiv(value, 1e18, 1e18);
        assertEq(result, value);
    }
}
