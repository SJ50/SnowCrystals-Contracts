// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBonusRewards {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _sender
    ) external;

    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) external;

    function restartPool(uint256 _amount, uint256 _nextEpochPoint) external;
}
