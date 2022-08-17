// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface ILiquidityFund {
    function addLiquidity(uint256 _amount) external;

    function sendToBonus(uint256 _price, uint256 _ceilingPrice) external;
}
