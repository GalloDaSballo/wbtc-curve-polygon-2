// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";

import "../interfaces/curve/ICurve.sol";
import "../interfaces/uniswap/IUniswapRouterV2.sol";

import {
    BaseStrategy
} from "../deps/BaseStrategy.sol";

contract StrategyCurveBadgerWBtcRenBtc is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    event TreeDistribution(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent

    address public constant wETH_TOKEN = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant renBTC_TOKEN = 0xDBf31dF14B66535aF65AaC99C32e9eA844e14501;
    address public constant wBTC_TOKEN = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address public constant CRV_TOKEN = 0x172370d5Cd63279eFa6d502DAB29171933a610AF;
    address public constant DAI_TOKEN = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;


    // curve interface contracts
    address public constant CURVE_RENBTC_POOL = 0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67;
    // address public constant CURVE_RENBTC_LP_TOKEN = 0xf8a57c1d3b9629b77b6726a042ca48990A84Fb49; // want
    // to retrieve both CRV & WMATIC rewards
    address public constant CURVE_RENBTC_REWARD_CLAIMER = 0xe89BC681C5cb6A3499E9dB97e0CE8558877Dd1A4;
    address public constant CURVE_RENBTC_GAUGE = 0xffbACcE0CC7C19d46132f1258FC16CF6871D153c; // this is pool & deposit token

    address public constant QUICKSWAP_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

    address public constant badgerTree = 0x2C798FaFd37C7DCdcAc2498e19432898Bc51376b;

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(_governance, _strategist, _controller, _keeper, _guardian);

        /// @dev Add config here
        want = _wantConfig[0];
        lpComponent = _wantConfig[1];
        reward = _wantConfig[2];


        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(CURVE_RENBTC_GAUGE, type(uint256).max);
        IERC20Upgradeable(want).safeApprove(CURVE_RENBTC_POOL, type(uint256).max);
        IERC20Upgradeable(wBTC_TOKEN).safeApprove(CURVE_RENBTC_POOL, type(uint256).max);

        IERC20Upgradeable(reward).safeApprove(QUICKSWAP_ROUTER, type(uint256).max);
        IERC20Upgradeable(CRV_TOKEN).safeApprove(QUICKSWAP_ROUTER, type(uint256).max);
        IERC20Upgradeable(wETH_TOKEN).safeApprove(QUICKSWAP_ROUTER, type(uint256).max);

    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external override pure returns (string memory) {
        return "StrategyCurveBadgerWBtcRenBtc";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public override view returns (uint256) {
        return IERC20Upgradeable(CURVE_RENBTC_GAUGE).balanceOf(address(this));
    }
    
    /// @dev Returns true if this strategy requires tending
    function isTendable() public override view returns (bool) {
        return balanceOfWant() > 0;
    }

    // TODO: update lpcomponent
    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens() public override view returns (address[] memory) {
        address[] memory protectedTokens = new address[](5);
        protectedTokens[0] = want;
        protectedTokens[1] = lpComponent;
        protectedTokens[2] = reward;

        protectedTokens[3] = CRV_TOKEN;
        protectedTokens[4] = wBTC_TOKEN;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====
    /// @notice Delete if you don't need!
    function setKeepReward(uint256 _setKeepReward) external {
        _onlyGovernance();
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for(uint256 x = 0; x < protectedTokens.length; x++){
            require(address(protectedTokens[x]) != _asset, "Asset is protected");
        }
    }


    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        ICurveGauge(CURVE_RENBTC_GAUGE).deposit(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        ICurveGauge(CURVE_RENBTC_GAUGE).withdraw(balanceOfPool());
    }
    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        if(_amount > balanceOfPool()) {
            _amount = balanceOfPool();
        }

        ICurveGauge(CURVE_RENBTC_GAUGE).withdraw(_amount);

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // figure out and claim our rewards
        ICurveGauge(CURVE_RENBTC_GAUGE).claim_rewards();

        // Get total rewards (WMATIC & CRV)
        uint256 rewardsAmount = IERC20Upgradeable(reward).balanceOf(address(this));
        uint256 crvAmount = IERC20Upgradeable(CRV_TOKEN).balanceOf(address(this));

        // If no reward, then no-op
        if (rewardsAmount == 0 && crvAmount == 0) {
            return 0;
        }

        // Process CRV rewards if existing
        if (crvAmount > 0) {
            // Process fees on CRV Rewards
            _processRewardsFees(crvAmount, CRV_TOKEN);

            // Transfer balance of CRV to the Badger Tree
            uint256 crvBalance = IERC20Upgradeable(CRV_TOKEN).balanceOf(address(this));
            IERC20Upgradeable(CRV_TOKEN).safeTransfer(badgerTree, crvBalance);

            emit TreeDistribution(CRV_TOKEN, crvBalance, block.number, block.timestamp);
        }

        // We want to swap rewards (WMATIC) to WBTC and then add liquidity to wBTC-renBTC pool by depositing wBTC

        // Swap WMATIC to wBTC
        if (rewardsAmount > 0) {
            address[] memory path = new address[](3);
            path[0] = reward;
            path[1] = wETH_TOKEN;
            path[2] = wBTC_TOKEN;
            IUniswapRouterV2(QUICKSWAP_ROUTER).swapExactTokensForTokens(rewardsAmount, 0, path, address(this), now);
        }

        // Add liquidity for wBTC-renBTC pool by depositing wBTC
        ICurveStableSwapREN(CURVE_RENBTC_POOL).add_liquidity(
            [IERC20Upgradeable(wBTC_TOKEN).balanceOf(address(this)), 0], 0, true
        );

        uint256 earned = IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// @notice Keep this in so you get paid!
        (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) = _processPerformanceFees(earned);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price) external whenNotPaused returns (uint256 harvested) {

    }

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        if(balanceOfWant() > 0) {
            _deposit(balanceOfWant());
        }
    }


    /// ===== Internal Helper Functions =====
    
    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount) internal returns (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) {
        governancePerformanceFee = _processFee(want, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistPerformanceFee = _processFee(want, _amount, performanceFeeStrategist, strategist);
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address token) internal returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee) {
        governanceRewardsFee = _processFee(token, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistRewardsFee = _processFee(token, _amount, performanceFeeStrategist, strategist);
    }
}
