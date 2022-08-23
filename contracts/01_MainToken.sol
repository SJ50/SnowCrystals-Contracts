// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./lib/SafeMath8.sol";
import "./access/Operator.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILiquidityFund.sol";

/*
    https://snowcrystals.finance
*/

contract Snow is ERC20, ERC20Burnable, Operator {
    using SafeMath for uint256;
    using SafeMath8 for uint8;

    /* ========== STATE VARIABLES ========== */
    // Initial distribution for the first 48h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 24000 ether;
    // Distribution for airdrops wallet
    uint256 public constant INITIAL_DAO_WALLET_DISTRIBUTION = 1000 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;
    bool public addLiquidityEnabled;

    address public oracle;

    uint256 public burnRate;
    uint256 public taxRate; // buy back  Token and add liquidity

    uint256[] public tiersTwaps = [
        0,
        1e18,
        1.05e18,
        1.10e18,
        1.20e18,
        1.30e18,
        1.40e18,
        1.50e18
    ];

    uint256[] public burnTiersRates = new uint256[](8);

    uint256[] public taxTiersRates = new uint256[](8);

    address public taxFund;
    address public pegToken;
    address public daoWallet;

    uint256 private _totalBurned;
    uint256 private _totalTaxAdded;
    bool public enableUpdatePrice;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedToFee;

    /* ========== GOVERNANCE ========== */
    /**
     * @notice Constructs the SNOW ERC-20 contract.
     */

    constructor(
        string memory name_,
        string memory symbol_,
        address _taxFund
    ) public ERC20(name_, symbol_) {
        // "snowcrystals.finance", "SNOW"

        enableUpdatePrice = true;
        taxFund = _taxFund;

        // Mints 10 SNOW to contract creator for initial pool setup
        _mint(msg.sender, 1000 ether);
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address[] memory _genesisPools,
        uint256[] memory _poolsStakes,
        address _daoWallet
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPools.length > 0, "_genesisPools.length > 0");
        require(_genesisPools.length == _poolsStakes.length, "arrays length");
        require(_daoWallet != address(0), "!_daoWallet");
        rewardPoolDistributed = true;

        uint256 totalStakePercent = 0;
        for (uint256 i = 0; i < _poolsStakes.length; i++) {
            totalStakePercent += _poolsStakes[i];
        }

        require(totalStakePercent == 10000, "total stake % must be 10000");

        uint256 totalDistributed;
        for (uint256 i = 0; i < _genesisPools.length; i++) {
            require(_genesisPools[i] != address(0), "!_genesisPool");
            uint256 stake;
            if (i == _genesisPools.length - 1) {
                stake = INITIAL_GENESIS_POOL_DISTRIBUTION - totalDistributed;
            } else {
                stake = INITIAL_GENESIS_POOL_DISTRIBUTION
                    .mul(_poolsStakes[i])
                    .div(10000);
            }

            totalDistributed += stake;
            _mint(_genesisPools[i], stake);
        }

        _mint(_daoWallet, INITIAL_DAO_WALLET_DISTRIBUTION);
    }

    /* ========== EVENTS ========== */

    event TaxAdded(address indexed account, address taxFund, uint256 amount);
    event TokenBurned(address indexed account, uint256 amount);

    /* ========== Modifiers =============== */

    /* ============= Taxation ============= */
    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function toggleAddLiquidityEnabled() external onlyOwner {
        addLiquidityEnabled = !addLiquidityEnabled;
    }

    function getTiersTwapsCount() public view returns (uint256 count) {
        return tiersTwaps.length;
    }

    function getBurnTiersRatesCount() public view returns (uint256 count) {
        return burnTiersRates.length;
    }

    function getTaxTiersRatesCount() public view returns (uint256 count) {
        return burnTiersRates.length;
    }

    function setTiersTwap(uint8 _index, uint256 _value)
        public
        onlyOwner
        returns (bool)
    {
        require(_index >= 0, "Index has to be higher than 0");
        require(
            _index < getTiersTwapsCount(),
            "Index has to lower than count of tax tiers"
        );
        if (_index > 0) {
            require(_value > tiersTwaps[_index - 1]);
        }
        if (_index < getTiersTwapsCount().sub(1)) {
            require(_value < tiersTwaps[_index + 1]);
        }
        tiersTwaps[_index] = _value;
        return true;
    }

    function setBurnTiersRate(uint8 _index, uint256 _value)
        public
        onlyOwner
        returns (bool)
    {
        require(_value <= 1500, "allowed maximum burn rate 15%");
        require(_index >= 0, "Index has to be higher than 0");
        require(
            _index < getBurnTiersRatesCount(),
            "Index has to lower than count of tax tiers"
        );
        burnTiersRates[_index] = _value;
        return true;
    }

    function setTaxTiersRate(uint8 _index, uint256 _value)
        public
        onlyOwner
        returns (bool)
    {
        require(_value <= 1500, "allowed maximum burn rate 15%");
        require(_index >= 0, "Index has to be higher than 0");
        require(
            _index < getTaxTiersRatesCount(),
            "Index has to lower than count of tax tiers"
        );
        taxTiersRates[_index] = _value;
        return true;
    }

    function setTaxFund(address _taxFund) external onlyOwner {
        require(_taxFund != address(0), "zero");
        taxFund = _taxFund;
    }

    function setExcludeFromFee(address _account, bool _status)
        external
        onlyOwner
    {
        _isExcludedFromFee[_account] = _status;
    }

    function setExcludeToFee(address _account, bool _status)
        external
        onlyOwner
    {
        _isExcludedToFee[_account] = _status;
    }

    function setExcludeBothDirectionsFee(address _account, bool _status)
        external
        onlyOwner
    {
        _isExcludedFromFee[_account] = _status;
        _isExcludedToFee[_account] = _status;
    }

    function switchEnableUpdatePrice() external onlyOwner {
        enableUpdatePrice = !enableUpdatePrice;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalBurned() external view returns (uint256) {
        return _totalBurned;
    }

    function totalTaxAdded() external view returns (uint256) {
        return _totalTaxAdded;
    }

    function getTokenPrice() public view returns (uint256) {
        address _oracle = oracle;
        return
            (_oracle == address(0))
                ? 1e18
                : uint256(IOracle(_oracle).consult(address(this), 1e18));
    }

    function getTokenUpdatedPrice() public view returns (uint256) {
        address _oracle = oracle;
        return
            (_oracle == address(0))
                ? 1e18
                : uint256(IOracle(_oracle).twap(address(this), 1e18));
    }

    function isExcludedFromFee(address _account) external view returns (bool) {
        return _isExcludedFromFee[_account];
    }

    function isExcludedToFee(address _account) external view returns (bool) {
        return _isExcludedToFee[_account];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _updateDollarPrice() internal {
        address _oracle = oracle;
        if (_oracle != address(0) && enableUpdatePrice == true)
            try IOracle(_oracle).update() {} catch {}
    }

    /**
     * @notice Operator mints basis V3S-Peg Token to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of basis V3S-Peg Token to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_)
        public
        onlyOperator
        returns (bool)
    {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount)
        public
        override
        onlyOperator
    {
        super.burnFrom(account, amount);
    }

    /* ========== OVERRIDE STANDARD FUNCTIONS ========== */

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `_account` cannot be the zero address.
     * - `_account` must have at least `_amount` tokens.
     */
    function _burn(address _account, uint256 _amount) internal override {
        super._burn(_account, _amount);
        _totalBurned = _totalBurned.add(_amount);
        emit TokenBurned(_account, _amount);
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "TTEST: transfer to the zero address");
        require(recipient != address(0), "TTEST: transfer to the zero address");

        uint256 _amount = amount;

        _beforeTokenTransfer(sender, recipient, _amount);

        if (!_isExcludedFromFee[sender] && !_isExcludedToFee[recipient]) {
            uint256 _tokenPrice = getTokenUpdatedPrice();

            uint256 _taxRate = _getTaxRate(_tokenPrice);
            if (_taxRate > 0) {
                uint256 _taxAmount = amount.mul(_taxRate).div(10000);
                address _taxFund = taxFund;
                super._transfer(sender, _taxFund, _taxAmount);
                _amount = _amount.sub(_taxAmount);
                _totalTaxAdded = _totalTaxAdded.add(_taxAmount);
                if (addLiquidityEnabled) {
                    ILiquidityFund(_taxFund).addLiquidity(_taxAmount);
                }
                emit TaxAdded(sender, _taxFund, _taxAmount);
            }

            uint256 _burnRate = _getBurnRate(_tokenPrice);
            if (_burnRate > 0) {
                uint256 _burnAmount = amount.mul(_burnRate).div(10000);
                _burn(sender, _burnAmount);
                _amount = _amount.sub(_burnAmount);
            }
        }

        super._transfer(sender, recipient, _amount);

        _updateDollarPrice();
    }

    function _getBurnRate(uint256 _tokenPrice) internal returns (uint256) {
        for (
            uint8 tierId = uint8(getTiersTwapsCount()).sub(1);
            tierId >= 0;
            --tierId
        ) {
            if (_tokenPrice >= tiersTwaps[tierId]) {
                require(
                    burnTiersRates[tierId] <= 1500,
                    "allowed maximum burn rate 15%"
                );
                burnRate = burnTiersRates[tierId];
                return burnTiersRates[tierId];
            }
        }
    }

    function _getTaxRate(uint256 _tokenPrice) internal returns (uint256) {
        for (
            uint8 tierId = uint8(getTiersTwapsCount()).sub(1);
            tierId >= 0;
            --tierId
        ) {
            if (_tokenPrice >= tiersTwaps[tierId]) {
                require(
                    taxTiersRates[tierId] <= 1500,
                    "allowed maximum burn rate 15%"
                );
                taxRate = taxTiersRates[tierId];
                return taxTiersRates[tierId];
            }
        }
    }

    /* ========== EMERGENCY ========== */

    function governanceRecoverUnsupported(address _token, address _to)
        external
        onlyOperator
    {
        IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
    }
}
