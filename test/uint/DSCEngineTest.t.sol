//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    DecentralisedStableCoin public dsc;
    DSCEngine public engine;
    DeployDSC deployer;
    HelperConfig public helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wbtc;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 5 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 private constant AMOUNT_DSC_MINTED = 5 ether;
    uint256 private constant ETH_MOCK_PRICE = 2000;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approveInternal(USER, address(engine), 5e18);
    }
    ////////////////////////
    /// Constructor Tests///
    ////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedsLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    /// Price Tests///
    //////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedValue = 15e18 * 2000;
        uint256 actualValue = engine.getUsdValue(weth, ethAmount);
        assertEq(actualValue, expectedValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedweth = 0.05 ether;
        uint256 actualweth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualweth, expectedweth);
    }
    //////////////////////////////////////////////
    //// depositeCollateral  and mint Tests  ////
    ////////////////////////////////////////////

    function testCanMintWithDepositedCollateral() public depositCollateralAndMintDsc {
        uint256 amountDsc = dsc.balanceOf(USER);
        assert(amountDsc == AMOUNT_DSC_MINTED);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfTokenIsNotAllowed() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine___NotAllowedToken.selector);
        engine.depositCollateral(USER, 1);
        vm.stopPrank();
    }

    function testCollateralDepositedIsUpdated() public {
        //Arrange
        uint256 expectedCollateralAmount = AMOUNT_COLLATERAL;
        console.log("expectedCollateralAmount:", expectedCollateralAmount);
        uint256 startingCollateralAmount = engine.getCollateralDeposited(USER, weth);
        console.log("startingCollateralAmount:", startingCollateralAmount);
        //Act
        vm.prank(USER);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 endingCollateralAmount = engine.getCollateralDeposited(USER, weth);
        //Assert
        assert(expectedCollateralAmount == endingCollateralAmount + startingCollateralAmount);
    }

    modifier depositedCollateral() {
        vm.startBroadcast(USER);
        ERC20Mock(weth).approveInternal(USER, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopBroadcast();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        console.log("collateralValueInUsd:", collateralValueInUsd);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositingCollateralEmitsEvent() public {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false, address(engine));
        emit collateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositedCollateral() public {
        vm.startBroadcast(USER);
        ERC20Mock(weth).approveInternal(USER, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopBroadcast();
    }

    function testHealthFactorIsCorrect() public depositedCollateral {
        //Arrage
        uint256 expectedHealthFactor = 1e38;
        uint256 collateralvalueInUsd = (AMOUNT_COLLATERAL * ETH_MOCK_PRICE);
        console.log("expectedHealthFactor:", expectedHealthFactor);
        uint256 amountDscMinted = 50;
        //Act
        vm.prank(USER);
        engine.mintDsc(amountDscMinted);
        uint256 actualHealthFactor = engine.calculateHealthFactor(amountDscMinted, collateralvalueInUsd);
        console.log("actualHealthFactor:", actualHealthFactor);
        //Assert
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testCanDepositCollateralAndMintDsc() public {
        //Arrage
        uint256 expectedAmountDscToMint = 50;

        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(engine), AMOUNT_COLLATERAL);
        //Act
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, expectedAmountDscToMint);
        vm.stopPrank();
        uint256 actualDscMinted = engine.getDscMinted(USER);
        uint256 actualCollateralDeposited = engine.getCollateralDeposited(USER, weth);
        //Assert
        assert(actualDscMinted == expectedAmountDscToMint);
        assert(actualCollateralDeposited == AMOUNT_COLLATERAL);
    }
    ////////////////////////////
    //redeem collateral Test///
    //////////////////////////

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approveInternal(USER, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);

        vm.stopPrank();
        _;
    }

    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        uint256 amountDscToMint = 5;
        vm.startPrank(USER);
        engine.mintDsc(amountDscToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        //Arrange

        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);

        uint256 amountCollateralToRedeem = AMOUNT_COLLATERAL;
        uint256 startingTokenBalance = IERC20(weth).balanceOf(USER);
        uint256 expectedEndingTokenBalance = startingTokenBalance + amountCollateralToRedeem;
        console.log("startingBalanceOfUser:", startingTokenBalance);

        //Act
        vm.prank(USER);
        engine.redeemCollateral(weth, amountCollateralToRedeem);
        uint256 endingTokenBalance = IERC20(weth).balanceOf(USER);
        //assert
        assertEq(endingTokenBalance, expectedEndingTokenBalance);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public {}
    //////////////////////////////////////////////
    ///Liquidation Tests        /////////////////
    /////////////////////////////////////////////

    modifier liquidate() {
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approveInternal(USER, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);


        int256 ethPrice = 500;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethPrice);
        uint256 healthFactor = engine.calculateHealthFactor(AMOUNT_DSC_MINTED, AMOUNT_COLLATERAL * uint256(ethPrice));
        console.log("healthFactor:", healthFactor);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approveInternal(LIQUIDATOR, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        _;
    }
    function testUsersCanBeLiquidated() public {}
    //////////////////////////////////////////////
    ////////// Burn DSC              /////////////
    //////////////////////////////////////////////

    function testCanBurnDSC() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        engine.burnDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();

        assert(dsc.balanceOf(USER) == 0);
    }
}
