// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IStdReference.sol";
import "../interfaces/IERC20Metadata.sol";

contract DataFeedOracle {
    using SafeMath for uint256;
    IStdReference ref;

    uint256 public price;
    uint256[] public pricesArr;

    constructor(IStdReference _ref) public {
        ref = _ref;
    }

    function consult(address _base, uint256 _amountIn)
        external
        view
        returns (uint256)
    {
        string memory base = IERC20Metadata(_base).symbol();
        if (
            keccak256(abi.encodePacked(base)) ==
            keccak256(abi.encodePacked("WCRO"))
        ) {
            base = "CRO";
        }

        IStdReference.ReferenceData memory data = ref.getReferenceData(
            base,
            "USD"
        );
        uint256 amountIn = _amountIn.div(1e18);
        return data.rate.mul(amountIn);
    }

    function getPrice(string memory _base, string memory _quote)
        external
        view
        returns (uint256)
    {
        IStdReference.ReferenceData memory data = ref.getReferenceData(
            _base,
            _quote
        );
        return data.rate;
    }

    function getMultiPrices(string[] memory _bases, string[] memory _quotes)
        external
        view
        returns (uint256[] memory)
    {
        require(_bases.length == _quotes.length, "BAD_INPUT_LENGTH");
        IStdReference.ReferenceData[] memory data = ref.getReferenceDataBulk(
            _bases,
            _quotes
        );

        uint256 len = _bases.length;
        uint256[] memory prices = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            prices[i] = data[i].rate;
        }

        return prices;
    }

    function savePrice(string memory _base, string memory _quote) external {
        IStdReference.ReferenceData memory data = ref.getReferenceData(
            _base,
            _quote
        );
        price = data.rate;
    }

    function saveMultiPrices(string[] memory _bases, string[] memory _quotes)
        public
    {
        require(_bases.length == _quotes.length, "BAD_INPUT_LENGTH");
        uint256 len = _bases.length;
        IStdReference.ReferenceData[] memory data = ref.getReferenceDataBulk(
            _bases,
            _quotes
        );
        delete pricesArr;
        for (uint256 i = 0; i < len; i++) {
            pricesArr.push(data[i].rate);
        }
    }
}
