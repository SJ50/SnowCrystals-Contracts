// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Taxable is IERC20 {
    function burn(uint256 amount) external;

    function taxOffice() external returns (address);

    function staticTaxRate() external returns (uint256);

    function dynamicTaxRate() external returns (uint256);

    function getCurrentTaxRate() external returns (uint256);

    function setTaxOffice(address _taxOffice) external;

    function setStaticTaxRate(uint256 _taxRate) external;

    function setEnableDynamicTax(bool _enableDynamicTax) external;

    function setWhitelistType(address _token, uint8 _type) external;

    function isWhitelistedSender(address _account)
        external
        view
        returns (bool isWhitelisted);

    function isWhitelistedRecipient(address _account)
        external
        view
        returns (bool isWhitelisted);

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external;
}
