// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./utils/ERC20Taxable.sol";

/* 
    https://snowcrystals.finance
*/

contract Snow is ERC20Taxable {
    using SafeMath for uint256;

    // Initial distribution for the first 48h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 24_000 ether;
    // Distribution for airdrops wallet
    uint256 public constant INITIAL_DAO_WALLET_DISTRIBUTION = 1_000 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    uint256 public totalBurned;

    /**
     * @notice Constructs the SNOW ERC-20 contract.
     */
    constructor(string memory name_, string memory symbol_)
        public
        ERC20Taxable(name_, symbol_)
    {
        // Mints 1_000 SNOW to contract creator for initial pool setup.
        _mint(msg.sender, 1_000 ether);
    }

    //* ========== EVENTS ========== *//

    event TokenBurned(address indexed account, uint256 amount);

    //*================ BASIC TOKEN FUNCTIONS ================*//
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

    //* ========== OVERRIDE STANDARD FUNCTIONS ========== *//

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
        totalBurned = totalBurned.add(_amount);
        emit TokenBurned(_account, _amount);
    }

    //*================ TOKEN DISTRIBUTION / RECOVERY ================*//
    function distributeReward(address _genesisPool, address _daoWallet)
        external
        onlyOperator
    {
        require(!rewardPoolDistributed, "Error: can only distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        require(_daoWallet != address(0), "!_daoWallet");

        rewardPoolDistributed = true; //State change before minting additional tokens.

        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
        _mint(_daoWallet, INITIAL_DAO_WALLET_DISTRIBUTION);
    }

    //*================ TAX FUNCTIONS ================*//

    function _updateDynamicTaxRate() internal override {
        dynamicTaxRate = ITaxOffice(taxOffice).calculateMainTokenTax();
    }

    function _handleTax(address _sender, uint256 _amount) internal override {
        uint256 _burnAmount = _amount.mul(80).div(100);
        _burn(_sender, _burnAmount);

        uint256 _taxAmount = _amount.sub(_burnAmount);
        _approve(_sender, taxOffice, _taxAmount);
        //Use inherited function to transferFrom.
        ERC20.transferFrom(_sender, taxOffice, _taxAmount);
        ITaxOffice(taxOffice).handleMainTokenTax(_taxAmount);
    }
}
