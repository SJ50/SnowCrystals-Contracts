// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ITreasury {
    function daoFund() external view returns (address);

    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getSnowPrice() external view returns (uint256);

    function buyBonds(uint256 amount, uint256 targetPrice) external;

    function redeemBonds(uint256 amount, uint256 targetPrice) external;
}
