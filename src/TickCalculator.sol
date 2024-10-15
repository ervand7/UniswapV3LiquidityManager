// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

library Babylonian {
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}

library TicksCalculator {
    /// @notice Calculates tickLower and tickUpper based on the specified width formula
    /// @param pool The address of the Uniswap V3 pool
    /// @param width The desired width of the liquidity position, defined as per the formula
    /// @return tickLower The lower tick bound
    /// @return tickUpper The upper tick bound
    function calculateTickBounds(IUniswapV3Pool pool, uint256 width)
        public
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        // Get the current price and tick from the pool
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();
        uint24 fee = pool.fee();
        int24 tickSpacing = _getTickSpacing(fee);

        // Calculate the width as a decimal (e.g., width of 100 represents 1%)
        uint256 widthPercentage = width;

        // Convert sqrtPriceX96 to price (token1/token0) in fixed-point Q64.96 format
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) >> 64;

        // Calculate the price delta based on the width formula
        uint256 deltaPriceX96 = (priceX96 * widthPercentage) / 10000;

        // Calculate lower and upper prices in Q64.96 format
        uint256 lowerPriceX96 = priceX96 - deltaPriceX96;
        uint256 upperPriceX96 = priceX96 + deltaPriceX96;

        // Ensure that lowerPriceX96 and upperPriceX96 are within valid ranges
        require(lowerPriceX96 > 0, "Lower price must be greater than zero");

        // Convert prices back to sqrtPriceX96
        uint160 sqrtLowerPriceX96 = uint160(Babylonian.sqrt(lowerPriceX96 << 64));
        uint160 sqrtUpperPriceX96 = uint160(Babylonian.sqrt(upperPriceX96 << 64));

        // Get ticks corresponding to sqrt prices
        int24 tickLowerUnrounded = TickMath.getTickAtSqrtRatio(sqrtLowerPriceX96);
        int24 tickUpperUnrounded = TickMath.getTickAtSqrtRatio(sqrtUpperPriceX96);

        // Round ticks to be multiples of tick spacing
        tickLower = (tickLowerUnrounded / tickSpacing) * tickSpacing;
        tickUpper = (tickUpperUnrounded / tickSpacing) * tickSpacing;

        // Ensure tickLower and tickUpper are within the valid range
        require(tickLower >= TickMath.MIN_TICK, "tickLower too low");
        require(tickUpper <= TickMath.MAX_TICK, "tickUpper too high");
        require(tickLower < tickUpper, "tickLower must be less than tickUpper");
    }

    /// @notice Determines the tick spacing for a Uniswap V3 pool based on its fee tier.
    /// @param fee The fee tier of the pool (e.g., 100 = 0.01%, 500 = 0.05%, 3000 = 0.3%, 10000 = 1%).
    /// @return tickSpacing The tick spacing corresponding to the fee tier.
    function _getTickSpacing(uint24 fee) internal pure returns (int24 tickSpacing) {
        // Uniswap V3 pools have different tick spacings depending on the fee tier.
        // The higher the fee, the wider the tick spacing.
        if (fee == 100) {
            // 0.01% fee tier has the smallest tick spacing of 1.
            tickSpacing = 1;
        } else if (fee == 500) {
            // 0.05% fee tier has a tick spacing of 10.
            tickSpacing = 10;
        } else if (fee == 3000) {
            // 0.3% fee tier has a tick spacing of 60.
            tickSpacing = 60;
        } else if (fee == 10000) {
            // 1% fee tier has the widest tick spacing of 200.
            tickSpacing = 200;
        } else {
            // If the fee tier is not supported, revert the transaction with an error.
            revert("Unsupported fee tier");
        }
    }
}
