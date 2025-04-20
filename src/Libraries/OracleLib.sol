//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title OracleLib
 * @author cipherious.xyz
 * @dev This library is used to check chainlink oracle for stale data.
 * if the price is stale the function will revert and render the DSCEngine unusable.
 * we want the DSCEngine to freeze if the price is stale.
 */
library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant TimeOut = 3 hours;
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns (uint80,int256,uint256,uint256,uint80) {

    (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
    uint256 secondsSince = block.timestamp - updatedAt;
    if (secondsSince > TimeOut) {
          revert OracleLib__StalePrice();
    }
      return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}