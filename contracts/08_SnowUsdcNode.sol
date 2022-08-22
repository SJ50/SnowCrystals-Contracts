// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IBonusRewards.sol";

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

/*
    https://snowcrystals.finance
*/

contract MainTokenNode {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public TOKEN;
    uint256[] public tierAllocPoints = [1 ether, 1 ether, 1 ether];
    uint256[] public tierAmounts = [0.00002 ether, 1 ether, 1 ether];
    struct User {
        uint256 total_deposits;
        uint256 total_claims;
        uint256 last_distPoints;
    }

    event CreateNode(uint256 timestamp, address account, uint256 num);

    address private dev;

    mapping(address => User) public users;
    mapping(address => mapping(uint256 => uint256)) public nodes;
    mapping(uint256 => uint256) public totalNodes;
    address[] public userIndices;

    uint256 public total_deposited;
    uint256 public total_claimed;
    uint256 public total_rewards;
    uint256 public treasury_rewards;
    uint256 public treasuryFeePercent;
    uint256 public totalDistributeRewards;
    uint256 public totalDistributePoints;
    uint256 public maxReturnPercent;
    uint256 public dripRate;
    uint256 public lastDripTime;
    uint256 public startTime;
    bool public enabled;
    uint256 public constant MULTIPLIER = 10e18;

    address public bonusreward;

    constructor(
        uint256 _startTime,
        address _token,
        address _bonusrewards
    ) public {
        maxReturnPercent = 500;
        dripRate = 2100000;
        treasuryFeePercent = 25;

        lastDripTime = _startTime > block.timestamp
            ? _startTime
            : block.timestamp;
        startTime = _startTime;
        enabled = true;
        TOKEN = IERC20(_token);
        dev = msg.sender;
        bonusreward = _bonusrewards;
    }

    receive() external payable {
        revert("Do not send CRO.");
    }

    modifier onlyDev() {
        require(msg.sender == dev, "Caller is not the dev!");
        _;
    }

    function changeDev(address payable newDev) external onlyDev {
        require(newDev != address(0), "Zero address");
        dev = newDev;
    }

    function claimTreasuryRewards() external {
        if (treasury_rewards > 0) {
            TOKEN.safeTransfer(dev, treasury_rewards);
            treasury_rewards = 0;
        }
    }

    function setStartTime(uint256 _startTime) external onlyDev {
        startTime = _startTime;
    }

    function setEnabled(bool _enabled) external onlyDev {
        enabled = _enabled;
    }

    function setTreasuryFeePercent(uint256 percent) external onlyDev {
        treasuryFeePercent = percent;
    }

    function setDripRate(uint256 rate) external onlyDev {
        dripRate = rate;
    }

    function setLastDripTime(uint256 timestamp) external onlyDev {
        lastDripTime = timestamp;
    }

    function setMaxReturnPercent(uint256 percent) external onlyDev {
        maxReturnPercent = percent;
    }

    function setTierValues(
        uint256[] memory _tierAllocPoints,
        uint256[] memory _tierAmounts
    ) external onlyDev {
        require(
            _tierAllocPoints.length == _tierAmounts.length,
            "Length mismatch"
        );
        tierAllocPoints = _tierAllocPoints;
        tierAmounts = _tierAmounts;
    }

    function setUser(address _addr, User memory _user) external onlyDev {
        total_deposited = total_deposited.sub(users[_addr].total_deposits).add(
            _user.total_deposits
        );
        total_claimed = total_claimed.sub(users[_addr].total_claims).add(
            _user.total_claims
        );
        users[_addr].total_deposits = _user.total_deposits;
        users[_addr].total_claims = _user.total_claims;
    }

    function setNodes(address _user, uint256[] memory _nodes) external onlyDev {
        for (uint256 i = 0; i < _nodes.length; i++) {
            totalNodes[i] = totalNodes[i].sub(nodes[_user][i]).add(_nodes[i]);
            nodes[_user][i] = _nodes[i];
        }
    }

    function setBonusReward(address _bonusreward) external onlyDev {
        bonusreward = _bonusreward;
    }

    function totalAllocPoints() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < tierAllocPoints.length; i++) {
            total = total.add(tierAllocPoints[i].mul(totalNodes[i]));
        }
        return total;
    }

    function allocPoints(address account) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < tierAllocPoints.length; i++) {
            total = total.add(tierAllocPoints[i].mul(nodes[account][i]));
        }
        return total;
    }

    function getDistributionRewards(address account)
        public
        view
        returns (uint256)
    {
        if (isMaxPayout(account)) return 0;

        uint256 newDividendPoints = totalDistributePoints.sub(
            users[account].last_distPoints
        );
        uint256 distribute = allocPoints(account).mul(newDividendPoints).div(
            MULTIPLIER
        );
        return distribute > total_rewards ? total_rewards : distribute;
    }

    function getTotalRewards(address _sender) public view returns (uint256) {
        if (users[_sender].total_deposits == 0) return 0;

        uint256 rewards = getDistributionRewards(_sender).add(
            getRewardDrip().mul(allocPoints(_sender)).div(totalAllocPoints())
        );
        uint256 totalClaims = users[_sender].total_claims;
        uint256 maxPay = maxPayout(_sender);

        // Payout remaining if exceeds max payout
        return
            totalClaims.add(rewards) > maxPay
                ? maxPay.sub(totalClaims)
                : rewards;
    }

    function create(uint256 nodeTier, uint256 numNodes) external {
        address _sender = msg.sender;
        require(enabled && block.timestamp >= startTime, "Disabled");
        require(
            nodeTier < tierAllocPoints.length && nodeTier < tierAmounts.length,
            "Invalid nodeTier"
        );

        claim();

        if (users[_sender].total_deposits == 0) {
            userIndices.push(_sender); // New user
            users[_sender].last_distPoints = totalDistributePoints;
        }
        if (users[_sender].total_deposits != 0 && isMaxPayout(_sender)) {
            users[_sender].last_distPoints = totalDistributePoints;
        }

        uint256 tierPrice = tierAmounts[nodeTier].mul(numNodes);

        require(TOKEN.balanceOf(_sender) >= tierPrice, "Insufficient balance");
        require(
            TOKEN.allowance(_sender, address(this)) >= tierPrice,
            "Insufficient allowance"
        );
        TOKEN.safeTransferFrom(_sender, address(this), tierPrice);

        users[_sender].total_deposits = users[_sender].total_deposits.add(
            tierPrice
        );

        total_deposited = total_deposited.add(tierPrice);
        treasury_rewards = treasury_rewards.add(
            tierPrice.mul(treasuryFeePercent).div(100)
        );

        nodes[_sender][nodeTier] = nodes[_sender][nodeTier].add(numNodes);
        totalNodes[nodeTier] = totalNodes[nodeTier].add(numNodes);

        _claimBonus();

        emit CreateNode(block.timestamp, _sender, numNodes);
    }

    function claim() public {
        dripRewards();

        address _sender = msg.sender;
        uint256 _rewards = getDistributionRewards(_sender);

        if (_rewards > 0) {
            uint256 totalClaims = users[_sender].total_claims;
            uint256 maxPay = maxPayout(_sender);

            // Payout remaining if exceeds max payout
            if (totalClaims.add(_rewards) > maxPay) {
                _rewards = maxPay.sub(totalClaims);
            }
            total_rewards = total_rewards.sub(_rewards);

            users[_sender].total_claims = users[_sender].total_claims.add(
                _rewards
            );
            total_claimed = total_claimed.add(_rewards);

            IERC20(TOKEN).safeTransfer(_sender, _rewards);
            _claimBonus();

            users[_sender].last_distPoints = totalDistributePoints;
        }
    }

    function _compound(uint256 nodeTier, uint256 numNodes) internal {
        address _sender = msg.sender;
        require(enabled && block.timestamp >= startTime, "Disabled");
        require(
            nodeTier < tierAllocPoints.length && nodeTier < tierAmounts.length,
            "Invalid nodeTier"
        );

        if (users[_sender].total_deposits == 0) {
            userIndices.push(_sender); // New user
            users[_sender].last_distPoints = totalDistributePoints;
        }
        if (users[_sender].total_deposits != 0 && isMaxPayout(_sender)) {
            users[_sender].last_distPoints = totalDistributePoints;
        }

        uint256 tierPrice = tierAmounts[nodeTier].mul(numNodes);

        require(TOKEN.balanceOf(_sender) >= tierPrice, "Insufficient balance");
        require(
            TOKEN.allowance(_sender, address(this)) >= tierPrice,
            "Insufficient allowance"
        );
        TOKEN.safeTransferFrom(_sender, address(this), tierPrice);

        users[_sender].total_deposits = users[_sender].total_deposits.add(
            tierPrice
        );

        total_deposited = total_deposited.add(tierPrice);
        treasury_rewards = treasury_rewards.add(
            tierPrice.mul(treasuryFeePercent).div(100)
        );

        nodes[_sender][nodeTier] = nodes[_sender][nodeTier].add(numNodes);
        totalNodes[nodeTier] = totalNodes[nodeTier].add(numNodes);

        emit CreateNode(block.timestamp, _sender, numNodes);
    }

    function compound() public {
        uint256 rewardsPending = getTotalRewards(msg.sender);
        require(rewardsPending >= tierAmounts[0], "Not enough to compound");
        uint256 numPossible = rewardsPending.div(tierAmounts[0]);
        claim();
        _compound(0, numPossible);
        _claimBonus();
    }

    function _claimBonus() internal {
        address _sender = msg.sender;
        uint256 _totalClaims = users[_sender].total_claims;
        uint256 _maxPay = maxPayout(_sender);
        uint256 _depositAmount = 0;
        if (_totalClaims >= _maxPay) {
            _depositAmount = 0;
        } else {
            uint256 _pendingClaims = _maxPay.sub(_totalClaims);
            _depositAmount = _pendingClaims.div(maxReturnPercent).mul(100);
        }
        uint256 _pid = 0;
        IBonusRewards(bonusreward).deposit(_pid, _depositAmount, _sender);
    }

    function maxPayout(address _sender) public view returns (uint256) {
        return users[_sender].total_deposits.mul(maxReturnPercent).div(100);
    }

    function isMaxPayout(address _sender) public view returns (bool) {
        return users[_sender].total_claims >= maxPayout(_sender);
    }

    // function nodeMaxPayout() public view returns (uint256) {
    //     uint256 total = 0;
    //     for (uint256 i = 0; id < userIndices.length; i++) {
    //         total = total.add(
    //             users[userIndices[i]].total_deposits.mul(maxReturnPercent).div(
    //                 100
    //             )
    //         );
    //     }
    //     return total;
    // }

    // function nodeTotalClaims() public view returns (uint256) {
    //     uint256 total = 0;
    //     for (uint256 i = 0; id < userIndices.length; i++) {
    //         total = total.add(users[userIndices[i]].total_claims);
    //     }
    //     return total;
    // }

    // function nodePendingPayout() public view returns (uint256) {
    //     return nodeMaxPayout().sub(nodeTotalclaims());
    // }

    function _disperse(uint256 amount) internal {
        if (amount > 0) {
            totalDistributePoints = totalDistributePoints.add(
                amount.mul(MULTIPLIER).div(totalAllocPoints())
            );
            totalDistributeRewards = totalDistributeRewards.add(amount);
            total_rewards = total_rewards.add(amount);
        }
    }

    function dripRewards() public {
        uint256 drip = getRewardDrip();

        if (drip > 0) {
            _disperse(drip);
            lastDripTime = block.timestamp;
        }
    }

    function getRewardDrip() public view returns (uint256) {
        if (lastDripTime < block.timestamp) {
            uint256 poolBalance = getBalancePool();
            uint256 secondsPassed = block.timestamp.sub(lastDripTime);
            uint256 drip = secondsPassed.mul(poolBalance).div(dripRate);

            if (drip > poolBalance) {
                drip = poolBalance;
            }

            return drip;
        }
        return 0;
    }

    function getDayDripEstimate(address _user) external view returns (uint256) {
        return
            allocPoints(_user) > 0 && !isMaxPayout(_user)
                ? getBalancePool()
                    .mul(86400)
                    .mul(allocPoints(_user))
                    .div(totalAllocPoints())
                    .div(dripRate)
                : 0;
    }

    function total_users() external view returns (uint256) {
        return userIndices.length;
    }

    function numNodes(address _sender, uint256 _nodeId)
        external
        view
        returns (uint256)
    {
        return nodes[_sender][_nodeId];
    }

    function getNodes(address _sender)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory userNodes = new uint256[](tierAllocPoints.length);
        for (uint256 i = 0; i < tierAllocPoints.length; i++) {
            userNodes[i] = userNodes[i].add(nodes[_sender][i]);
        }
        return userNodes;
    }

    function getTotalNodes() external view returns (uint256[] memory) {
        uint256[] memory totals = new uint256[](tierAllocPoints.length);
        for (uint256 i = 0; i < tierAllocPoints.length; i++) {
            totals[i] = totals[i].add(totalNodes[i]);
        }
        return totals;
    }

    function getBalance() public view returns (uint256) {
        return IERC20(TOKEN).balanceOf(address(this));
    }

    function getBalancePool() public view returns (uint256) {
        return getBalance().sub(total_rewards).sub(treasury_rewards);
    }

    function emergencyWithdraw(IERC20 token, uint256 amnt) external onlyDev {
        token.safeTransfer(dev, amnt);
    }
}
