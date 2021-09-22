// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";
import "../interfaces/benqi/IBenqiERC20Delegator.sol";
import "../interfaces/benqi/IBenqiUnitroller.sol";
import "../interfaces/erc20/IERC20.sol";
import "../interfaces/traderjoe/IJoeRouter02.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public qiToken; // Token we provide liquidity with (qiBTC)
    address public reward; // Token we farm and swap to want / qiToken

    // benqi unitroller/comptroller address
    address public constant BENQI_UNITROLLER =
        0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4;
    address public constant JOE_ROUTER_V2 =
        0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7; // wrapped AVAX

    address public constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5; // BENQI (QI) Token
    uint256 _balanceOfPool;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );
        /// @dev Add config here
        want = _wantConfig[0];
        qiToken = _wantConfig[1];
        reward = _wantConfig[2];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20(want).approve(qiToken, type(uint256).max);

        // approval for joe_router
        IERC20(QI).approve(JOE_ROUTER_V2, type(uint256).max);

        // enter market
        address[] memory tokens = new address[](1);
        tokens[0] = address(qiToken);
        IBenqiUnitroller(BENQI_UNITROLLER).enterMarkets(tokens);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "wBTC.e-QI-AVAX-strategy";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        // return locally tracked balance
        return _balanceOfPool;

        // NOTE: ideally we should use 'balanceOfUnderlying' here, but this isn't "view"
        //return IBenqiERC20Delegator(qiToken).balanceOfUnderlying(address(this));
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return balanceOfWant() > 0;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = qiToken;
        protectedTokens[2] = reward;
        return protectedTokens;
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        _balanceOfPool += _amount;
        IBenqiERC20Delegator(qiToken).mint(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        IBenqiERC20Delegator(qiToken).redeem(balanceOfPool());
        _balanceOfPool -= balanceOfPool();
    }

    /// @dev withdraw the specified amount of want, liquidate from qiToken to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        if (_amount > balanceOfPool()) {
            _amount = balanceOfPool();
        }
        IBenqiERC20Delegator(qiToken).redeemUnderlying(_amount);
        _balanceOfPool -= _amount;

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest()
        external
        payable
        whenNotPaused
        returns (uint256 harvested)
    {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));
        uint256 _avaxBefore = address(this).balance;

        // claim QI rewards
        IBenqiUnitroller(BENQI_UNITROLLER).claimReward(0, address(this));
        // claim AVAX rewards
        IBenqiUnitroller(BENQI_UNITROLLER).claimReward(1, address(this));

        // swap QI -> wBTC.e
        uint256 _qiRewards = IERC20Upgradeable(QI).balanceOf(address(this));
        if (_qiRewards > 0) {
            address[] memory path = new address[](3);
            path[0] = QI;
            path[1] = WAVAX;
            path[2] = want;

            IJoeRouter02(JOE_ROUTER_V2).swapExactTokensForTokens(
                _qiRewards,
                0,
                path,
                address(this),
                now + 120
            );
        }

        // swap AVAX -> wBTC.e
        uint256 _avaxRewards = address(this).balance.sub(_avaxBefore);
        if (_avaxRewards > 0) {
            address[] memory path = new address[](2);
            path[0] = WAVAX;
            path[1] = want;

            IJoeRouter02(JOE_ROUTER_V2).swapExactAVAXForTokens{
                value: _avaxRewards
            }(0, path, address(this), now + 120);
        }

        uint256 earned =
            IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// @notice Keep this in so you get paid!
        (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) =
            _processRewardsFees(earned, want);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        /// @dev Harvest must return the amount of want increased
        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        uint256 toDeposit = balanceOfWant();
        if (toDeposit > 0) {
            _deposit(toDeposit);
        }
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }

    /**
     * @notice payable function needed to receive AVAX
     */
    receive() external payable {}
}
