// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./Libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author cipherious.xyz
 *  This system is designed to be as minimal as possible and
 *  have the tokens maintain a 1 token ==$1 peg.
 * This stablecoin has the following properties:
 * -Exogenous collateral
 * -Dollar pegged
 * -Algorithmically stable
 *
 * it is similar to DAI if DAI had no governance ,no fees and was only backed by wETH and wBTC
 *
 * our DSC system should always be "overcollateralized".At no point, should the value of all collateral
 * <=the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system.It handles all the logic  for mining
 * and redeeming DSC as well as depositing & withdrawing collateral.
 * @notice This  contract is very loosely based on the MakerDAO DSS(DAI) system.
 *
 */

contract DSCEngine is ReentrancyGuard {
    ///////////////
    // Types    //
    //////////////
    using OracleLib for AggregatorV3Interface;
    ///////////////
    // Errors   //
    //////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength();
    error DSCEngine___NotAllowedToken();
    error DSCEngine__TranferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 _healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant ADDITIONAL_PRICEFEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //this means a  10 % bonus
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_CollateralTokens;
    DecentralisedStableCoin private immutable i_dsc;

    /////////////////////
    //      Events     //
    /////////////////////

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);
    /////////////////////
    //  Modifiers      //
    /////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine___NotAllowedToken();
        }
        _;
    }

    ///////////////
    // Functions//
    //////////////
    /**
     * @dev Each cyptocurrency(token) has its own price feed.
     *  so we configure the contructor to automatically the
     *  provided address of the token to be used as collateral to its price feed
     */
    /**
     *
     * @param tokenAddress address of the token token be used as collateral
     * @param priceFeedAddresses  Address of the price feed of the token paired with USDC
     * @param dscAddress  address of a deployed dsc contract
     */
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_CollateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral  amount of collateral to deposit
     * @param amountDscToMint  amount of DSC to mint
     * @notice This function will deposit your collateral and mint dsc in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    //In order to redeem collateral;
    //1.health factor must be over 1 after collateral pulled
    //DRY:Dont repeat yourself

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }
    //Do we need  if this breaks health factor

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
    }
    //if someone is undercollateralized we will pay you to liquidate them
    /**
     * @param collateral The address of the erc20 collateral token to liquidate from the user
     * @param user The user who has broken the health factor. their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC  you want to burn to improve user health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be 200% overcollateralized in order this to work
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _burnDSC(debtToCover, user, msg.sender);
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to redeem
     * @param amountCollateral  amount of collateral to redeem
     * @param amountDscToBurn  amount of DSC to burn
     * @notice This function will redeem your collateral and burn dsc in one transaction
     * @notice a known bug  would be if the protocol is undercollateralized,then we
     * wouldn't be able to incentive the liquidators
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }
    /**
     * @notice follows CEI
     * @param amountDscToMint  amount of DSC to mint
     * @notice They must have more collateral than the minimal threshold
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral .
     * @param amountCollateral  The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TranferFailed();
        }
    }
    ////////////////////////////////////////
    // Private and Internal view Functions //
    ////////////////////////////////////////
    /**
     *
     * @dev low level internal function
     */

    function _burnDSC(uint256 amountDSCTOBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= amountDSCTOBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCTOBurn);
        if (!success) {
            revert DSCEngine__TranferFailed();
        }
        i_dsc.burn(amountDSCTOBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        _revertIfHealthFactorIsBroken(from);
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TranferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     *
     *  Returns how close to liquidation a user is
     *  If a user goes below 1,then they can get liquidated
     *
     */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    /**
     * @dev check health factor to see if the user has enough collateral
     *  revert if they don't
     * @param user address of the user to check the health factor
     */

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    ////////////////////////////////////////
    // Public and External view Functions //
    ////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //price of Eth (token)

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //the amount of the token in wei divided by the currency coversion rate
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_PRICEFEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_CollateralTokens.length; i++) {
            address token = s_CollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //remember the decimal of the price feed is 8
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_PRICEFEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
    ////////////////
    //Getters     //
    ////////////////

    function getCollateralDeposited(address user, address tokenCollateral) public view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateral];
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralvalueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralvalueInUsd);
    }

    function getDscMinted(address user) public view returns (uint256) {
        return s_DscMinted[user];
    }

    function getPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getDsc() public view returns (DecentralisedStableCoin) {
        return i_dsc;
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalPriceFeedPrecision() public pure returns (uint256) {
        return ADDITIONAL_PRICEFEED_PRECISION;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() public pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() public pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_CollateralTokens;
    }
}
