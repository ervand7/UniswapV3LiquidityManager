// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {TicksCalculator} from "./TickCalculator.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract LiquidityManager is IERC721Receiver, ReentrancyGuard {
    event LiquidityAdded(address indexed user, uint256 amount0, uint256 amount1);

    INonfungiblePositionManager immutable nonfungiblePositionManager;
    IUniswapV3Pool immutable uniswapPool;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, IUniswapV3Pool _uniswapPool) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        uniswapPool = _uniswapPool;
    }

    /// @notice Add liquidity to a specified Uniswap V3 pool
    /// @param pool IUniswapV3Pool instance
    /// @param amount0 Desired amount of token0 to add
    /// @param amount1 Desired amount of token1 to add
    /// @param width The width of the position (calculated as provided)
    function addLiquidity(IUniswapV3Pool pool, uint256 amount0, uint256 amount1, uint256 width)
        external
        nonReentrant
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        require(amount0 != 0 && amount1 != 0, "Input amount should not be zero");

        (address token0, address token1, uint24 fee) = _getPoolTokensAndFee(pool);
        (int24 tickLower, int24 tickUpper) = TicksCalculator.calculateTickBounds(pool, width);

        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1);

        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1);

        // Mint new liquidity position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0Used, amount1Used) = nonfungiblePositionManager.mint(params);
        emit LiquidityAdded(msg.sender, amount0Used, amount1Used);
        
        _refundUnusedTokens(token0, token1, amount0, amount1, amount0Used, amount1Used);
    }

    // Implementing `onERC721Received` so this contract can receive ERC721 tokens
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Refunds any unused tokens back to the user after adding liquidity
    /// @param token0 The address of the first token in the pool (token0)
    /// @param token1 The address of the second token in the pool (token1)
    /// @param amount0 The initial amount of token0 provided by the user
    /// @param amount1 The initial amount of token1 provided by the user
    /// @param amount0Used The amount of token0 actually used for the liquidity position
    /// @param amount1Used The amount of token1 actually used for the liquidity position
    function _refundUnusedTokens(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Used,
        uint256 amount1Used
    ) internal {
        if (amount0 > amount0Used) {
            TransferHelper.safeTransfer(token0, msg.sender, amount0 - amount0Used);
        }
        if (amount1 > amount1Used) {
            TransferHelper.safeTransfer(token1, msg.sender, amount1 - amount1Used);
        }
    }

    /// @notice Retrieves token0, token1, and fee from the pool
    /// @param pool IUniswapV3Pool instance
    /// @return token0 The first token in the pair
    /// @return token1 The second token in the pair
    /// @return fee The fee tier of the pool
    function _getPoolTokensAndFee(IUniswapV3Pool pool)
        internal
        view
        returns (address token0, address token1, uint24 fee)
    {
        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
    }
}
