// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./access/Operator.sol";
import "./utils/ContractGuard.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/IBoardroom.sol";
import "../interfaces/IERC20Taxable.sol";
import "../interfaces/ITaxOffice.sol";

/*
    https://snowcrystals.finance
*/
contract Treasury is ContractGuard, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply;

    // core components
    address public snow;
    address public sBond;
    address public glcr;

    address public boardroom;
    address public snowOracle;

    // price
    uint256 public snowPriceOne;
    uint256 public snowPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochSnowPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra Snow during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address private devFund;
    uint256 public devFundSharedPercent;

    /* =================== Added variables =================== */

    address public taxOffice;

    uint256 public minExpansion;
    uint256 public fixedExpansion;
    uint256 public expansionFactor;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(
        address indexed from,
        uint256 snowAmount,
        uint256 bondAmount
    );
    event BoughtBonds(
        address indexed from,
        uint256 snowAmount,
        uint256 bondAmount
    );
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);


    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition() {
        require(now >= startTime, "Treasury: not started yet");
        _;
    }

    modifier checkEpoch() {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getSnowPrice() > snowPriceCeiling)
            ? 0
            : getSnowCirculatingSupply().mul(maxSupplyContractionPercent).div(
                10000
            );
    }

    modifier checkOperator() {
        require(
            IERC20Taxable(snow).operator() == address(this) &&
                IERC20Taxable(sBond).operator() == address(this) &&
                IERC20Taxable(glcr).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getSnowPrice() public view returns (uint256 snowPrice) {
        try IOracle(snowOracle).consult(snow, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult SNOW price from the oracle");
        }
    }

    function getSnowUpdatedPrice() public view returns (uint256 _snowPrice) {
        try IOracle(snowOracle).twap(snow, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult Snow price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableSnowLeft()
        public
        view
        returns (uint256 _burnableSnowLeft)
    {
        uint256 _snowPrice = getSnowPrice();
        if (_snowPrice <= snowPriceOne) {
            uint256 _snowSupply = getSnowCirculatingSupply();
            uint256 _bondMaxSupply = _snowSupply.mul(maxDebtRatioPercent).div(
                10000
            );
            uint256 _bondSupply = IERC20(sBond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableSnow = _maxMintableBond.mul(_snowPrice).div(
                    1e18
                );
                _burnableSnowLeft = Math.min(
                    epochSupplyContractionLeft,
                    _maxBurnableSnow
                );
            }
        }
    }

    function getRedeemableBonds()
        public
        view
        returns (uint256 _redeemableBonds)
    {
        uint256 _snowPrice = getSnowPrice();
        if (_snowPrice > snowPriceCeiling) {
            uint256 _totalSnow = IERC20(snow).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalSnow.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _snowPrice = getSnowPrice();
        if (_snowPrice <= snowPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = snowPriceOne;
            } else {
                uint256 _bondAmount = snowPriceOne.mul(1e18).div(_snowPrice); // to burn 1 Snow
                uint256 _discountAmount = _bondAmount
                    .sub(snowPriceOne)
                    .mul(discountPercent)
                    .div(10000);
                _rate = snowPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _snowPrice = getSnowPrice();
        if (_snowPrice > snowPriceCeiling) {
            uint256 _snowPricePremiumThreshold = snowPriceOne
                .mul(premiumThreshold)
                .div(100);
            if (_snowPrice >= _snowPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _snowPrice
                    .sub(snowPriceOne)
                    .mul(premiumPercent)
                    .div(10000);
                _rate = snowPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = snowPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _snow,
        address _sBond,
        address _glcr,
        address _snowOracle,
        address _boardroom,
        uint256 _startTime,
        address _taxOffice,
        address[] memory _excludedFromTotalSupply
    ) public notInitialized {
        snow = _snow;
        sBond = _sBond;
        glcr = _glcr;
        snowOracle = _snowOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        taxOffice = _taxOffice;
        excludedFromTotalSupply = _excludedFromTotalSupply;

        snowPriceOne = 10**17; // This is to allow a PEG of 10 Snow per USDC
        snowPriceCeiling = snowPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [
            0 ether,
            500_000 ether,
            2_000_000 ether,
            4_000_000 ether,
            8_000_000 ether,
            20_000_000 ether
        ];
        maxExpansionTiers = [300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn Snow and mint BondToken)
        maxDebtRatioPercent = 4000; // Upto 40% supply of BOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 4% expansion
        bootstrapEpochs = 28;
        bootstrapSupplyExpansionPercent = 400;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(snow).balanceOf(address(this));

        minExpansion = 10**16;
        expansionFactor = 150;

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setSnowOracle(address _snowOracle) external onlyOperator {
        snowOracle = _snowOracle;
    }

    function setTaxOffice(address _taxOffice) external onlyOperator {
        taxOffice = _taxOffice;
    }

    function setSnowPriceCeiling(uint256 _snowPriceCeiling)
        external
        onlyOperator
    {
        require(
            _snowPriceCeiling >= snowPriceOne &&
                _snowPriceCeiling <= snowPriceOne.mul(120).div(100),
            "out of range"
        ); // [$0.1, $0.12]
        snowPriceCeiling = _snowPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent)
        external
        onlyOperator
    {
        require(
            _maxSupplyExpansionPercent >= 10 &&
                _maxSupplyExpansionPercent <= 1000,
            "_maxSupplyExpansionPercent: out of range"
        ); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        require(_index >= 0, "Index has to be higher than 0");
        require(
            _index < supplyTiers.length,
            "Index has to be lower than count of tiers"
        );
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < supplyTiers.length - 1) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        require(_index >= 0, "Index has to be higher than 0");
        require(
            _index < maxExpansionTiers.length,
            "Index has to be lower than count of tiers"
        );
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setMinExpansion(uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        minExpansion = _value;
        return true;
    }

    function setFixedExpansion(uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        fixedExpansion = _value;
        return true;
    }

    function setExpansionFactor(uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        expansionFactor = _value;
        return true;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent)
        external
        onlyOperator
    {
        require(
            _bondDepletionFloorPercent >= 500 &&
                _bondDepletionFloorPercent <= 10000,
            "out of range"
        ); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(
        uint256 _maxSupplyContractionPercent
    ) external onlyOperator {
        require(
            _maxSupplyContractionPercent >= 100 &&
                _maxSupplyContractionPercent <= 1500,
            "out of range"
        ); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent)
        external
        onlyOperator
    {
        require(
            _maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000,
            "out of range"
        ); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(
        uint256 _bootstrapEpochs,
        uint256 _bootstrapSupplyExpansionPercent
    ) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(
            _bootstrapSupplyExpansionPercent >= 100 &&
                _bootstrapSupplyExpansionPercent <= 1000,
            "_bootstrapSupplyExpansionPercent: out of range"
        ); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent,

 
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
       
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
 
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate)
        external
        onlyOperator
    {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent)
        external
        onlyOperator
    {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold)
        external
        onlyOperator
    {
        require(
            _premiumThreshold >= snowPriceCeiling,
            "_premiumThreshold exceeds snowPriceCeiling"
        );
        require(
            _premiumThreshold <= 150,
            "_premiumThreshold is higher than 1.5"
        );
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt)
        external
        onlyOperator
    {
        require(
            _mintingFactorForPayingDebt >= 10000 &&
                _mintingFactorForPayingDebt <= 20000,
            "_mintingFactorForPayingDebt: out of range"
        ); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateSnowPrice() internal {
        try IOracle(snowOracle).update() {} catch {}
    }

    function getSnowCirculatingSupply() public view returns (uint256) {
        IERC20 snowErc20 = IERC20(snow);
        uint256 totalSupply = snowErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (
            uint8 entryId = 0;
            entryId < excludedFromTotalSupply.length;
            ++entryId
        ) {
            balanceExcluded = balanceExcluded.add(
                snowErc20.balanceOf(excludedFromTotalSupply[entryId])
            );
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _snowAmount, uint256 targetPrice)
        external
        onlyOneBlock
        checkCondition
        checkOperator
        nonReentrant
    {
        require(
            _snowAmount > 0,
            "Treasury: cannot purchase bonds with zero amount"
        );

        uint256 snowPrice = getSnowPrice();
        require(snowPrice == targetPrice, "Treasury: Snow price moved");
        require(
            snowPrice < snowPriceOne, // price < $0.1
            "Treasury: snowPrice not eligible for bond purchase"
        );

        require(
            _snowAmount <= epochSupplyContractionLeft,
            "Treasury: not enough bond left to purchase"
        );

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _snowAmount.mul(_rate).div(1e18);
        uint256 snowSupply = getSnowCirculatingSupply();
        uint256 newBondSupply = IERC20(sBond).totalSupply().add(_bondAmount);
        require(
            newBondSupply <= snowSupply.mul(maxDebtRatioPercent).div(10000),
            "over max debt ratio"
        );

        IERC20Taxable(snow).burnFrom(msg.sender, _snowAmount);
        IERC20Taxable(sBond).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(
            _snowAmount
        );
        _updateSnowPrice();

        emit BoughtBonds(msg.sender, _snowAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice)
        external
        onlyOneBlock
        checkCondition
        checkOperator
        nonReentrant
    {
        require(
            _bondAmount > 0,
            "Treasury: cannot redeem bonds with zero amount"
        );

        uint256 snowPrice = getSnowPrice();
        require(snowPrice == targetPrice, "Treasury: Snow price moved");
        require(
            snowPrice > snowPriceCeiling, // price > $0.101
            "Treasury: snowPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _snowAmount = _bondAmount.mul(_rate).div(1e18);
        require(
            IERC20(snow).balanceOf(address(this)) >= _snowAmount,
            "Treasury: treasury has no more budget"
        );

        seigniorageSaved = seigniorageSaved.sub(
            Math.min(seigniorageSaved, _snowAmount)
        );

        IERC20Taxable(sBond).burnFrom(msg.sender, _bondAmount);
        IERC20(snow).safeTransfer(msg.sender, _snowAmount);

        _updateSnowPrice();

        emit RedeemedBonds(msg.sender, _snowAmount, _bondAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IERC20Taxable(snow).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(snow).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(snow).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(snow).safeIncreaseAllowance(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(now, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _snowSupply)
        internal
        returns (uint256)
    {
        for (
            uint8 tierId = uint8(supplyTiers.length - 1);
            tierId >= 0;
            --tierId
        ) {
            if (_snowSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function getExpansionPercent() public view returns (uint256) {
        uint256 prevEpochSnowPrice = getSnowPrice();
        uint256 _percentage = prevEpochSnowPrice.sub(snowPriceOne);
        uint256 _mse = maxSupplyExpansionPercent.mul(1e14);

        if (fixedExpansion != 0) {
            return fixedExpansion;
        }

        if (expansionFactor != 0) {
            _percentage = _percentage.mul(expansionFactor).div(10000);
        }

        if (minExpansion > _percentage) {
            _percentage = minExpansion;
        }

        if (_percentage > _mse) {
            _percentage = _mse;
        }

        return _percentage;
    }

    function allocateSeigniorage()
        external
        onlyOneBlock
        checkCondition
        checkEpoch
        checkOperator
        nonReentrant
    {
        _updateSnowPrice();
        previousEpochSnowPrice = getSnowPrice();
        uint256 snowSupply = getSnowCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 20 first epochs with 4% expansion
            _sendToBoardroom(
                snowSupply.mul(bootstrapSupplyExpansionPercent).div(10000)
            );
        } else {
            if (previousEpochSnowPrice > snowPriceCeiling) {
                // Expansion (Snow Price > 0.1 $USDC): there is some seigniorage to be allocated
                _calculateMaxSupplyExpansionPercent(snowSupply);
                uint256 bondSupply = IERC20(sBond).totalSupply();
                uint256 _percentage = getExpansionPercent();
                uint256 _savedForBond;
                uint256 _savedForBoardroom;

                if (
                    seigniorageSaved >=
                    bondSupply.mul(bondDepletionFloorPercent).div(10000)
                ) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = snowSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = snowSupply.mul(_percentage).div(
                        1e18
                    );
                    _savedForBoardroom = _seigniorage
                        .mul(seigniorageExpansionFloorPercent)
                        .div(10000);
                    _savedForBond = _seigniorage.sub(_savedForBoardroom);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond
                            .mul(mintingFactorForPayingDebt)
                            .div(10000);
                    }
                }
                if (_savedForBoardroom > 0) {
                    _sendToBoardroom(_savedForBoardroom);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IERC20Taxable(snow).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond);
                }
            }
        }
        ITaxOffice(taxOffice).sendToBonus(
            previousEpochSnowPrice,
            snowPriceCeiling,
            nextEpochPoint()
        );
    }

    function governanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(snow), "snow");
        require(address(_token) != address(sBond), "bond");
        require(address(_token) != address(glcr), "share");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /** 
    Boardroom governance
    **/

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetLockUp(
        uint256 _withdrawLockupEpochs,
        uint256 _rewardLockupEpochs
    ) external onlyOperator {
        IBoardroom(boardroom).setLockUp(
            _withdrawLockupEpochs,
            _rewardLockupEpochs
        );
    }

    function boardroomAllocateSeigniorage(uint256 amount)
        external
        onlyOperator
    {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(
            _token,
            _amount,
            _to
        );
    }

    /** 
    Snow token contract governance
    **/
    function setSnowTaxOffice(address _taxOffice) external onlyOperator {
        IERC20Taxable(snow).setTaxOffice(_taxOffice);
    }

    function setGlcrTaxOffice(address _taxOffice) external onlyOperator {
        IERC20Taxable(glcr).setTaxOffice(_taxOffice);
    }

    function snowGovernanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IERC20Taxable(snow).governanceRecoverUnsupported(_token, _amount, _to);
    }

    function glcrGovernanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IERC20Taxable(glcr).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
