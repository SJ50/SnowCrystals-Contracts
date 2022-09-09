// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ITaxOffice {
    function setMainTokenOracle(address _mainTokenOracle) external;

    function setMainTokenTaxTiers(
        uint256[] calldata _mainTokenTaxTwapTiers,
        uint256[] calldata _mainTokenTaxRateTiers
    ) external;

    function setShareTokenTaxTiers(
        uint256[] calldata _shareTokenTaxTwapTiers,
        uint256[] calldata _shareTokenTaxRateTiers
    ) external;

    function calculateMainTokenTax() external view returns (uint256 taxRate);

    function calculateShareTokenTax() external view returns (uint256 taxRate);

    function handleMainTokenTax(uint256 _amount) external;

    function handleShareTokenTax(uint256 _amount) external;

    function taxDiscount(address _sender, address _recipient)
        external
        returns (uint256);
}
