// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./lib/SafeMath8.sol";
import "./access/Operator.sol";
import "./utils/ContractGuard.sol";

import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/lib/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";

import "../interfaces/IBonusRewards.sol";

/*
    https://snowcrystals.finance
*/

contract LiquidityFund is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // router & pair
    IUniswapV2Router public uniswapV2Router;
    address public uniswapV2Pair;
    bool inSwapAndLiquify;

    // governance
    address public operator;

    //
    address private devWallet;
    address public daoWallet;
    address public pegToken;
    address public mainToken;

    address public sBondBonusReward;
    address public nodeBonusReward;

    address public treasury;

    uint256 private numTokensSellToAddToLiquidity = 100 * 10**18;
    uint256 public liquidityBalance;
    uint256 public bonusBalance;

    constructor(
        address _daoWallet,
        address _devWallet,
        address _pegToken,
        address _mainToken,
        address _sBondBonusReward,
        address _nodeBonusReward,
        address _treasury,
        address _router
    ) public {
        daoWallet = _daoWallet;
        devWallet = _devWallet;
        pegToken = _pegToken;
        mainToken = _mainToken;

        sBondBonusReward = _sBondBonusReward;
        nodeBonusReward = _nodeBonusReward;

        treasury = _treasury;

        IUniswapV2Router _uniswapV2Router = IUniswapV2Router(_router);
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _pegToken);

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        operator = msg.sender;
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 tokenReceived,
        uint256 tokensIntoLiqudity,
        uint256 liquidityPair
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "caller is not the operator");
        _;
    }

    modifier onlyOperatorOrTreasury() {
        require(
            operator == msg.sender || treasury == msg.sender,
            "caller is not the operator or the treasury"
        );
        _;
    }

    modifier onlyOperatorOrMainToken() {
        require(
            operator == msg.sender || mainToken == msg.sender,
            "caller is not the operator or the token"
        );
        _;
    }

    function addLiquidity(uint256 _amount) public onlyOperatorOrMainToken {
        uint256 liquidityAmount = _amount.mul(250).div(1000);
        uint256 bonusAmount = _amount.mul(750).div(1000);

        liquidityBalance = liquidityBalance.add(liquidityAmount);
        bonusBalance = bonusBalance.add(bonusAmount);

        if (liquidityBalance >= numTokensSellToAddToLiquidity) {
            uint256 daoLiqudityBalance = liquidityBalance.mul(800).div(1000);
            uint256 devLiqudityBalance = liquidityBalance.sub(
                daoLiqudityBalance
            );
            swapAndLiquify(daoLiqudityBalance, daoWallet);
            swapAndLiquify(devLiqudityBalance, devWallet);
            liquidityBalance = 0;
        }
    }

    function swapAndLiquify(uint256 _amount, address _receiver)
        private
        lockTheSwap
    {
        // split the balance into halves
        uint256 sellAmount = _amount.div(2);
        uint256 otherHalf = _amount.sub(sellAmount);

        // swap tokens for PEGTOKEN
        uint256 otherAmount = swapTokensForOther(sellAmount); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // add liquidity to uniswap
        uint256 liquidity;
        liquidity = addLiquidity(otherHalf, otherAmount, _receiver);

        emit SwapAndLiquify(sellAmount, otherAmount, otherHalf, liquidity);
    }

    function swapTokensForOther(uint256 _tokenAmount)
        private
        returns (uint256)
    {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = mainToken;
        path[1] = pegToken;

        // approve token transfer to cover all possible scenarios
        _approveTokenIfNeeded(mainToken, address(uniswapV2Router));
        _approveTokenIfNeeded(pegToken, address(uniswapV2Router));

        // make the swap
        // uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        //     _tokenAmount,
        //     0, // accept any amount of pegToken
        //     path,
        //     address(this),
        //     block.timestamp
        // );

        uniswapV2Router.swapExactTokensForTokens(
            _tokenAmount,
            0, // accept any amount of pegToken
            path,
            address(this),
            block.timestamp
        );
        return IERC20(pegToken).balanceOf(address(this));
    }

    function addLiquidity(
        uint256 _tokenAmount,
        uint256 _otherAmount,
        address _receiver
    ) private returns (uint256) {
        // add the liquidity
        uint256 liquidity;
        (, , liquidity) = uniswapV2Router.addLiquidity(
            mainToken,
            pegToken,
            _tokenAmount,
            _otherAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            _receiver,
            block.timestamp
        );
        return liquidity;
    }

    function _approveTokenIfNeeded(address token, address router) private {
        if (IERC20(token).allowance(address(this), router) == 0) {
            IERC20(token).safeApprove(router, type(uint256).max);
        }
    }

    function sendToBonus(
        uint256 _price,
        uint256 _ceilingPrice,
        uint256 _nextEpochPoint
    ) public onlyOperatorOrTreasury {
        if (block.timestamp > _nextEpochPoint) {
            return;
        }
        if (_price < _ceilingPrice) {
            uint256 half = bonusBalance.div(2);
            uint256 otherHalf = bonusBalance.sub(half);

            IERC20(mainToken).transfer(sBondBonusReward, half);
            IERC20(mainToken).transfer(nodeBonusReward, otherHalf);

            _restartBonusRewardPool(half, sBondBonusReward, _nextEpochPoint);
            _restartBonusRewardPool(
                otherHalf,
                nodeBonusReward,
                _nextEpochPoint
            );
        } else {
            IERC20(mainToken).transfer(nodeBonusReward, bonusBalance);

            _restartBonusRewardPool(
                bonusBalance,
                nodeBonusReward,
                _nextEpochPoint
            );
        }
        bonusBalance = 0;
    }

    function _restartBonusRewardPool(
        uint256 _amount,
        address _rewardPool,
        uint256 _nextEpochPoint
    ) private {
        IBonusRewards(_rewardPool).restartPool(_amount, _nextEpochPoint);
    }

    function setRouterAddress(address newRouter) public onlyOperator {
        IUniswapV2Router _newRouter = IUniswapV2Router(newRouter);
        uniswapV2Router = _newRouter;
    }

    function setNumTokensSellToAddToLiquidity(
        uint256 _numTokensSellToAddToLiquidity
    ) public onlyOperator {
        numTokensSellToAddToLiquidity =
            _numTokensSellToAddToLiquidity.div(10000) *
            10**18;
    }

    function setDaoWallet(address _daoWallet) external onlyOperator {
        daoWallet = _daoWallet;
    }

    function setDevWallet(address _devWallet) external onlyOperator {
        devWallet = _devWallet;
    }

    function setPegToken(address _pegToken) external onlyOperator {
        pegToken = _pegToken;
    }

    function setMainToken(address _mainToken) external onlyOperator {
        mainToken = _mainToken;
    }

    function setBondBonusReward(address _sBondBonusReward)
        external
        onlyOperator
    {
        sBondBonusReward = _sBondBonusReward;
    }

    function setNodeBonusReward(address _nodeBonusReward)
        external
        onlyOperator
    {
        nodeBonusReward = _nodeBonusReward;
    }

    function setBonusBalance(uint256 _amount) external onlyOperator {
        bonusBalance = _amount;
    }

    function setLiquidityBalance(uint256 _amount) external onlyOperator {
        liquidityBalance = _amount;
    }

    function governanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
