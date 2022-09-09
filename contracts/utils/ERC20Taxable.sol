// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "../access/Operator.sol";
import "../../interfaces/ITaxOffice.sol";

contract ERC20Taxable is ERC20Burnable, Operator {
    using SafeMath for uint256;

    enum WhitelistType {
        NONE,
        SENDER,
        RECIPIENT,
        BOTH
    }

    mapping(address => WhitelistType) public whitelistType;

    bool public enableDynamicTax;
    uint256 public constant BASIS_POINTS_DENOM = 10_000;
    uint256 public constant MAX_TAX_RATE = 3_500;
    uint256 public staticTaxRate;
    uint256 public dynamicTaxRate;

    address public taxOffice;

    constructor(string memory _name, string memory _symbol)
        public
        ERC20(_name, _symbol)
    {}

    modifier onlyTaxOffice() {
        require(taxOffice == msg.sender, "Error: Caller is not the tax office");
        _;
    }

    function setTaxOffice(address _taxOffice) external onlyOperator {
        taxOffice = _taxOffice;
    }

    function setStaticTaxRate(uint256 _taxRate) external onlyTaxOffice {
        require(_taxRate <= MAX_TAX_RATE, "Error: Max tax rate exceeded.");
        staticTaxRate = _taxRate;
    }

    function setEnableDynamicTax(bool _enableDynamicTax)
        external
        onlyTaxOffice
    {
        enableDynamicTax = _enableDynamicTax;
    }

    function setWhitelistType(address _account, uint8 _type)
        external
        onlyTaxOffice
    {
        whitelistType[_account] = WhitelistType(_type);
    }

    function isWhitelistedSender(address _account)
        public
        view
        returns (bool isWhitelisted)
    {
        isWhitelisted =
            whitelistType[_account] == WhitelistType.SENDER ||
            whitelistType[_account] == WhitelistType.BOTH;
    }

    function isWhitelistedRecipient(address _account)
        public
        view
        returns (bool isWhitelisted)
    {
        isWhitelisted =
            whitelistType[_account] == WhitelistType.RECIPIENT ||
            whitelistType[_account] == WhitelistType.BOTH;
    }

    function getCurrentTaxRate() public returns (uint256 taxRate) {
        taxRate = staticTaxRate;
        if (enableDynamicTax == true) {
            _updateDynamicTaxRate();
            if (dynamicTaxRate > MAX_TAX_RATE) {
                dynamicTaxRate = MAX_TAX_RATE;
            }
            taxRate = dynamicTaxRate;
        }
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool successFlag) {
        //If neither the sender or recipient are whitelisted then apply tax.
        if (
            !isWhitelistedSender(_sender) && !isWhitelistedRecipient(_recipient)
        ) {
            //Calculate tax amount and then handle tax.
            uint256 taxRate = getCurrentTaxRate();

            uint256 taxDiscount = BASIS_POINTS_DENOM.sub(
                ITaxOffice(taxOffice).taxDiscount(_sender, _recipient)
            );

            taxRate = taxRate.mul(taxDiscount).div(BASIS_POINTS_DENOM);
            uint256 taxableAmount = _amount.mul(taxRate).div(
                BASIS_POINTS_DENOM
            );
            _amount = _amount.sub(taxableAmount);
            _handleTax(_sender, taxableAmount);
        }

        //Use inherited function to transferFrom.
        successFlag = ERC20.transferFrom(_sender, _recipient, _amount);
    }

    //Overrideable functions for the inheriting contract to dictate tax rates.
    function _updateDynamicTaxRate() internal virtual {}

    function _handleTax(address _sender, uint256 _amount) internal virtual {}

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
