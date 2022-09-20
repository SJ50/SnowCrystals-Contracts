// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./access/Operator.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IERC20Taxable.sol";
import "../interfaces/IBonusRewards.sol";

contract TaxOffice is Operator {
    using SafeMath for uint256;

    event HandledMainTokenTax(uint256 _amount);
    event HandledShareTokenTax(uint256 _amount);

    IERC20Taxable public mainToken;
    IERC20Taxable public shareToken;
    IOracle public mainTokenOracle;

    uint256 public constant BASIS_POINTS_DENOM = 10_000;

    uint256[] public mainTokenTaxTwapTiers = [
        0,
        5e16,
        6e16,
        7e16,
        8e16,
        9e16,
        9.5e16,
        1e17,
        1.05e17,
        1.10e17,
        1.20e17,
        1.30e17,
        1.40e17,
        1.50e17
    ];
    uint256[] public mainTokenTaxRateTiers = [
        2000,
        2000,
        2000,
        2000,
        1600,
        1600,
        1600,
        1600,
        1200,
        800,
        800,
        800,
        800,
        800
    ];

    uint256[] public shareTokenTaxTwapTiers = [
        0,
        5e16,
        6e16,
        7e16,
        8e16,
        9e16,
        9.5e16,
        1e17,
        1.05e17,
        1.10e17,
        1.20e17,
        1.30e17,
        1.40e17,
        1.50e17
    ];
    uint256[] public shareTokenTaxRateTiers = [
        2000,
        2000,
        2000,
        2000,
        1600,
        1600,
        1600,
        1600,
        1200,
        800,
        800,
        800,
        800,
        800
    ];

    mapping(address => mapping(address => uint256)) public taxDiscount;

    constructor(
        address _mainToken,
        address _shareToken,
        address _mainTokenOracle
    ) public {
        mainToken = IERC20Taxable(_mainToken);
        shareToken = IERC20Taxable(_shareToken);
        mainTokenOracle = IOracle(_mainTokenOracle);
    }

    /*
    Uses the oracle to fire the 'consult' method and get the price of tomb.
    */
    function getMainTokenPrice() public view returns (uint256) {
        try mainTokenOracle.consult(address(mainToken), 1e18) returns (
            uint144 _price
        ) {
            return uint256(_price);
        } catch {
            revert("Erro: failed to fetch Main Token price from Oracle");
        }
    }

    /*
    Uses the oracle to fire the 'twap' method and get the price of tomb.
    */
    function getMainTokenUpdatedPrice() public view returns (uint256) {
        try mainTokenOracle.twap(address(mainToken), 1e18) returns (
            uint144 _price
        ) {
            return uint256(_price);
        } catch {
            revert("Erro: failed to fetch Main Token price from Oracle");
        }
    }

    /* 
    use the oracle to update maintoke twap price 
    */
    function updateMainTokenPrice() public {
        if (address(mainTokenOracle) != address(0))
            try mainTokenOracle.update() {} catch {}
    }

    function assertMonotonicity(uint256[] memory _monotonicArray)
        internal
        pure
    {
        uint8 endIdx = uint8(_monotonicArray.length.sub(1));
        for (uint8 idx = 0; idx <= endIdx; idx++) {
            if (idx > 0) {
                require(
                    _monotonicArray[idx] > _monotonicArray[idx - 1],
                    "Error: TWAP tiers sequence are not monotonic"
                );
            }
            if (idx < endIdx) {
                require(
                    _monotonicArray[idx] < _monotonicArray[idx + 1],
                    "Error: TWAP tiers sequence are not monotonic"
                );
            }
        }
    }

    function setMainTokenTaxTiers(
        uint256[] calldata _mainTokenTaxTwapTiers,
        uint256[] calldata _mainTokenTaxRateTiers
    ) external onlyOperator {
        require(
            _mainTokenTaxTwapTiers.length == _mainTokenTaxRateTiers.length,
            "Error: vector lengths are not the same."
        );

        //Require monotonicity of TWAP tiers.
        assertMonotonicity(_mainTokenTaxTwapTiers);

        //Set values.
        mainTokenTaxTwapTiers = _mainTokenTaxTwapTiers;
        mainTokenTaxRateTiers = _mainTokenTaxRateTiers;
    }

    function setShareTokenTaxTiers(
        uint256[] calldata _shareTokenTaxTwapTiers,
        uint256[] calldata _shareTokenTaxRateTiers
    ) external onlyOperator {
        require(
            _shareTokenTaxTwapTiers.length == _shareTokenTaxRateTiers.length,
            "Error: vector lengths are not the same."
        );

        //Require monotonicity of TWAP tiers.
        assertMonotonicity(_shareTokenTaxTwapTiers);

        //Set values.
        shareTokenTaxTwapTiers = _shareTokenTaxTwapTiers;
        shareTokenTaxRateTiers = _shareTokenTaxRateTiers;
    }

    function searchSorted(uint256[] memory _monotonicArray, uint256 _value)
        internal
        pure
        returns (uint8)
    {
        uint8 endIdx = uint8(_monotonicArray.length.sub(1));
        for (uint8 tierIdx = endIdx; tierIdx >= 0; --tierIdx) {
            if (_value >= _monotonicArray[tierIdx]) {
                return tierIdx;
            }
        }
    }

    function calculateMainTokenTax() external view returns (uint256 taxRate) {
        uint256 mainTokenPrice = getMainTokenUpdatedPrice();
        uint8 taxTierIdx = searchSorted(mainTokenTaxTwapTiers, mainTokenPrice);
        taxRate = mainTokenTaxRateTiers[taxTierIdx];
    }

    function calculateShareTokenTax() external view returns (uint256 taxRate) {
        uint256 mainTokenPrice = getMainTokenUpdatedPrice();
        uint8 taxTierIdx = searchSorted(shareTokenTaxTwapTiers, mainTokenPrice);
        taxRate = shareTokenTaxRateTiers[taxTierIdx];
    }

    function withdraw(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyOperator {
        IERC20(_token).transfer(_recipient, _amount);
    }

    function handleMainTokenTax(uint256 _amount) external virtual {
        emit HandledMainTokenTax(_amount);
    }

    function handleShareTokenTax(uint256 _amount) external virtual {
        emit HandledShareTokenTax(_amount);
    }

    /* ========== SET VARIABLES ========== */

    function setMainTokenStaticTaxRate(uint256 _taxRate) external onlyOperator {
        mainToken.setStaticTaxRate(_taxRate);
    }

    function setMainTokenEnableDynamicTax(bool _enableDynamicTax)
        external
        onlyOperator
    {
        mainToken.setEnableDynamicTax(_enableDynamicTax);
    }

    function setMainTokenWhitelistType(address _account, uint8 _type)
        external
        onlyOperator
    {
        mainToken.setWhitelistType(_account, _type);
    }

    function setShareTokenStaticTaxRate(uint256 _taxRate)
        external
        onlyOperator
    {
        shareToken.setStaticTaxRate(_taxRate);
    }

    function setShareTokenEnableDynamicTax(bool _enableDynamicTax)
        external
        onlyOperator
    {
        shareToken.setEnableDynamicTax(_enableDynamicTax);
    }

    function setShareTokenWhitelistType(address _account, uint8 _type)
        external
        onlyOperator
    {
        shareToken.setWhitelistType(_account, _type);
    }

    function setTaxDiscount(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external onlyOwner {
        require(
            _amount <= BASIS_POINTS_DENOM,
            "Error: Discount rate too high."
        );
        taxDiscount[_sender][_recipient] = _amount;
    }

    function setMainTokenOracle(address _mainTokenOracle)
        external
        onlyOperator
    {
        require(
            _mainTokenOracle != address(0),
            "Error: Oracle address cannot be 0 address"
        );
        mainTokenOracle = IOracle(_mainTokenOracle);
    }
}

// File: TaxOfficeV2.sol

contract TaxOfficeV2 is TaxOffice {
    using SafeERC20 for IERC20;

    address public router;
    IERC20 public pegToken;

    constructor(
        address _mainToken,
        address _shareToken,
        address _mainTokenOracle,
        address _pegToken,
        address _router
    ) public TaxOffice(_mainToken, _shareToken, _mainTokenOracle) {
        pegToken = IERC20(_pegToken);
        router = _router;
    }

    function setRouterAddress(address _router) public onlyOperator {
        router = _router;
    }

    function handleShareTokenTax(uint256 _amount) external override {
        //Apply accesibility permissions.
        require(
            msg.sender == address(shareToken) || msg.sender == operator(),
            "Error: Withdraw permissions insufficient."
        );

        //Check _amount of share token to be handled is available.
        uint256 tokenBalance = shareToken.balanceOf(address(this));
        if (_amount > tokenBalance) {
            _amount = tokenBalance;
        }
        // generate the uniswap pair path of token -> weth
        address[] memory shareToMainTokenSwapPath;
        shareToMainTokenSwapPath = new address[](3);
        shareToMainTokenSwapPath[0] = address(shareToken);
        shareToMainTokenSwapPath[1] = address(pegToken);
        shareToMainTokenSwapPath[2] = address(mainToken);
        //Swap from share token to main token.
        IERC20(address(shareToken)).safeIncreaseAllowance(router, _amount);

        uint256[] memory amounts = IUniswapV2Router(router)
            .swapExactTokensForTokens(
                _amount,
                0,
                shareToMainTokenSwapPath,
                address(this),
                block.timestamp + 40
            );
        uint256 mainTokenAmounts = amounts[2];
        mainToken.burn(mainTokenAmounts);

        updateMainTokenPrice();
        //Emit event.
        emit HandledShareTokenTax(_amount);
    }
}

contract TaxOfficeV3 is TaxOfficeV2 {
    using SafeERC20 for IERC20;

    address public sBondBonusRewardPool;
    address public nodeBonusRewardPool;
    address public treasury;
    uint256 public devBalance;
    uint256 public bonusBalance;
    bool public bonusRewardEnabled;

    constructor(
        address _mainToken,
        address _shareToken,
        address _mainTokenOracle,
        address _pegToken,
        address _router,
        address _treasury
    )
        public
        TaxOfficeV2(
            _mainToken,
            _shareToken,
            _mainTokenOracle,
            _pegToken,
            _router
        )
    {
        treasury = _treasury;
    }

    modifier onlyOperatorOrTreasury() {
        require(
            operator() == msg.sender || treasury == msg.sender,
            "caller is not the operator or the treasury"
        );
        _;
    }

    function handleMainTokenTax(uint256 _amount) external override {
        require(
            msg.sender == address(mainToken) || msg.sender == operator(),
            "Error: Withdraw permissions insufficient."
        );
        uint256 devAmount = _amount.mul(250).div(1000);
        uint256 bonusAmount = _amount.sub(devAmount);
        if (bonusRewardEnabled) {
            bonusBalance = bonusBalance.add(bonusAmount);
        }
        swapTokensForOther(devAmount);
        updateMainTokenPrice();
    }

    function swapTokensForOther(uint256 _tokenAmount)
        private
        returns (uint256)
    {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(mainToken);
        path[1] = address(pegToken);

        // approve token transfer to cover all possible scenarios
        _approveTokenIfNeeded(address(mainToken), router);
        _approveTokenIfNeeded(address(pegToken), router);

        IUniswapV2Router(router).swapExactTokensForTokens(
            _tokenAmount,
            0, // accept any amount of pegToken
            path,
            address(this),
            block.timestamp + 40
        );
        return pegToken.balanceOf(address(this));
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

            mainToken.transfer(sBondBonusRewardPool, half);
            mainToken.transfer(nodeBonusRewardPool, otherHalf);

            _restartBonusRewardPool(
                half,
                sBondBonusRewardPool,
                _nextEpochPoint
            );
            _restartBonusRewardPool(
                otherHalf,
                nodeBonusRewardPool,
                _nextEpochPoint
            );
        } else {
            mainToken.transfer(nodeBonusRewardPool, bonusBalance);

            _restartBonusRewardPool(
                bonusBalance,
                nodeBonusRewardPool,
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

    function setBondBonusReward(address _sBondBonusRewardPool)
        external
        onlyOperator
    {
        sBondBonusRewardPool = _sBondBonusRewardPool;
    }

    function setNodeBonusRewardPool(address _nodeBonusRewardPool)
        external
        onlyOperator
    {
        nodeBonusRewardPool = _nodeBonusRewardPool;
    }

    function setTreasury(address _treasury) external onlyOperator {
        treasury = _treasury;
    }

    function toggleBonusRewardEnabled() external onlyOperator {
        bonusRewardEnabled = !bonusRewardEnabled;
    }
}
