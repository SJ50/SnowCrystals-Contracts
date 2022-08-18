// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Note that this pool has no minter key of SNOW (rewards).
// Instead, the governance will call SNOW distributeReward method and send reward to this pool at the beginning.
contract SnowBonusRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;
    address public node;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SNOW to distribute.
        uint256 lastRewardTime; // Last time that SNOW distribution occurs.
        uint256 accSnowPerShare; // Accumulated SNOW per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
    }

    IERC20 public snow;
    IERC20 public depositToken;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // list of user address
    address[] public nodeUsers;
    mapping(address => uint256) public nodePurchased;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when SNOW mining starts.
    uint256 public poolStartTime;

    // The time when SNOW mining ends.
    uint256 public poolEndTime;

    uint256 public snowPerSecond;
    uint256 public runningTime = 6 hours;
    uint256 public TOTAL_REWARDS;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _snow,
        uint256 _poolStartTime,
        address _depositToken
    ) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_snow != address(0)) snow = IERC20(_snow);
        TOTAL_REWARDS = snow.balanceOf(address(this));
        snowPerSecond = TOTAL_REWARDS.div(runningTime);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        depositToken = IERC20(_depositToken);
        operator = msg.sender;
        add(1, depositToken, false, 0);
    }

    modifier onlyOperatorOrNode() {
        require(
            operator == msg.sender || node == msg.sender,
            "caller is not the operator or the node"
        );
        _;
    }

    function restartPool(uint256 _amount) external onlyOperatorOrNode {
        require(block.timestamp > poolEndTime, "last reward pool running");
        TOTAL_REWARDS = _amount;
        snowPerSecond = TOTAL_REWARDS.div(runningTime);
        poolStartTime = block.timestamp;
        poolEndTime = poolStartTime + runningTime;
        massUpdatePools();
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "existing pool?");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperatorOrNode {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) ||
            (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accSnowPerShare: 0,
                isStarted: _isStarted
            })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's SNOW allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperatorOrNode {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime)
        public
        view
        returns (uint256)
    {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime)
                return poolEndTime.sub(poolStartTime).mul(snowPerSecond);
            return poolEndTime.sub(_fromTime).mul(snowPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime)
                return _toTime.sub(poolStartTime).mul(snowPerSecond);
            return _toTime.sub(_fromTime).mul(snowPerSecond);
        }
    }

    // View function to see pending SNOW on frontend.
    function pendingSNOW(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSnowPerShare = pool.accSnowPerShare;
        uint256 tokenSupply = getTotalAmount();
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _snowReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            accSnowPerShare = accSnowPerShare.add(
                _snowReward.mul(1e18).div(tokenSupply)
            );
        }
        return user.amount.mul(accSnowPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 tokenSupply = getTotalAmount();
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _snowReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            pool.accSnowPerShare = pool.accSnowPerShare.add(
                _snowReward.mul(1e18).div(tokenSupply)
            );
        }
        pool.lastRewardTime = block.timestamp;
    }

    function getTotalAmount() public view returns (uint256) {
        uint256 _totalAmount = 0;
        for (uint256 _pid = 0; _pid < poolInfo.length; ++_pid) {
            for (
                uint256 nodeUsersIndex = 0;
                nodeUsersIndex < nodeUsers.length;
                ++nodeUsersIndex
            ) {
                address _userAddress = nodeUsers[nodeUsersIndex];
                UserInfo storage _user = userInfo[_pid][_userAddress];
                _totalAmount = _totalAmount + _user.amount;
            }
        }
        return _totalAmount;
    }

    // Deposit LP tokens.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _sender
    ) external onlyOperatorOrNode {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        if (user.amount <= 0) {
            nodePurchased[_sender] = nodePurchased[_sender] + 1;
        }
        if (nodePurchased[_sender] == 1) {
            nodeUsers.push(_sender);
        }

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user
                .amount
                .mul(pool.accSnowPerShare)
                .div(1e18)
                .sub(user.rewardDebt);
            if (_pending > 0) {
                safeSnowTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }

        if (_amount > 0) {
            user.amount = _amount;
        }

        if (_amount == 0) {
            user.amount = _amount;
            nodePurchased[_sender] = nodePurchased[_sender] - 1;
            if (nodePurchased[_sender] == 0) {
                for (
                    uint256 nodeUsersIndex = 0;
                    nodeUsersIndex < nodeUsers.length;
                    nodeUsersIndex++
                ) {
                    if (nodeUsers[nodeUsersIndex] == _sender) {
                        nodeUsers[nodeUsersIndex] = nodeUsers[
                            nodeUsers.length - 1
                        ];
                        nodeUsers.pop();
                    }
                }
            }
        }

        user.rewardDebt = user.amount.mul(pool.accSnowPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Safe SNOW transfer function, just in case if rounding error causes pool to not have enough SNOWs.
    function safeSnowTransfer(address _to, uint256 _amount) internal {
        uint256 _snowBalance = snow.balanceOf(address(this));
        if (_snowBalance > 0) {
            if (_amount > _snowBalance) {
                snow.safeTransfer(_to, _snowBalance);
            } else {
                snow.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperatorOrNode {
        operator = _operator;
    }

    function setNode(address _node) external onlyOperatorOrNode {
        node = _node;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOperatorOrNode {
        if (block.timestamp < poolEndTime + 30 days) {
            // do not allow to drain core token (SNOW or lps) if less than 30 days after pool ends
            require(_token != snow, "snow");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
