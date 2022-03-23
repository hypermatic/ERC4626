pragma solidity 0.8.10;

import {ERC20, ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "../external/interfaces/tokemak/ILiquidityPool.sol";
import "../external/interfaces/tokemak/IRewards.sol";
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

/**
* A Tokemak compatible ERC4626 vault that takes in a tAsset and auto compounds toke rewards
* received from staking that tAsset in toke.
*/
contract TokeVault is ERC4626 {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // require assets
    ERC20 public immutable toke = ERC20(0x2e9d63788249371f1DFC918a52f8d799F4a38C94);
    ERC20 public immutable tAsset;

    // tokemak liquidity pool
    ILiquidityPool public tokemakPool;
    IRewards public rewards;

    // keeper rewards: default of 1.5 Toke
    uint256 public keeperRewardAmount = 1500000000000000000;

    // user requested withdraws
    mapping(address => uint256) public requestedWithdraws;

    // uniswap
    ISwapRouter public immutable swapRouter;
    // configurable max swap amount. Default 100 toke (~$2500 USD)
    uint256 public maxTokeSwapAmount = 100000000000000000000;
    uint256 public swapPoolFee = 3000; // default 0.3%


    /**
    * @param _tAsset the tAsset that this vault handles
    */
    constructor(
        address _tAsset,
        address _rewards,
        address _swapRouter,
        string memory name,
        string memory symbol
    ) ERC4626(ERC20(_tAsset), name, symbol) {
        // erc20 representation of toke pool
        tAsset = ERC20(_tAsset);
        // pool representation of toke pool
        tokemakPool = ILiquidityPool(_tAsset);
        rewards = IRewards(_rewards);
        swapRouter = ISwapRouter(_swapRouter);
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256) internal override {
        // no after withdraw
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        // no after deposit actions
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns(uint256) {
        // Simply read tAsset balance. Ignore outstanding rewards
        return tAsset.balanceOf(address(this));
    }

    /**
    * @notice Claims rewards from toke 
    * @dev the payload for claiming (recipient, v, r, s) must be formed off chain
    */
    function claim(
        IRewards.Recipient memory recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // claim toke rewards
        rewards.claim(recipient, v, r, s);

        // reward the claimer for executing this claim
        tAsset.safeTransfer(msg.sender, keeperRewardAmount);
    }

    /**
    * @notice harvests on hand rewards for the underlying asset and reinvests
    * @dev limits the amount of slippage that it is willing to accept.
    */
    function compound() public {
        // find the asset the tokemak pool is settled in
        ERC20 underlying = ERC20(tokemakPool.underlyer());
        uint256 tokeBal = toke.balanceOf(address(this));
        // cap at max toke swap amount
        uint256 swapAmount = tokeBal >= maxTokeSwapAmount ? maxTokeSwapAmount : tokeBal;

        // sell toke rewards earned for underlying asset
        // dealing with slippage
        // todo: option 1: - toke / underlying oracle needed for safety
        // option 2: have a max sale amount with a cooldown period?
        // note: slippage here will only ever be upward pressure on the tAsset but you still want to optimise this
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(toke),
                tokenOut: address(underlying),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: swapAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);

        // todo: option 3: make this a permissioned function and use input to define the MIN price willing to be accepted.


        // deposit all of underlying back into toke and take service fee
        uint256 underlyingBal = underlying.balanceOf(address(this));
        uint256 depositAmount = underlyingBal - (underlyingBal / 10); // 90%
        uint256 serviceFee = underlyingBal / 20; // 5%
        underlying.safeApprove(address(tokemakPool), depositAmount);
        tokemakPool.deposit(depositAmount);
        underlying.safeTransfer(feeReciever, serviceFee);

    }
}