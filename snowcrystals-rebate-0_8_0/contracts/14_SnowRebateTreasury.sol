// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/lib/IUniswapV2Pair.sol";

contract SnowRebateTreasury is Ownable {
    struct Asset {
        bool isAdded;
        uint256 multiplier; // 1100000 for 1.1 (10% discount if discount set to zero)
        address oracle;
        bool isLP;
        address pair;
    }

    struct VestingSchedule {
        uint256 amount;
        uint256 period;
        uint256 end;
        uint256 claimed;
        uint256 lastClaimed;
    }

    IERC20 public Snow;
    IOracle public SnowOracle;
    ITreasury public Treasury;

    mapping(address => Asset) public assets;
    mapping(address => VestingSchedule) public vesting;

    uint256 public discount; // 100000 for 10% discount or 1.1
    bool staticPremiumEnabled = true;

    uint256 public bondThreshold = 20 * 1e4;
    uint256 public bondFactor = 80 * 1e4;
    uint256 public secondaryThreshold = 70 * 1e4;
    uint256 public secondaryFactor = 15 * 1e4;

    uint256 public bondVesting = 1 days;
    uint256 public totalVested = 0;

    uint256 public lastBuyback;
    uint256 public buybackAmount = 10 * 1e4;

    address public immutable USDC;
    uint256 public constant DENOMINATOR = 1e6;

    address public daoOperator;

    /*
     * ---------
     * MODIFIERS
     * ---------
     */

    // Only allow a function to be called with a bondable asset

    modifier onlyAsset(address _token) {
        require(
            assets[_token].isAdded,
            "RebateTreasury: token is not a bondable asset"
        );
        _;
    }

    modifier onlyDaoOperator() {
        require(
            daoOperator == msg.sender,
            "RebateTreasury: caller is not the operator"
        );
        _;
    }

    /*
     * ------------------
     * EXTERNAL FUNCTIONS
     * ------------------
     */

    // Initialize parameters

    constructor(
        address _snow,
        address _snowOracle,
        address _treasury,
        address _usdc
    ) {
        Snow = IERC20(_snow);
        SnowOracle = IOracle(_snowOracle);
        Treasury = ITreasury(_treasury);
        USDC = _usdc;
        daoOperator = msg.sender;
    }

    function daoFund() external view returns (address) {
        return Treasury.daoFund();
    }

    function setDaoOperator(address _operator) external onlyOwner {
        daoOperator = _operator;
    }

    // Bond asset for discounted Snow at bond rate

    function bond(address _token, uint256 _amount) external onlyAsset(_token) {
        require(_amount > 0, "RebateTreasury: invalid bond amount");
        uint256 snowAmount = getSnowReturn(_token, _amount);
        require(
            snowAmount <= Snow.balanceOf(address(this)) - totalVested,
            "RebateTreasury: insufficient snow balance"
        );

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        _claimVested(msg.sender);

        VestingSchedule storage schedule = vesting[msg.sender];
        schedule.amount = schedule.amount - schedule.claimed + snowAmount;
        schedule.period = bondVesting;
        schedule.end = block.timestamp + bondVesting;
        schedule.claimed = 0;
        schedule.lastClaimed = block.timestamp;
        totalVested += snowAmount;
    }

    // Claim available Snow rewards from bonding

    function claimRewards() external {
        _claimVested(msg.sender);
    }

    /*
     * --------------------
     * RESTRICTED FUNCTIONS
     * --------------------
     */

    // Set Snow token

    function setSnow(address _snow) external onlyOwner {
        Snow = IERC20(_snow);
    }

    // Set Snow oracle

    function setSnowOracle(address _oracle) external onlyOwner {
        SnowOracle = IOracle(_oracle);
    }

    // Set Snow treasury

    function setTreasury(address _treasury) external onlyOwner {
        Treasury = ITreasury(_treasury);
    }

    // Set bonding parameters of token

    function setAsset(
        address _token,
        bool _isAdded,
        uint256 _multiplier,
        address _oracle,
        bool _isLP,
        address _pair
    ) external onlyOwner {
        require(_multiplier >= 1e6);
        assets[_token].isAdded = _isAdded;
        assets[_token].multiplier = _multiplier;
        assets[_token].oracle = _oracle;
        assets[_token].isLP = _isLP;
        assets[_token].pair = _pair;
    }

    // Set bond pricing parameters

    function setBondParameters(
        uint256 _primaryThreshold,
        uint256 _primaryFactor,
        uint256 _secondThreshold,
        uint256 _secondFactor,
        uint256 _vestingPeriod,
        uint256 _discount,
        bool _staticPremiumEnabled
    ) external onlyOwner {
        bondThreshold = _primaryThreshold;
        bondFactor = _primaryFactor;
        secondaryThreshold = _secondThreshold;
        secondaryFactor = _secondFactor;
        bondVesting = _vestingPeriod;
        discount = _discount;
        staticPremiumEnabled = _staticPremiumEnabled;
    }

    // Redeem assets for buyback

    function redeemAssetsForBuyback(address[] calldata _tokens)
        external
        onlyDaoOperator
    {
        uint256 epoch = Treasury.epoch();
        require(lastBuyback != epoch, "RebateTreasury: already bought back");
        lastBuyback = epoch;

        for (uint256 t = 0; t < _tokens.length; t++) {
            require(
                assets[_tokens[t]].isAdded,
                "RebateTreasury: invalid token"
            );
            IERC20 Token = IERC20(_tokens[t]);
            Token.transfer(Treasury.daoFund(), Token.balanceOf(address(this)));
        }
    }

    /*
     * ------------------
     * INTERNAL FUNCTIONS
     * ------------------
     */

    function _claimVested(address _account) internal {
        VestingSchedule storage schedule = vesting[_account];
        if (schedule.amount == 0 || schedule.amount == schedule.claimed) return;
        if (
            block.timestamp <= schedule.lastClaimed ||
            schedule.lastClaimed >= schedule.end
        ) return;

        uint256 duration = (
            block.timestamp > schedule.end ? schedule.end : block.timestamp
        ) - schedule.lastClaimed;
        uint256 claimable = (schedule.amount * duration) / schedule.period;
        if (claimable == 0) return;

        schedule.claimed += claimable;
        schedule.lastClaimed = block.timestamp > schedule.end
            ? schedule.end
            : block.timestamp;
        totalVested -= claimable;
        Snow.transfer(_account, claimable);
    }

    /*
     * --------------
     * VIEW FUNCTIONS
     * --------------
     */

    // Calculate Snow return of bonding amount of token

    function getSnowReturn(address _token, uint256 amount)
        public
        view
        onlyAsset(_token)
        returns (uint256)
    {
        uint256 snowPrice = getSnowPrice();
        uint256 tokenPrice = getTokenPrice(_token);
        uint256 bondPremium = getBondPremium();
        uint256 decimalsMultiplier = 10 **
            (18 - IERC20Metadata(_token).decimals());
        return
            (_amount * decimalsMultiplier * tokenPrice * bondPremium) /
            snowPrice;
    }

    // Calculate premium for bonds based on bonding curve

    function getBondPremium(address _token)
        public
        view
        onlyAsset(_token)
        returns (uint256)
    {
        if (staticPremiumEnabled) {
            return
                ((discount + DENOMINATOR) * assets[_token].multiplier) /
                (DENOMINATOR * DENOMINATOR);
        }
        uint256 premium;
        uint256 snowPrice = getSnowPrice();
        if (snowPrice < 1e18) return 0;

        uint256 snowPremium = (snowPrice * DENOMINATOR) / 1e18 - DENOMINATOR;
        if (snowPremium < bondThreshold) return 0;
        if (snowPremium <= secondaryThreshold) {
            premium =
                ((snowPremium - bondThreshold) * bondFactor) /
                DENOMINATOR;
        } else {
            uint256 primaryPremium = ((secondaryThreshold - bondThreshold) *
                bondFactor) / DENOMINATOR;
            premium =
                primaryPremium +
                ((snowPremium - secondaryThreshold) * secondaryFactor) /
                DENOMINATOR;
        }
        return
            ((premium + DENOMINATOR) * assets[_token].multiplier) /
            (DENOMINATOR * DENOMINATOR);
    }

    // Get SNOW price from Oracle

    function getSnowPrice() public view returns (uint256) {
        return SnowOracle.consult(address(Snow), 1e18);
    }

    // Get token price from Oracle

    function getTokenPrice(address _token)
        public
        view
        onlyAsset(_token)
        returns (uint256)
    {
        Asset memory asset = assets[_token];
        IOracle Oracle = IOracle(asset.oracle);
        if (!asset.isLP) {
            return Oracle.consult(_token, 1e18);
        }

        IUniswapV2Pair Pair = IUniswapV2Pair(asset.pair);
        uint256 totalPairSupply = Pair.totalSupply();
        address token0 = Pair.token0();
        address token1 = Pair.token1();
        (uint256 reserve0, uint256 reserve1, ) = Pair.getReserves();

        if (token1 == USDC) {
            uint256 tokenPrice = Oracle.consult(token0, 1e18);
            return
                (tokenPrice * reserve0) /
                totalPairSupply +
                (reserve1 * 1e18) /
                totalPairSupply;
        } else {
            uint256 tokenPrice = Oracle.consult(token1, 1e18);
            return
                (tokenPrice * reserve1) /
                totalPairSupply +
                (reserve0 * 1e18) /
                totalPairSupply;
        }
    }

    // Get claimable vested Snow for account
    function claimableSnow(address _account) external view returns (uint256) {
        VestingSchedule memory schedule = vesting[_account];
        if (
            block.timestamp <= schedule.lastClaimed ||
            schedule.lastClaimed >= schedule.end
        ) return 0;
        uint256 duration = (
            block.timestamp > schedule.end ? schedule.end : block.timestamp
        ) - schedule.lastClaimed;
        return (schedule.amount * duration) / schedule.period;
    }
}
