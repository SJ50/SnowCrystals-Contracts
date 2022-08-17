// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IZap {
    function zapInToken(
        address _from,
        uint256 amount,
        address _to,
        address routerAddr,
        address _recipient
    ) external;
}
