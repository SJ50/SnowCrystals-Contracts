// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/lib/IUniswapV2Pair.sol";

contract SnowRebateTreasury is Ownable {
    struct Asset {
        bool isAdded;
        uint256 multiplier;
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

    uint256 public bondThreshold = 20 * 1e4;
    uint256 public bondFactor = 80 * 1e4;
    uint256 public secondaryThreshold = 70 * 1e4;
    uint256 public secondaryFactor = 15 * 1e4;

    uint256 public bondVesting = 3 days;
    uint256 public totalVested = 0;

    uint256 public lastBuyback;
    uint256 public buybackAmount = 10 * 1e4;

    address public constant USDC = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59;
    uint256 public constant DENOMINATOR = 1e6;

    address public daoOperator;

    /*
     * ---------
     * MODIFIERS
     * ---------
     */

    // Only allow a function to be called with a bondable asset

    modifier onlyAsset(address token) {
        require(
            assets[token].isAdded,
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
        address snow,
        address snowOracle,
        address treasury
    ) {
        Snow = IERC20(snow);
        SnowOracle = IOracle(snowOracle);
        Treasury = ITreasury(treasury);
        daoOperator = msg.sender;
    }

    function daoFund() external view returns (address) {
        return Treasury.daoFund();
    }

    function setDaoOperator(address operator) external onlyOwner {
        daoOperator = operator;
    }

    // Bond asset for discounted Snow at bond rate

    function bond(address token, uint256 amount) external onlyAsset(token) {
        require(amount > 0, "RebateTreasury: invalid bond amount");
        uint256 snowAmount = getSnowReturn(token, amount);
        require(
            snowAmount <= Snow.balanceOf(address(this)) - totalVested,
            "RebateTreasury: insufficient snow balance"
        );

        IERC20(token).transferFrom(msg.sender, address(this), amount);
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

    function setSnow(address snow) external onlyOwner {
        Snow = IERC20(snow);
    }

    // Set Snow oracle

    function setSnowOracle(address oracle) external onlyOwner {
        SnowOracle = IOracle(oracle);
    }

    // Set Snow treasury

    function setTreasury(address treasury) external onlyOwner {
        Treasury = ITreasury(treasury);
    }

    // Set bonding parameters of token

    function setAsset(
        address token,
        bool isAdded,
        uint256 multiplier,
        address oracle,
        bool isLP,
        address pair
    ) external onlyOwner {
        assets[token].isAdded = isAdded;
        assets[token].multiplier = multiplier;
        assets[token].oracle = oracle;
        assets[token].isLP = isLP;
        assets[token].pair = pair;
    }

    // Set bond pricing parameters

    function setBondParameters(
        uint256 primaryThreshold,
        uint256 primaryFactor,
        uint256 secondThreshold,
        uint256 secondFactor,
        uint256 vestingPeriod
    ) external onlyOwner {
        bondThreshold = primaryThreshold;
        bondFactor = primaryFactor;
        secondaryThreshold = secondThreshold;
        secondaryFactor = secondFactor;
        bondVesting = vestingPeriod;
    }

    // Redeem assets for buyback

    function redeemAssetsForBuyback(address[] calldata tokens)
        external
        onlyDaoOperator
    {
        uint256 epoch = Treasury.epoch();
        require(lastBuyback != epoch, "RebateTreasury: already bought back");
        lastBuyback = epoch;

        for (uint256 t = 0; t < tokens.length; t++) {
            require(assets[tokens[t]].isAdded, "RebateTreasury: invalid token");
            IERC20 Token = IERC20(tokens[t]);
            Token.transfer(Treasury.daoFund(), Token.balanceOf(address(this)));
        }
    }

    /*
     * ------------------
     * INTERNAL FUNCTIONS
     * ------------------
     */

    function _claimVested(address account) internal {
        VestingSchedule storage schedule = vesting[account];
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
        Snow.transfer(account, claimable);
    }

    /*
     * --------------
     * VIEW FUNCTIONS
     * --------------
     */

    // Calculate Snow return of bonding amount of token

    function getSnowReturn(address token, uint256 amount)
        public
        view
        onlyAsset(token)
        returns (uint256)
    {
        uint256 snowPrice = getSnowPrice();
        uint256 tokenPrice = getTokenPrice(token);
        uint256 bondPremium = getBondPremium();
        uint256 decimalsMultiplier = token == USDC ? 1e12 : 1;
        return
            (amount *
                decimalsMultiplier *
                tokenPrice *
                (bondPremium + DENOMINATOR) *
                assets[token].multiplier) /
            (DENOMINATOR * DENOMINATOR) /
            snowPrice;
    }

    // Calculate premium for bonds based on bonding curve

    function getBondPremium() public view returns (uint256) {
        uint256 snowPrice = getSnowPrice();
        if (snowPrice < 1e18) return 0;

        uint256 snowPremium = (snowPrice * DENOMINATOR) / 1e18 - DENOMINATOR;
        if (snowPremium < bondThreshold) return 0;
        if (snowPremium <= secondaryThreshold) {
            return ((snowPremium - bondThreshold) * bondFactor) / DENOMINATOR;
        } else {
            uint256 primaryPremium = ((secondaryThreshold - bondThreshold) *
                bondFactor) / DENOMINATOR;
            return
                primaryPremium +
                ((snowPremium - secondaryThreshold) * secondaryFactor) /
                DENOMINATOR;
        }
    }

    // Get SNOW price from Oracle

    function getSnowPrice() public view returns (uint256) {
        return SnowOracle.consult(address(Snow), 1e18);
    }

    // Get token price from Oracle

    function getTokenPrice(address token)
        public
        view
        onlyAsset(token)
        returns (uint256)
    {
        Asset memory asset = assets[token];
        IOracle Oracle = IOracle(asset.oracle);
        if (!asset.isLP) {
            return Oracle.consult(token, 1e18);
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
    function claimableSnow(address account) external view returns (uint256) {
        VestingSchedule memory schedule = vesting[account];
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
