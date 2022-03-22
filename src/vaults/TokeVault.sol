pragma solidity 0.8.10;

import {ERC20, ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "../external/interfaces/tokemak/ILiquidityPool.sol";
import "../external/interfaces/tokemak/IRewards.sol";

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


    /**
    * @param _tAsset the tAsset that this vault handles
    */
    constructor(
        address _tAsset,
        address _rewards,
        string memory name,
        string memory symbol
    ) ERC4626(ERC20(_tAsset), name, symbol) {
        // erc20 representation of toke pool
        tAsset = ERC20(_tAsset);
        // pool representation of toke pool
        tokemakPool = ILiquidityPool(_tAsset);
        rewards = IRewards(_rewards);
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

    /// @notice Maximum amount of assets that can be withdrawn.
    /// This is capped by the amount of cash available on hand
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        uint256 cash = tAsset.balanceOf(address(this));
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    /// This is capped by the amount of cash available on hand
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = tAsset.balanceOf(address(this));
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
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

        // sell toke rewards earned for underlying asset
        // todo: toke / underlying oracle needed for safety here OR have a max sale amount with a cooldown period?

        // deposit underlying back into toke and take service fee in tAsset
        // uint256 depositAmount = underlyingAmount - (underlyingAmount / 10); // 90%
        // uint256 serviceFee = underlyingAmount / 20; // 5%
        // underlying.safeApprove(address(tokemakPool), depositAmount);
        // tokemakPool.deposit(depositAmount);
    }
}