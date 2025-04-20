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
/**
 * @title Decentralised Stable Coin
 * @author Cipherious.xyz
 * @notice This is a decentralised stable coin.
 * minting:Algorithmic
 * Relative Stability:Pegged to usd
 * collateral:Exogenous(ETH & BTC)
 *
 * This is the contract meant to be govened by DSCEngine.This contract is
 * just the ERC20 implementation of our stablecoin system.
 *
 */

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DSCEngine} from "./DSCEngine.sol";

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountMustExceedsBalance();
    error DecentralisedStableCoin__StableCoinNotZeroAddress();

    constructor() ERC20("Decentralised Stable Coin", "DSC") Ownable() {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralisedStableCoin__BurnAmountMustExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__StableCoinNotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
