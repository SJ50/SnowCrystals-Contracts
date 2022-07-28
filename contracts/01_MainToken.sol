// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./access/Operator.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILiquidityFund.sol";

/*
    https://snowcrystals.finance
*/

contract Snow is ERC20, ERC20Burnable, Operator {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // Initial distribution for the first 48h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 24000 ether;
    // Distribution for airdrops wallet
    uint256 public constant INITIAL_DAO_WALLET_DISTRIBUTION = 1000 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;
    bool public addLiquidityEnabled = false;

    address public oracle;

    uint256 public burnRate;
    uint256 public burnRateAbovePeg;
    uint256 public taxRate; // buy back  Token and add liquidity
    uint256 public taxRateAbovePeg;
    address public taxFund; // fund buy back Token

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
        taxFund = _taxFund;
        burnRate = 800;
        burnRateAbovePeg = 400;
        taxRate = 800;
        taxRateAbovePeg = 200;
        enableUpdatePrice = true;
        // Mints 10 SNOW to contract creator for initial pool setup
        _mint(msg.sender, 10 ether);
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

    /* ========== Modifiers =============== */

    /* ============= Taxation ============= */
    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function toggleAddLiquidityEnabled() external onlyOwner {
        addLiquidityEnabled = !addLiquidityEnabled;
    }

    function setBurnRate(uint256 _burnRate) external onlyOwner {
        require(_burnRate <= 1500, "too high"); // <= 15%
        burnRate = _burnRate;
    }

    function setTaxRate(uint256 _taxRate) external onlyOwner {
        require(_taxRate <= 1500, "too high"); // <= 15%
        taxRate = _taxRate;
    }

    function setBurnRateAbovePeg(uint256 _burnRateAbovePeg) external onlyOwner {
        require(_burnRateAbovePeg <= 1500, "too high"); // <= 15%
        burnRateAbovePeg = _burnRateAbovePeg;
    }

    function setTaxRateAbovePeg(uint256 _taxRateAbovePeg) external onlyOwner {
        require(_taxRateAbovePeg <= 1500, "too high"); // <= 15%
        taxRateAbovePeg = _taxRateAbovePeg;
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
            {
                uint256 _taxRate = getTaxRate(_tokenPrice);
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
            }
            {
                uint256 _burnRate = getBurnRate(_tokenPrice);
                if (_burnRate > 0) {
                    uint256 _burnAmount = amount.mul(_burnRate).div(10000);
                    _burn(sender, _burnAmount);
                    _amount = _amount.sub(_burnAmount);
                }
            }
        }

        super._transfer(sender, recipient, _amount);

        _updateDollarPrice();
    }

    function getTaxRate(uint256 _tokenPrice) public view returns (uint256) {
        if (_tokenPrice < 1e18) {
            return taxRate;
        }
        if (_tokenPrice > 1e18 && _tokenPrice < 1.5e18) {
            return taxRateAbovePeg;
        }
    }

    function getBurnRate(uint256 _tokenPrice) public view returns (uint256) {
        if (_tokenPrice < 1e18) {
            return burnRate;
        }
        if (_tokenPrice > 1e18 && _tokenPrice < 1.5e18) {
            return burnRateAbovePeg;
        }
    }

    /* ========== EMERGENCY ========== */

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }
}
