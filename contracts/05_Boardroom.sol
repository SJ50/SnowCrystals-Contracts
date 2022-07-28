/**
 *Submitted for verification at cronoscan.com on 2022-06-19
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./utils/ShareWrapper.sol";
import "./utils/ContractGuard.sol";
import "../interfaces/IBasisAsset.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IpegBoardroom.sol";

contract Boardroom is ShareWrapper, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    IERC20 public snow;
    ITreasury public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;
    bool isSacrificeReward;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event RewardSacrificed(
        address indexed token,
        address indexed user,
        uint256 reward
    );

    /* ========== Modifiers =============== */

    modifier onlyOperator() {
        require(
            operator == msg.sender,
            "Boardroom: caller is not the operator"
        );
        _;
    }

    modifier memberExists() {
        require(
            balanceOf(msg.sender) > 0,
            "Boardroom: The member does not exist"
        );
        _;
    }

    modifier updateReward(address member) {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        IERC20 _snow,
        IERC20 _share,
        ITreasury _treasury
    ) public notInitialized {
        snow = _snow;
        share = _share;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 8; // Lock for 8 epochs (48h) before release withdraw
        rewardLockupEpochs = 4; // Lock for 4 epochs (24h) before release claimReward

        isSacrificeReward = true;
        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setLockUp(
        uint256 _withdrawLockupEpochs,
        uint256 _rewardLockupEpochs
    ) external onlyOperator {
        require(
            _withdrawLockupEpochs >= _rewardLockupEpochs &&
                _withdrawLockupEpochs <= 56,
            "_withdrawLockupEpochs: out of range"
        ); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length.sub(1);
    }

    function getLatestSnapshot()
        internal
        view
        returns (BoardroomSnapshot memory)
    {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member)
        public
        view
        returns (uint256)
    {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member)
        internal
        view
        returns (BoardroomSnapshot memory)
    {
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function canWithdraw(address member) external view returns (bool) {
        return
            members[member].epochTimerStart.add(withdrawLockupEpochs) <=
            treasury.epoch();
    }

    function canClaimReward(address member) external view returns (bool) {
        return
            members[member].epochTimerStart.add(rewardLockupEpochs) <=
            treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getSnowPrice() external view returns (uint256) {
        return treasury.getSnowPrice();
    }

    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return
            balanceOf(member).mul(latestRPS.sub(storedRPS)).div(1e18).add(
                members[member].rewardEarned
            );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount)
        public
        override
        onlyOneBlock
        updateReward(msg.sender)
    {
        require(amount > 0, "Boardroom: Cannot stake 0");
        super.stake(amount);
        members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        onlyOneBlock
        memberExists
        updateReward(msg.sender)
    {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(
            members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <=
                treasury.epoch(),
            "Boardroom: still in withdraw lockup"
        );
        if (isSacrificeReward == true) _sacrificeReward();
        else claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function _sacrificeReward() internal updateReward(msg.sender) {
        uint256 reward = members[msg.sender].rewardEarned;
        address _token = address(snow);
        IBasisAsset(_token).burn(reward);
        members[msg.sender].rewardEarned = 0;
        emit RewardSacrificed(_token, msg.sender, reward);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = members[msg.sender].rewardEarned;
        if (reward > 0) {
            require(
                members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <=
                    treasury.epoch(),
                "Boardroom: still in reward lockup"
            );
            members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            members[msg.sender].rewardEarned = 0;
            snow.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(
            totalSupply() > 0,
            "Boardroom: Cannot allocate when totalSupply is 0"
        );

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardroomHistory.push(newSnapshot);

        snow.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(snow), "snow");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}
