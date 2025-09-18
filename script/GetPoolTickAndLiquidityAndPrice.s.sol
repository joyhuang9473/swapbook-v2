// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title GetPoolTickAndLiquidityAndPrice
 * @notice Script to get pool tick, liquidity, and calculate price from tick and sqrtPriceX96
 */
import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract GetPoolTickAndLiquidityAndPrice is Script {
    using PoolIdLibrary for PoolId;
    using StateLibrary for IPoolManager;

    function setUp() public {}

    function run() public view {
        console.log("=== Price Calculation Analysis ===");
        
        // Get addresses from environment
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        uint256 poolIdUint = vm.envUint("POOL_ID");
        
        // Convert uint256 to PoolId
        PoolId poolId = PoolId.wrap(bytes32(poolIdUint));
        
        // Get pool state
        (uint160 sqrtPriceX96, int24 currentTick, , ) = IPoolManager(poolManagerAddress).getSlot0(poolId);
        
        console.log("Raw Data:");
        console.log("  SqrtPriceX96:", sqrtPriceX96);
        console.log("  Current Tick:", currentTick);
        
        // Calculate price from sqrtPriceX96
        uint256 price = calculatePriceFromSqrtPriceX96(sqrtPriceX96);
        console.log("  Calculated Price (wei):", price);
        
        // Calculate price from tick
        uint256 priceFromTick = calculatePriceFromTick(currentTick);
        console.log("  Price from Tick (wei):", priceFromTick);
        
        // Show tick spacing analysis
        console.log("\nTick Spacing Analysis:");
        int24 tickSpacing = 60;
        console.log("  Tick Spacing:", tickSpacing);
        console.log("  Current Tick:", currentTick);
        
        // Show nearby valid ticks
        int24 lowerValidTick = (currentTick / tickSpacing) * tickSpacing;
        int24 upperValidTick = lowerValidTick + tickSpacing;
        console.log("  Lower liquidity position:", lowerValidTick);
        console.log("  Upper liquidity position:", upperValidTick);
        
        // Price comparison
        uint256 priceAtTick_120 = calculatePriceFromTick(-120);
        uint256 priceAtTick_60 = calculatePriceFromTick(-60);
        uint256 priceAtTick0 = calculatePriceFromTick(0);
        uint256 priceAtTick60 = calculatePriceFromTick(60);
        uint256 priceAtTick120 = calculatePriceFromTick(120);
        console.log("\nPrice Comparison:");
        console.log("  Price at tick -120:", priceAtTick_120);
        console.log("  Price at tick -60:", priceAtTick_60);
        console.log("  Price at tick 0:", priceAtTick0);
        console.log("  Price at tick 60:", priceAtTick60);
        console.log("  Price at tick 120:", priceAtTick120);
    }
    
    function calculatePriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // Price = (sqrtPriceX96 / 2^96)^2
        // More accurate calculation using proper scaling
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        
        // Calculate (sqrtPriceX96 / 2^96)^2
        // This is equivalent to (sqrtPriceX96^2) / 2^192
        uint256 numerator = sqrtPrice * sqrtPrice;
        uint256 denominator = 1 << 192; // 2^192
        
        // Scale by 1e18 for proper decimal representation
        return (numerator * 1e18) / denominator;
    }
    
    function calculatePriceFromTick(int24 tick) internal pure returns (uint256) {
        // Price = 1.0001^tick
        // More accurate calculation for small ticks
        
        if (tick == 0) return 1e18;
        
        // For positive ticks: price = 1.0001^tick
        if (tick > 0) {
            // Use approximation: 1.0001^tick ≈ 1 + tick * 0.0001 for small ticks
            // More precise: 1.0001^tick = (1 + 1/10000)^tick
            uint256 basePrice = 1e18;
            uint256 tickMultiplier = 1e14; // 0.0001 * 1e18
            
            // Convert int24 to uint256 safely
            uint256 tickValue = uint256(uint24(tick));
            
            // For small positive ticks, use linear approximation
            if (tick <= 1000) {
                return basePrice + (tickValue * tickMultiplier);
            }
            
            // For larger ticks, use exponential approximation
            // This is still an approximation - for production use proper math libraries
            return basePrice + (tickValue * tickMultiplier) + (tickValue * tickValue * 1e10) / 2;
        }
        
        // For negative ticks: price = 1.0001^tick = 1 / (1.0001^(-tick))
        uint256 absTick = uint256(uint24(-tick));
        uint256 inversePrice = calculatePriceFromTick(int24(int256(absTick)));
        
        // Return 1 / inversePrice, but avoid division by zero
        if (inversePrice == 0) return 0;
        return (1e18 * 1e18) / inversePrice;
    }
}
