// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./access/Operator.sol";

/*
    https://snowcrystals.finance
*/
contract Glcr is ERC20, ERC20Burnable, Operator {
    using SafeMath for uint256;

    /*
        TOTAL MAX SUPPLY = 68,000 GLCR
        - 50000 GLCRs allocated to farming pools
        - Airdop 500 GLCRs allocated to DAO wallet
        - Allocate 11500 GLCRs to DAO wallet for linear vesting
        - Airdrop 10 GLCRs to Dev wallet
        - Allocate 5990 GLCRs to Dev wallet for linear vesting
    */
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 50000 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 11500 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 5990 ether;

    uint256 public constant VESTING_DURATION = 52 weeks;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    bool public rewardPoolDistributed = false;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _startTime,
        address _daoFund,
        address _devFund
    ) public ERC20(name_, symbol_) {
        _mint(msg.sender, 2 ether); // mint 2 Walrus Share for initial pools deployment and Boardroom initialization
        _mint(_daoFund, 500 ether); // Airdop 500 WSHAREs allocated to DAO wallet
        _mint(_devFund, 10 ether); // Airdop 360 WSHAREs allocated to DEV wallet

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate =
            COMMUNITY_FUND_POOL_ALLOCATION /
            (VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION / (VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_daoFund != address(0), "Address cannot be 0");
        communityFund = _daoFund;
    }

    function setTreasuryFund(address _daoFund) external {
        require(msg.sender == devFund, "!dev");
        communityFund = _daoFund;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(
            communityFundRewardRate
        );
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && communityFund != address(0)) {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund)
        external
        onlyOperator
    {
        require(!rewardPoolDistributed, "only can distribute once");
        require(
            _farmingIncentiveFund != address(0) &&
                _farmingIncentiveFund != address(this),
            "!_farmingIncentiveFund"
        );
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
    }
}
