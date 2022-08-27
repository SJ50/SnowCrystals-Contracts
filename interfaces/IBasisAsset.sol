// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IBasisAsset {
    function burn(uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;

    function mint(address recipient, uint256 amount) external returns (bool);

    function operator() external view returns (address);

    function setBurnTiersRate(uint8 _index, uint256 _value)
        external
        returns (bool);

    function setExcludeBothDirectionsFee(address _account, bool _status)
        external;

    function setExcludeFromFee(address _account, bool _status) external;

    function setExcludeToFee(address _account, bool _status) external;

    function setOracle(address _oracle) external;

    function setTaxFund(address _taxFund) external;

    function setTaxTiersRate(uint8 _index, uint256 _value)
        external
        returns (bool);

    function switchEnableUpdatePrice() external;

    function toggleAddLiquidityEnabled() external;
}
