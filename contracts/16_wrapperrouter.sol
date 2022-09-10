// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IUniswapV2Router.sol";

contract WrappedRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Router public router;
    mapping(address => bool) public operator;

    constructor(address _router) public {
        operator[msg.sender] = true;
        router = IUniswapV2Router(_router);
    }

    //*================ OPERATOR FUNCTIONS ================*//

    modifier onlyOperator() {
        require(operator[msg.sender], "Caller is not an operator");
        _;
    }

    function setIsOperator(address _account, bool _isOperator)
        external
        onlyOwner
    {
        operator[_account] = _isOperator;
    }

    function setRouter(address _router) external onlyOwner {
        router = IUniswapV2Router(_router);
    }

    //*================ ROUTER FUNCTIONS ================*//

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        //Move tokens.
        IERC20(_tokenA).safeTransferFrom(
            msg.sender,
            address(this),
            _amountADesired
        );
        IERC20(_tokenB).safeTransferFrom(
            msg.sender,
            address(this),
            _amountBDesired
        );

        //Increase Approval
        IERC20(_tokenA).safeIncreaseAllowance(address(router), _amountADesired);
        IERC20(_tokenB).safeIncreaseAllowance(address(router), _amountBDesired);

        (amountA, amountB, liquidity) = router.addLiquidity(
            _tokenA,
            _tokenB,
            _amountADesired,
            _amountBDesired,
            _amountAMin,
            _amountBMin,
            _to,
            _deadline
        );

        //Token A leftover management.
        uint256 remainingTokenA = _amountADesired.sub(amountA);
        uint256 balanceTokenA = IERC20(_tokenA).balanceOf(address(this));
        remainingTokenA = remainingTokenA > balanceTokenA
            ? balanceTokenA
            : remainingTokenA;
        if (remainingTokenA > 0) {
            IERC20(_tokenA).transfer(msg.sender, remainingTokenA);
        }

        //Token B leftover management.
        uint256 remainingTokenB = _amountBDesired.sub(amountB);
        uint256 balanceTokenB = IERC20(_tokenB).balanceOf(address(this));
        remainingTokenB = remainingTokenB > balanceTokenB
            ? balanceTokenB
            : remainingTokenB;
        if (remainingTokenB > 0) {
            IERC20(_tokenB).transfer(msg.sender, remainingTokenB);
        }
    }

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external onlyOperator returns (uint256[] memory amounts) {
        //Assign token and transfer.
        address tokenIn = _path[0];
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);

        //Increase Approval
        IERC20(tokenIn).safeIncreaseAllowance(address(router), _amountIn);

        amounts = router.swapExactTokensForTokens(
            _amountIn,
            _amountOutMin,
            _path,
            _to,
            _deadline
        );

        //Token leftover management.
        uint256 remainingTokenIn = _amountIn.sub(amounts[0]);
        uint256 balanceTokenIn = IERC20(tokenIn).balanceOf(address(this));
        remainingTokenIn = remainingTokenIn > balanceTokenIn
            ? balanceTokenIn
            : remainingTokenIn;
        if (remainingTokenIn > 0) {
            IERC20(tokenIn).transfer(msg.sender, remainingTokenIn);
        }
    }
}
