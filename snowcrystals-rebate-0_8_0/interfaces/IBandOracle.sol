// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

interface TestInterface {
    function getPrice(string memory _base, string memory _quote)
        external
        view
        returns (uint256);

    function getMultiPrices(string[] memory _bases, string[] memory _quotes)
        external
        view
        returns (uint256[] memory);
}
