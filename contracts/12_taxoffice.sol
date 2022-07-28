// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./access/Operator.sol";
import "../interfaces/ITaxable.sol";
import "../interfaces/IUniswapV2Router.sol";

/*
    https://walrus.finance
*/
contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public wlrs = address(0x522348779DCb2911539e76A1042aA922F9C47Ee3);
    address public weth = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public uniRouter =
        address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(wlrs).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(wlrs).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(wlrs).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(wlrs).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(wlrs).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(wlrs).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress)
        public
        onlyOperator
    {
        ITaxable(wlrs).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(wlrs).isAddressExcluded(_address)) {
            return ITaxable(wlrs).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(wlrs).isAddressExcluded(_address)) {
            return ITaxable(wlrs).includeAddress(_address);
        }
    }

    function taxRate() external returns (uint256) {
        return ITaxable(wlrs).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtWlrs,
        uint256 amtToken,
        uint256 amtWlrsMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtWlrs != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(wlrs).transferFrom(msg.sender, address(this), amtWlrs);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(wlrs, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtWlrs;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtWlrs, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter)
            .addLiquidity(
                wlrs,
                token,
                amtWlrs,
                amtToken,
                amtWlrsMin,
                amtTokenMin,
                msg.sender,
                block.timestamp
            );

        if (amtWlrs.sub(resultAmtWlrs) > 0) {
            IERC20(wlrs).transfer(msg.sender, amtWlrs.sub(resultAmtWlrs));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtWlrs, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtWlrs,
        uint256 amtWlrsMin,
        uint256 amtEthMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtWlrs != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(wlrs).transferFrom(msg.sender, address(this), amtWlrs);
        _approveTokenIfNeeded(wlrs, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtWlrs;
        uint256 resultAmtEth;
        uint256 liquidity;
        (resultAmtWlrs, resultAmtEth, liquidity) = IUniswapV2Router(uniRouter)
            .addLiquidityETH{value: msg.value}(
            wlrs,
            amtWlrs,
            amtWlrsMin,
            amtEthMin,
            msg.sender,
            block.timestamp
        );

        if (amtWlrs.sub(resultAmtWlrs) > 0) {
            IERC20(wlrs).transfer(msg.sender, amtWlrs.sub(resultAmtWlrs));
        }
        return (resultAmtWlrs, resultAmtEth, liquidity);
    }

    function setTaxableWlrsOracle(address _wlrsOracle) external onlyOperator {
        ITaxable(wlrs).setWlrsOracle(_wlrsOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(wlrs).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(
            taxExclusionEnabled[msg.sender],
            "Address not approved for tax free transfers"
        );
        _excludeAddressFromTax(_sender);
        IERC20(wlrs).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded)
        external
        onlyOperator
    {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
