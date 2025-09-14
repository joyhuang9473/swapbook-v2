// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
 
// Foundry libraries
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
 
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
 
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
 
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
 
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IPoolManager.sol";
 
import {SwapbookV2} from "../src/SwapbookV2.sol";
 
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract SwapbookV2Test is Test, Deployers, ERC1155Holder {
    // Use the libraries
    using StateLibrary for IPoolManager;
 
    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;
 
    SwapbookV2 hook;
    
    function setUp() public {
        // Deploy v4 core contracts
        deployFreshManagerAndRouters();
    
        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();
    
        // Deploy our hook
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        address hookAddress = address(flags);
        deployCodeTo(
            "SwapbookV2.sol",
            abi.encode(manager, ""),
            hookAddress
        );
        hook = SwapbookV2(hookAddress);
    
        // Approve our hook address to spend these tokens as well
        MockERC20(Currency.unwrap(token0)).approve(
            address(hook),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(hook),
            type(uint256).max
        );
    
        // Initialize a pool with these two tokens
        (key, ) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1);
    
        // Add initial liquidity to the pool

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_placeOrder() public {
        // Place a zeroForOne take-profit order
        // for 10e18 token0 tokens
        // at tick 100
        int24 tick = 100;
        uint256 amount = 10e18;
        bool zeroForOne = true;
    
        // Note the original balance of token0 we have
        uint256 originalBalance = token0.balanceOfSelf();
    
        // Place the order
        int24 tickLower = hook.placeOrder(key, tick, zeroForOne, amount);
    
        // Note the new balance of token0 we have
        uint256 newBalance = token0.balanceOfSelf();
    
        // Since we deployed the pool contract with tick spacing = 60
        // i.e. the tick can only be a multiple of 60
        // the tickLower should be 60 since we placed an order at tick 100
        assertEq(tickLower, 60);
    
        // Ensure that our balance of token0 was reduced by `amount` tokens
        assertEq(originalBalance - newBalance, amount);
    
        // Check the balance of ERC-1155 tokens we received
        uint256 orderId = hook.getOrderId(key, tickLower, zeroForOne);
        uint256 tokenBalance = hook.balanceOf(address(this), orderId);
    
        // Ensure that we were, in fact, given ERC-1155 tokens for the order
        // equal to the `amount` of token0 tokens we placed the order for
        assertTrue(orderId != 0);
        assertEq(tokenBalance, amount);
    }

    function test_cancelOrder() public {
        // Place an order as earlier
        int24 tick = 100;
        uint256 amount = 10e18;
        bool zeroForOne = true;
    
        uint256 originalBalance = token0.balanceOfSelf();
        int24 tickLower = hook.placeOrder(key, tick, zeroForOne, amount);
        uint256 newBalance = token0.balanceOfSelf();
    
        assertEq(tickLower, 60);
        assertEq(originalBalance - newBalance, amount);
    
        // Check the balance of ERC-1155 tokens we received
        uint256 orderId = hook.getOrderId(key, tickLower, zeroForOne);
        uint256 tokenBalance = hook.balanceOf(address(this), orderId);
        assertEq(tokenBalance, amount);
    
        // Cancel the order
        hook.cancelOrder(key, tickLower, zeroForOne, amount);
    
        // Check that we received our token0 tokens back, and no longer own any ERC-1155 tokens
        uint256 finalBalance = token0.balanceOfSelf();
        assertEq(finalBalance, originalBalance);
    
        tokenBalance = hook.balanceOf(address(this), orderId);
        assertEq(tokenBalance, 0);
    }

    function test_afterSwapCompleteFill() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        
        // Setup users
        _setupUsers(user1, user2);

        // Record balances BEFORE placing the order
        uint256 user1Token0Before = token0.balanceOf(user1);
        uint256 user1Token1Before = token1.balanceOf(user1);
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);
        
        // User1 places limit order
        uint256 orderId = _placeLimitOrder_tick_60(user1);

        // Expect the LimitOrderExecutedAfterSwap event to be emitted
        vm.expectEmit(true, true, true, true);
        emit SwapbookV2.LimitOrderExecutedAfterSwap(); // outputAmount will be set by the contract

        // User2 performs swap
        _performSwap(user2);

        // Check order was filled and redeem
        uint256 claimableOutput = hook.claimableOutputTokens(orderId);
        assertTrue(claimableOutput > 0, "Order should have been filled through afterSwap");
        
        vm.startPrank(user1);
        hook.redeem(key, 60, true, 5e18);
        vm.stopPrank();
        
        // Debug and verify results
        _debugAndVerify(user1, user2, user1Token0Before, user1Token1Before, user2Token0Before, user2Token1Before);
    }

    function test_beforeSwapCompleteFill() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        
        // Setup users
        _setupUsers(user1, user2);

        // Record balances BEFORE placing the order
        uint256 user1Token0Before = token0.balanceOf(user1);
        uint256 user1Token1Before = token1.balanceOf(user1);
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);
        
        // User1 places limit order
        uint256 orderId = _placeLimitOrder_tick_0(user1);

        // Expect the LimitOrderExecutedBeforeSwap event to be emitted
        vm.expectEmit(true, true, true, true);
        emit SwapbookV2.LimitOrderExecutedBeforeSwap(); // outputAmount will be set by the contract

        // User2 performs swap
        _performSwap(user2);

        // Check order was filled and redeem
        uint256 claimableOutput = hook.claimableOutputTokens(orderId);
        assertTrue(claimableOutput > 0, "Order should have been filled through beforeSwap");
        
        vm.startPrank(user1);
        hook.redeem(key, 0, true, 5e18);
        vm.stopPrank();
        
        // Debug and verify results
        _debugAndVerify(user1, user2, user1Token0Before, user1Token1Before, user2Token0Before, user2Token1Before);
    }

    function test_swapWithoutHook() public {
        address user2 = address(0x2);
        
        // Setup user2
        vm.startPrank(address(manager));
        MockERC20(Currency.unwrap(token0)).mint(user2, 10e18);
        MockERC20(Currency.unwrap(token1)).mint(user2, 10e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user2Token0Before = token0.balanceOf(user2);
        uint256 user2Token1Before = token1.balanceOf(user2);
        
        // User2 performs swap using the SAME pool but WITHOUT any limit orders
        // This simulates what would happen if there were no limit orders in the book
        vm.startPrank(user2);
        swapRouter.swap(
            key, // Same pool as the hook test
            SwapParams({
                zeroForOne: false, // Swap token1 for token0
                amountSpecified: -int256(1e18), // Exact input
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Check final balances
        uint256 user2Token0After = token0.balanceOf(user2);
        uint256 user2Token1After = token1.balanceOf(user2);
        
        console.log("=== USER2 WITHOUT Swapbook Limit Orders ===");
        console.log("Token0 Before:", user2Token0Before);
        console.log("Token0 After:", user2Token0After);
        console.log("Token0 Difference:", int256(user2Token0After) - int256(user2Token0Before));
        console.log("Token1 Before:", user2Token1Before);
        console.log("Token1 After:", user2Token1After);
        console.log("Token1 Difference:", int256(user2Token1After) - int256(user2Token1Before));
    }

    function _setupUsers(address user1, address user2) internal {
        vm.startPrank(address(manager));
        MockERC20(Currency.unwrap(token0)).mint(user1, 10e18);
        MockERC20(Currency.unwrap(token1)).mint(user1, 10e18);
        MockERC20(Currency.unwrap(token0)).mint(user2, 10e18);
        MockERC20(Currency.unwrap(token1)).mint(user2, 10e18);
        vm.stopPrank();
        
        vm.startPrank(user1);
        MockERC20(Currency.unwrap(token0)).approve(address(hook), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _placeLimitOrder_tick_0(address user) internal returns (uint256) {
        vm.startPrank(user);
        int24 tickLower = hook.placeOrder(key, 0, true, 5e18);
        assertEq(tickLower, 0); // For tick 0 with tickSpacing 60, the usable tick is 0
        uint256 orderId = hook.getOrderId(key, tickLower, true);
        uint256 tokenBalance = hook.balanceOf(user, orderId);
        assertEq(tokenBalance, 5e18);
        vm.stopPrank();
        return orderId;
    }

    function _placeLimitOrder_tick_60(address user) internal returns (uint256) {
        vm.startPrank(user);
        int24 tickLower = hook.placeOrder(key, 60, true, 10e18); // Place a larger order (10e18)
        assertEq(tickLower, 60);
        uint256 orderId = hook.getOrderId(key, tickLower, true);
        uint256 tokenBalance = hook.balanceOf(user, orderId);
        assertEq(tokenBalance, 10e18);
        vm.stopPrank();
        return orderId;
    }

    function _performSwap(address user) internal {
        vm.startPrank(user);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(1e18),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    function _debugAndVerify(address user1, address user2, uint256 user1Token0Before, uint256 user1Token1Before, uint256 user2Token0Before, uint256 user2Token1Before) internal {
        console.log("=== USER1 (Limit Order Seller) ===");
        console.log("Token0 Before:", user1Token0Before);
        console.log("Token0 After:", token0.balanceOf(user1));
        console.log("Token0 Difference:", int256(token0.balanceOf(user1)) - int256(user1Token0Before));
        console.log("Token1 Before:", user1Token1Before);
        console.log("Token1 After:", token1.balanceOf(user1));
        console.log("Token1 Difference:", int256(token1.balanceOf(user1)) - int256(user1Token1Before));
        
        console.log("=== USER2 (Swap Buyer) ===");
        console.log("Token0 Before:", user2Token0Before);
        console.log("Token0 After:", token0.balanceOf(user2));
        console.log("Token0 Difference:", int256(token0.balanceOf(user2)) - int256(user2Token0Before));
        console.log("Token1 Before:", user2Token1Before);
        console.log("Token1 After:", token1.balanceOf(user2));
        console.log("Token1 Difference:", int256(token1.balanceOf(user2)) - int256(user2Token1Before));
        
        assertTrue(token0.balanceOf(user1) < user1Token0Before, "User1 should have lost token0 from selling");
        assertTrue(token1.balanceOf(user1) > user1Token1Before, "User1 should have gained token1 from selling");
        assertTrue(token0.balanceOf(user2) > user2Token0Before, "User2 should have gained token0 from buying");
        assertTrue(token1.balanceOf(user2) < user2Token1Before, "User2 should have lost token1 from buying");
    }

}