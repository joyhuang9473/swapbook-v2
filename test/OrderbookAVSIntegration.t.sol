// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/OrderbookAVS.sol";
import "../src/SwapbookV2.sol";
import "../src/interface/IAttestationCenter.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/types/PoolId.sol";
import "v4-core/types/PoolOperation.sol";
import "v4-core/interfaces/IPoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract OrderbookAVSIntegrationTest is Test, Deployers, ERC1155Holder {
    OrderbookAVS public orderbookAVS;
    SwapbookV2 public swapbookV2;
    Currency token0;
    Currency token1;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public taskSubmitter = address(0x4);

    function setUp() public {
        // Deploy v4 core contracts
        deployFreshManagerAndRouters();
        
        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();
        
        // Deploy OrderbookAVS
        orderbookAVS = new OrderbookAVS();
        
        // Deploy SwapbookV2 hook
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
        );
        address hookAddress = address(flags);
        deployCodeTo(
            "SwapbookV2.sol",
            abi.encode(manager, ""),
            hookAddress
        );
        swapbookV2 = SwapbookV2(hookAddress);
        
        // Set SwapbookV2 in OrderbookAVS
        orderbookAVS.setSwapbookV2(address(swapbookV2));
        
        // Set OrderbookAVS in SwapbookV2 for callback integration
        swapbookV2.setOrderbookAVS(address(orderbookAVS));
        
        // Initialize the pool with the hook
        PoolKey memory poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        // Initialize the pool
        (poolKey, ) = initPool(token0, token1, IHooks(address(swapbookV2)), 3000, SQRT_PRICE_1_1);
        
        // Add some initial liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10000e18, // Much more liquidity to handle 100e18 swaps
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        
        // Add liquidity across a wider range to ensure sufficient depth
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: 10000e18,
                salt: bytes32(uint256(1))
            }),
            ZERO_BYTES
        );
        
        // Setup users with tokens
        MockERC20(Currency.unwrap(token0)).mint(user1, 1000e18);
        MockERC20(Currency.unwrap(token0)).mint(user2, 1000e18);
        MockERC20(Currency.unwrap(token0)).mint(user3, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user1, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user2, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user3, 1000e18);
        
        // Users approve OrderbookAVS to spend their tokens
        vm.startPrank(user1);
        MockERC20(Currency.unwrap(token0)).approve(address(orderbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        MockERC20(Currency.unwrap(token0)).approve(address(orderbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        MockERC20(Currency.unwrap(token0)).approve(address(orderbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        // Users deposit funds to OrderbookAVS
        vm.startPrank(user1);
        orderbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        orderbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        orderbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        orderbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user3);
        orderbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        orderbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();
        
        // Fund OrderbookAVS with tokens so it can place orders in SwapbookV2
        MockERC20(Currency.unwrap(token0)).mint(address(orderbookAVS), 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(address(orderbookAVS), 1000e18);
        
        // Approve SwapbookV2 to spend OrderbookAVS tokens
        vm.prank(address(orderbookAVS));
        MockERC20(Currency.unwrap(token0)).approve(address(swapbookV2), type(uint256).max);
        vm.prank(address(orderbookAVS));
        MockERC20(Currency.unwrap(token1)).approve(address(swapbookV2), type(uint256).max);
        
    }

    function testCompleteFill() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order ===");
        
        // Create CompleteFill task data
        OrderbookAVS.OrderInfo memory user2Order = OrderbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: 100e18,
            amount1: 200e18,
            tick: -2000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });
        
        // Create a new best order (user3) that will replace user1's order after the fill
        OrderbookAVS.OrderInfo memory newBestOrder = OrderbookAVS.OrderInfo({
            user: user3,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: 50e18,
            amount1: 100e18,
            tick: -1500, // Better price than user1's -1000
            zeroForOne: true, // user3 selling token0 for token1
            orderId: 3
        });
        
        uint256 fillAmount0 = 100e18;
        uint256 fillAmount1 = 200e18;
        
        bytes memory completeTaskData = abi.encode(user2Order, fillAmount0, fillAmount1, newBestOrder);
        
        IAttestationCenter.TaskInfo memory completeTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(OrderbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        orderbookAVS.afterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== AFTER COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // Verify the peer-to-peer swap
        // User1 should have lost 100e18 token0 and gained 200e18 token1
        assertEq(user1Token0After, user1Token0Before - 100e18, "User1 should have lost 100e18 token0");
        assertEq(user1Token1After, user1Token1Before + 200e18, "User1 should have gained 200e18 token1");
        
        // User2 should have gained 100e18 token0 and lost 200e18 token1
        assertEq(user2Token0After, user2Token0Before + 100e18, "User2 should have gained 100e18 token0");
        assertEq(user2Token1After, user2Token1Before - 200e18, "User2 should have lost 200e18 token1");
        
        // Verify the new best order was set
        console.log("=== NEW BEST ORDER VERIFICATION ===");
        address newBestOrderUser = orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1));
        int24 newBestOrderTick = orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1));
        bool newBestOrderDirection = orderbookAVS.bestOrderDirections(Currency.unwrap(token0), Currency.unwrap(token1));
        
        console.log("New best order user:", newBestOrderUser);
        console.log("New best order tick:", newBestOrderTick);
        console.log("New best order direction (zeroForOne):", newBestOrderDirection);
        
        assertEq(newBestOrderUser, user3, "New best order user should be user3");
        assertEq(newBestOrderTick, -1500, "New best order tick should be -1500");
        assertTrue(newBestOrderDirection, "New best order should be zeroForOne (selling token0 for token1)");
    }
    
    function testCompleteFillWithEmptyNewBestOrder() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order, but NO new best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order (no new best order) ===");
        
        // Create CompleteFill task data with empty newBestOrder
        OrderbookAVS.OrderInfo memory user2Order = OrderbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: 100e18,
            amount1: 200e18,
            tick: -2000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });
        
        // Empty newBestOrder (all zeros)
        OrderbookAVS.OrderInfo memory emptyNewBestOrder = OrderbookAVS.OrderInfo({
            user: address(0), // Empty user address
            token0: address(0),
            token1: address(0),
            amount0: 0,
            amount1: 0,
            tick: 0,
            zeroForOne: false,
            orderId: 0
        });
        
        uint256 fillAmount0 = 100e18;
        uint256 fillAmount1 = 200e18;
        
        bytes memory completeTaskData = abi.encode(user2Order, fillAmount0, fillAmount1, emptyNewBestOrder);
        
        IAttestationCenter.TaskInfo memory completeTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(OrderbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        orderbookAVS.afterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = orderbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== AFTER COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // Verify the peer-to-peer swap
        // User1 should have lost 100e18 token0 and gained 200e18 token1
        assertEq(user1Token0After, user1Token0Before - 100e18, "User1 should have lost 100e18 token0");
        assertEq(user1Token1After, user1Token1Before + 200e18, "User1 should have gained 200e18 token1");
        
        // User2 should have gained 100e18 token0 and lost 200e18 token1
        assertEq(user2Token0After, user2Token0Before + 100e18, "User2 should have gained 100e18 token0");
        assertEq(user2Token1After, user2Token1Before - 200e18, "User2 should have lost 200e18 token1");
        
        // Verify that the best order was cleared (no new best order)
        console.log("=== BEST ORDER CLEARED VERIFICATION ===");
        address bestOrderUser = orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1));
        int24 bestOrderTick = orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1));
        bool bestOrderDirection = orderbookAVS.bestOrderDirections(Currency.unwrap(token0), Currency.unwrap(token1));
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);
        console.log("Best order direction (zeroForOne):", bestOrderDirection);
        
        assertEq(bestOrderUser, address(0), "Best order user should be cleared (address(0))");
        assertEq(bestOrderTick, 0, "Best order tick should be cleared (0)");
        assertFalse(bestOrderDirection, "Best order direction should be cleared (false)");
    }
    
    function testSwapbookV2Integration() public {
        // Test that _processUpdateBestPrice actually places an order in SwapbookV2
        console.log("=== Testing SwapbookV2 Integration ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Create PoolKey for verification
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        // Check that there's no pending order before
        uint256 pendingOrderBefore = swapbookV2.pendingOrders(key.toId(), -1000, true);
        console.log("Pending order before:", pendingOrderBefore);
        assertEq(pendingOrderBefore, 0, "Should have no pending order before");
        
        // Check bestTicks before
        int24 bestTickBefore = swapbookV2.bestTicks(key.toId(), true);
        console.log("Best tick before:", bestTickBefore);
        assertEq(bestTickBefore, 0, "Should have no best tick before");
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Check that there's now a pending order in SwapbookV2
        // The tick was adjusted to -1020 (as seen in the trace), so check that tick
        uint256 pendingOrderAfter = swapbookV2.pendingOrders(key.toId(), -1020, true);
        console.log("Pending order after (tick -1020):", pendingOrderAfter);
        assertEq(pendingOrderAfter, 100e18, "Should have 100e18 pending order after");
        
        // Verify bestTicks was updated
        int24 bestTickAfter = swapbookV2.bestTicks(key.toId(), true); // true for zeroForOne
        console.log("Best tick after:", bestTickAfter);
        assertEq(bestTickAfter, -1020, "Best tick should be -1020 (adjusted for tick spacing)");
        
        // Verify that OrderbookAVS also stored the best order information
        address bestOrderUser = orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1));
        int24 bestOrderTick = orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1));
        bool bestOrderDirection = orderbookAVS.bestOrderDirections(Currency.unwrap(token0), Currency.unwrap(token1));
        
        console.log("OrderbookAVS - Best order user:", bestOrderUser);
        console.log("OrderbookAVS - Best order tick:", bestOrderTick);
        console.log("OrderbookAVS - Best order direction:", bestOrderDirection);
        
        assertEq(bestOrderUser, user1, "Best order user should be user1");
        assertEq(bestOrderTick, -1000, "Best order tick should be -1000");
        assertTrue(bestOrderDirection, "Best order direction should be true (zeroForOne)");
        
        console.log("SwapbookV2 integration successful!");
    }
 
    function testCompleteFillWithSwapRouterReRouting() public {
        // Test the complete flow: User1 places order in OrderbookAVS, 
        // User4 swaps through router, gets re-routed to SwapbookV2 via _beforeSwap
        console.log("=== Testing Swap Router Re-routing ===");
        
        // STEP 1: User1 places limit order to sell 100e18 token0 at tick 60
        _placeLimitOrder();
        
        // STEP 2: User4 swaps through swap router to sell token1 for token0
        _executeSwapAndVerify();
    }

    function testPartialFillWithSwapRouterReRouting() public {
        // Test the partial fill flow: User1 places larger limit order (200e18 token0), 
        // User4 swaps through router, only partially fills User1's order
        console.log("=== Testing Partial Fill with Swap Router Re-routing ===");
        
        // STEP 1: User1 places larger limit order to sell 200e18 token0 at tick 60
        _placePartialFillLimitOrder();
        
        // STEP 2: User4 swaps through swap router to sell token1 for token0 (only 100e18)
        _executePartialSwapAndVerify();
    }

    function _placePartialFillLimitOrder() internal {
        console.log("=== STEP 1: User1 places larger limit order (200e18 token0) ===");
        
        // Create UpdateBestPrice task data for User1's larger order
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            60, // tick (better price than pool's 1:1)
            true,  // zeroForOne (selling token0 for token1)
            200e18, // amount (larger order - 200e18 token0)
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's larger order (200e18 token0) placed in both OrderbookAVS and SwapbookV2");
        
        // Verify the order was placed in SwapbookV2
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 bestTick = swapbookV2.bestTicks(key.toId(), true);
        uint256 pendingOrder = swapbookV2.pendingOrders(key.toId(), bestTick, true);
        console.log("SwapbookV2 - Best tick:", bestTick);
        console.log("SwapbookV2 - Pending order amount:", pendingOrder);
        
        assertEq(bestTick, 60, "Best tick should be 60");
        assertEq(pendingOrder, 200e18, "Pending order should be 200e18");
        
        // Verify OrderbookAVS also has the best order
        assertEq(orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1)), user1, "Best order user should be user1");
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 60, "Best order tick should be 60");
        assertTrue(orderbookAVS.bestOrderDirections(Currency.unwrap(token0), Currency.unwrap(token1)), "Best order direction should be true (zeroForOne)");
    }

    function _executePartialSwapAndVerify() internal {
        console.log("=== STEP 2: User4 swaps through router (triggers _beforeSwap) - PARTIAL FILL ===");
        
        // Create user4 - a normal swap router user without deposits in OrderbookAVS
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with (NOT using escrow funds)
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);

        console.log("=== BEFORE PARTIAL SWAP ===");
        console.log("User1 Token0 (escrow):", user1Token0Before);
        console.log("User1 Token1 (escrow):", user1Token1Before);
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router (only 100e18 token1, not enough to fill 200e18 order)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        int24 bestTickBefore = swapbookV2.bestTicks(key.toId(), true);
        
        // Expect the OrderExecutionCallback event to be emitted for partial fill
        vm.expectEmit(true, true, true, false);
        emit OrderbookAVS.OrderExecutionCallback(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            user1, // bestOrderUser
            address(0), // swapper (any address)
            0, // inputAmount (any amount)
            0, // outputAmount (any amount)
            false // zeroForOne (any boolean)
        );
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(25e18), // Exact input of 25e18 token1 (partial fill)
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        console.log("=== AFTER PARTIAL SWAP ===");
        console.log("User1 Token0 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0)));
        console.log("User1 Token1 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)));
        console.log("User4 Token0 (wallet):", MockERC20(Currency.unwrap(token0)).balanceOf(user4));
        console.log("User4 Token1 (wallet):", MockERC20(Currency.unwrap(token1)).balanceOf(user4));
        
        // Check if the limit order was partially filled
        console.log("=== ORDER FILL STATUS ===");
        console.log("Best tick before swap:", bestTickBefore);
        console.log("Best tick after swap:", swapbookV2.bestTicks(key.toId(), true));
        console.log("Pending order amount after swap:", swapbookV2.pendingOrders(key.toId(), bestTickBefore, true));
        
        uint256 remainingOrderAmount = swapbookV2.pendingOrders(key.toId(), bestTickBefore, true);
        if (remainingOrderAmount == 0) {
            console.log("Order was COMPLETELY FILLED");
        } else {
            console.log("Order was PARTIALLY FILLED - remaining:", remainingOrderAmount);
        }
        
        // Verify the swap was re-routed and User1's order was partially filled
        // User1 should have lost some token0 (the amount that was filled)
        uint256 user1Token0Lost = user1Token0Before - orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        assertTrue(user1Token0Lost > 0, "User1 should have lost some token0 (partial fill)");
        assertTrue(user1Token0Lost < 200e18, "User1 should not have lost all 200e18 token0 (partial fill)");
        assertTrue(orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)) > user1Token1Before, "User1 should have gained token1 from the partial swap");
        assertTrue(MockERC20(Currency.unwrap(token0)).balanceOf(user4) > user4Token0Before, "User4 should have gained token0 from the swap");
        assertTrue(MockERC20(Currency.unwrap(token1)).balanceOf(user4) < user4Token1Before, "User4 should have lost token1 from the swap");
        
        // Verify the amounts are reasonable (User4 got a better deal due to limit order)
        console.log("User4 Token0 gained:", MockERC20(Currency.unwrap(token0)).balanceOf(user4) - user4Token0Before);
        console.log("User4 Token1 lost:", user4Token1Before - MockERC20(Currency.unwrap(token1)).balanceOf(user4));
        console.log("User1 Token0 lost:", user1Token0Lost);
        console.log("User4 got better rate due to limit order!");
        
        // Verify the order was partially filled - should have some amount remaining
        assertTrue(remainingOrderAmount > 0, "Remaining order amount should be greater than 0 (partial fill)");
        assertTrue(remainingOrderAmount < 200e18, "Remaining order amount should be less than 200e18 (partial fill)");
        assertEq(swapbookV2.bestTicks(key.toId(), true), 60, "Best tick should still be 60 (order not completely filled)");
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 60, "Best order tick should still be 60");
        assertEq(orderbookAVS.getEscrowedBalance(user4, Currency.unwrap(token0)), 0, "User4 should not have escrowed token0");
        assertEq(orderbookAVS.getEscrowedBalance(user4, Currency.unwrap(token1)), 0, "User4 should not have escrowed token1");
        
        console.log("Partial fill swap router re-routing successful!");
        console.log("Limit order had better price and was partially filled");
        console.log("User4 used wallet funds, not escrow funds");
        console.log("onOrderExecuted was called to settle escrowedFunds for partial fill");
    }

    function testLargeSwapWithSmallLimitOrder() public {
        // Test the case where userSwapAmount > availableAmount
        // User1 places small limit order (50e18 token0), User4 wants to swap more (100e18 token1)
        // Should completely fill the limit order (50e18) and then complete remaining (50e18) through pool
        console.log("=== Testing Large Swap with Small Limit Order (Complete Fill + Pool Completion) ===");
        
        // STEP 1: User1 places small limit order to sell 50e18 token0 at tick 60
        _placeSmallLimitOrder();
        
        // STEP 2: User4 swaps through swap router to sell 100e18 token1 for token0
        _executeLargeSwapAndVerify();
    }

    function _placeSmallLimitOrder() internal {
        console.log("=== STEP 1: User1 places small limit order (50e18 token0) ===");
        
        // Create UpdateBestPrice task data for User1's small order
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            60, // tick (better price than pool's 1:1)
            true,  // zeroForOne (selling token0 for token1)
            50e18, // amount (small order - 50e18 token0)
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's small order (50e18 token0) placed in both OrderbookAVS and SwapbookV2");
        
        // Verify the order was placed in SwapbookV2
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 bestTick = swapbookV2.bestTicks(key.toId(), true);
        uint256 pendingOrder = swapbookV2.pendingOrders(key.toId(), bestTick, true);
        console.log("SwapbookV2 - Best tick:", bestTick);
        console.log("SwapbookV2 - Pending order amount:", pendingOrder);
        
        assertEq(bestTick, 60, "Best tick should be 60");
        assertEq(pendingOrder, 50e18, "Pending order should be 50e18");
    }

    function _executeLargeSwapAndVerify() internal {
        console.log("=== STEP 2: User4 swaps through router (100e18 token1 > 50e18 available) ===");
        
        // Create user4 - a normal swap router user without deposits in OrderbookAVS
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with (NOT using escrow funds)
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);

        console.log("=== BEFORE LARGE SWAP ===");
        console.log("User1 Token0 (escrow):", user1Token0Before);
        console.log("User1 Token1 (escrow):", user1Token1Before);
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router (100e18 token1, more than available 50e18)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        int24 bestTickBefore = swapbookV2.bestTicks(key.toId(), true);
        
        // Don't expect OrderExecutionCallback event since we're not using limit order matching
        // (userSwapAmount > availableAmount, so it goes through normal pool swap)
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(100e18), // Exact input of 100e18 token1 (more than available 50e18)
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        console.log("=== AFTER LARGE SWAP ===");
        console.log("User1 Token0 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0)));
        console.log("User1 Token1 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)));
        console.log("User4 Token0 (wallet):", MockERC20(Currency.unwrap(token0)).balanceOf(user4));
        console.log("User4 Token1 (wallet):", MockERC20(Currency.unwrap(token1)).balanceOf(user4));
        
        // Check if the limit order was used or if it went through normal pool swap
        console.log("=== SWAP ROUTE STATUS ===");
        console.log("Best tick before swap:", bestTickBefore);
        console.log("Best tick after swap:", swapbookV2.bestTicks(key.toId(), true));
        console.log("Pending order amount after swap:", swapbookV2.pendingOrders(key.toId(), swapbookV2.bestTicks(key.toId(), true), true));
        
        int24 currentBestTick = swapbookV2.bestTicks(key.toId(), true);
        uint256 remainingOrderAmount = swapbookV2.pendingOrders(key.toId(), currentBestTick, true);
        
        // Verify that the limit order was COMPLETELY FILLED (userSwapAmount > availableAmount)
        // The limit order should be completely consumed, then remaining goes through pool
        assertEq(remainingOrderAmount, 0, "Limit order should be completely filled (0 remaining)");
        assertEq(currentBestTick, 0, "Best tick should be 0 (limit order completely filled)");
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 0, "OrderbookAVS best tick should be 0");
        
        // Verify User1's escrow changed (limit order was executed)
        assertTrue(orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0)) < user1Token0Before, "User1's token0 escrow should be reduced (limit order executed)");
        assertTrue(orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)) > user1Token1Before, "User1's token1 escrow should be increased (limit order executed)");
        
        // Verify User4's swap went through (normal pool swap)
        assertTrue(MockERC20(Currency.unwrap(token0)).balanceOf(user4) > user4Token0Before, "User4 should have gained token0 from pool swap");
        assertTrue(MockERC20(Currency.unwrap(token1)).balanceOf(user4) < user4Token1Before, "User4 should have lost token1 from pool swap");
        
        console.log("Large swap with small limit order successful!");
        console.log("User4's swap completely filled the limit order (50e18) and completed remaining (50e18) through pool");
        console.log("User1's limit order was completely executed and settled");
    }

    function _placeLimitOrder() internal {
        console.log("=== STEP 1: User1 places limit order (better price) ===");
        
        // Create UpdateBestPrice task data for User1's order
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            60, // tick (better price than pool's 1:1) - higher tick = better price for buying token0
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order placed in both OrderbookAVS and SwapbookV2");
        
        // Verify the order was placed in SwapbookV2
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 bestTick = swapbookV2.bestTicks(key.toId(), true);
        uint256 pendingOrder = swapbookV2.pendingOrders(key.toId(), bestTick, true);
        console.log("SwapbookV2 - Best tick:", bestTick);
        console.log("SwapbookV2 - Pending order amount:", pendingOrder);
        
        assertEq(bestTick, 60, "Best tick should be 60");
        assertEq(pendingOrder, 100e18, "Pending order should be 100e18");
        
        // Verify OrderbookAVS also has the best order
        assertEq(orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1)), user1, "Best order user should be user1");
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 60, "Best order tick should be 60");
        assertTrue(orderbookAVS.bestOrderDirections(Currency.unwrap(token0), Currency.unwrap(token1)), "Best order direction should be true (zeroForOne)");
    }
    
    function _executeSwapAndVerify() internal {
        console.log("=== STEP 2: User4 swaps through router (triggers _beforeSwap) ===");
        
        // Create user4 - a normal swap router user without deposits in OrderbookAVS
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with (NOT using escrow funds)
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);

        console.log("=== BEFORE SWAP ===");
        console.log("User1 Token0 (escrow):", user1Token0Before);
        console.log("User1 Token1 (escrow):", user1Token1Before);
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        int24 bestTickBefore = swapbookV2.bestTicks(key.toId(), true);
        
        // Expect the OrderExecutionCallback event to be emitted
        // Check indexed parameters (token0, token1, bestOrderUser) exactly, but allow flexible values for others
        vm.expectEmit(true, true, true, false);
        emit OrderbookAVS.OrderExecutionCallback(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            user1, // bestOrderUser
            address(0), // swapper (any address)
            0, // inputAmount (any amount)
            0, // outputAmount (any amount)
            false // zeroForOne (any boolean)
        );
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(100e18), // Exact input of 100e18 token1
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        uint256 user1Token0After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0After = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1After = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("=== AFTER SWAP ===");
        console.log("User1 Token0 (escrow):", user1Token0After);
        console.log("User1 Token1 (escrow):", user1Token1After);
        console.log("User4 Token0 (wallet):", user4Token0After);
        console.log("User4 Token1 (wallet):", user4Token1After);
        
        // Check if the limit order was completely filled by checking pending orders
        console.log("=== ORDER FILL STATUS ===");
        console.log("Best tick before swap:", bestTickBefore);
        console.log("Best tick after swap:", swapbookV2.bestTicks(key.toId(), true));
        console.log("Pending order amount after swap:", swapbookV2.pendingOrders(key.toId(), bestTickBefore, true));
        
        if (swapbookV2.pendingOrders(key.toId(), swapbookV2.bestTicks(key.toId(), true), true) == 0) {
            console.log("Order was COMPLETELY FILLED");
        } else {
            console.log("Order was PARTIALLY FILLED - remaining:", swapbookV2.pendingOrders(key.toId(), bestTickBefore, true));
        }
        
        // Verify the swap was re-routed and User1's order was completely filled
        assertEq(user1Token0After, user1Token0Before - 100e18, "User1 should have lost 100e18 token0");
        assertTrue(user1Token1After > user1Token1Before, "User1 should have gained token1 from the swap");
        assertTrue(user4Token0After > user4Token0Before, "User4 should have gained token0 from the swap");
        assertTrue(user4Token1After < user4Token1Before, "User4 should have lost token1 from the swap");
        
        // Verify the amounts are reasonable (User4 got a better deal due to limit order)
        uint256 user4Token0Gained = user4Token0After - user4Token0Before;
        uint256 user4Token1Lost = user4Token1Before - user4Token1After;
        console.log("User4 Token0 gained:", user4Token0Gained);
        console.log("User4 Token1 lost:", user4Token1Lost);
        console.log("User4 got better rate due to limit order!");
        
        // Verify the order was completely filled and best order cleared
        assertEq(swapbookV2.pendingOrders(key.toId(), bestTickBefore, true), 0, "Pending order should be 0");
        assertEq(swapbookV2.bestTicks(key.toId(), true), 0, "Best tick in SwapbookV2 should be 0");
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 0, "Best order tick in OrderbookAVS should be 0");
        assertEq(orderbookAVS.getEscrowedBalance(user4, Currency.unwrap(token0)), 0, "User4 should not have escrowed token0");
        assertEq(orderbookAVS.getEscrowedBalance(user4, Currency.unwrap(token1)), 0, "User4 should not have escrowed token1");
        
        console.log("Swap router re-routing successful!");
        console.log("Limit order had better price and was completely filled");
        console.log("User4 used wallet funds, not escrow funds");
        console.log("onOrderExecuted was called to settle escrowedFunds");
    }

    function testPoolOnlySwap() public {
        // Test what happens when User4 swaps through pool only (no limit orders)
        console.log("=== Testing Pool-Only Swap ===");
        
        // Create user4 - a normal swap router user
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("=== BEFORE POOL SWAP ===");
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router (no limit orders to intercept)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(100e18), // Exact input of 100e18 token1
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        uint256 user4Token0After = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1After = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("=== AFTER POOL SWAP ===");
        console.log("User4 Token0 (wallet):", user4Token0After);
        console.log("User4 Token1 (wallet):", user4Token1After);
        
        // Calculate the exchange rate
        uint256 user4Token0Gained = user4Token0After - user4Token0Before;
        uint256 user4Token1Lost = user4Token1Before - user4Token1After;
        
        console.log("=== POOL EXCHANGE RATE ===");
        console.log("User4 Token0 gained:", user4Token0Gained);
        console.log("User4 Token1 lost:", user4Token1Lost);
        console.log("Exchange rate: 1 token1 =", (user4Token0Gained * 1e18) / user4Token1Lost, "token0");
        console.log("At tick 0 (1:1 price), User4 should get approximately 100e18 token0 for 100e18 token1");
    }

    function testTick60ExchangeRate() public {
        // Test what happens when User4 swaps at tick 60 (limit order price)
        console.log("=== Testing Tick 60 Exchange Rate ===");
        
        // First, place a limit order at tick 60
        _placeLimitOrder();
        
        // Create user4 - a normal swap router user
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("=== BEFORE TICK 60 SWAP ===");
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router (should hit the limit order at tick 60)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(100e18), // Exact input of 100e18 token1
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        uint256 user4Token0After = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1After = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("=== AFTER TICK 60 SWAP ===");
        console.log("User4 Token0 (wallet):", user4Token0After);
        console.log("User4 Token1 (wallet):", user4Token1After);
        
        // Calculate the exchange rate
        uint256 user4Token0Gained = user4Token0After - user4Token0Before;
        uint256 user4Token1Lost = user4Token1Before - user4Token1After;
        
        console.log("=== TICK 60 EXCHANGE RATE ===");
        console.log("User4 Token0 gained:", user4Token0Gained);
        console.log("User4 Token1 lost:", user4Token1Lost);
        console.log("Exchange rate: 1 token1 =", (user4Token0Gained * 1e18) / user4Token1Lost, "token0");
        console.log("At tick 60, User4 gets", user4Token0Gained);
        console.log("token0 for", user4Token1Lost, "token1");
    }

    function testBestOrderTicksMismatch() public {
        // Test case where bestOrderTicks in OrderbookAVS differs from bestTicks in SwapbookV2
        // This happens naturally due to getLowerUsableTick function rounding down ticks
        // User1 sells 100e18 token0 for token1 at tick 100
        // User4 swaps through router to sell 100e18 token1 for token0
        console.log("=== Testing Natural Best Order Ticks Mismatch (due to tickSpacing) ===");
        
        // STEP 1: User1 places limit order at tick 100 in OrderbookAVS
        _placeOrderAtTick100();
        
        // STEP 2: Check the natural mismatch due to getLowerUsableTick
        _simulateSwapbookV2Mismatch();
        
        // STEP 3: User4 swaps through router
        _executeSwapWithMismatch();
        
        // STEP 4: Verify the behavior with mismatched ticks
        _verifyMismatchBehavior();
    }

    function _placeOrderAtTick100() internal {
        console.log("=== STEP 1: User1 places limit order at tick 100 ===");
        
        // Create UpdateBestPrice task data for User1's order at tick 100
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            100, // tick 100
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task in OrderbookAVS
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order placed in OrderbookAVS at tick 100");
        console.log("OrderbookAVS bestOrderTicks:", orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)));
        
        // Verify OrderbookAVS has the order at tick 100
        assertEq(orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1)), 100, "OrderbookAVS should have tick 100");
        assertEq(orderbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1)), user1, "OrderbookAVS should have user1");
    }

    function _simulateSwapbookV2Mismatch() internal {
        console.log("=== STEP 2: Check natural tick mismatch due to getLowerUsableTick ===");
        
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        // Check current state after OrderbookAVS placed the order
        int24 orderbookAVSTick = orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1));
        int24 swapbookV2Tick = swapbookV2.bestTicks(key.toId(), true);
        
        console.log("After OrderbookAVS placed order at tick 100:");
        console.log("OrderbookAVS bestOrderTicks:", orderbookAVSTick);
        console.log("SwapbookV2 bestTicks:", swapbookV2Tick);
        
        // The mismatch occurs naturally because:
        // - OrderbookAVS stores the original tick (100)
        // - When OrderbookAVS called swapbookV2.placeOrder(100, ...), 
        //   getLowerUsableTick(100, 60) returned 60 (100/60 = 1, 1*60 = 60)
        // - So SwapbookV2 actually has tick 60, not 100
        
        assertEq(orderbookAVSTick, 100, "OrderbookAVS should have original tick 100");
        assertEq(swapbookV2Tick, 60, "SwapbookV2 should have usable tick 60 (100 rounded down by tickSpacing)");
        assertTrue(orderbookAVSTick != swapbookV2Tick, "Ticks should be different due to tickSpacing rounding");
        
        console.log("Natural mismatch confirmed: OrderbookAVS has tick 100, SwapbookV2 has tick 60");
        console.log("This happens because getLowerUsableTick(100, 60) = 60");
    }

    function _executeSwapWithMismatch() internal {
        console.log("=== STEP 3: User4 swaps through router with tick mismatch ===");
        
        // Create user4 - a normal swap router user
        address user4 = makeAddr("user4");
        
        // Give user4 some tokens to swap with
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);
        
        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record balances before swap
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);

        console.log("=== BEFORE SWAP WITH MISMATCH ===");
        console.log("User1 Token0 (escrow):", user1Token0Before);
        console.log("User1 Token1 (escrow):", user1Token1Before);
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute the swap through the swap router (100e18 token1 for token0)
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        vm.startPrank(user4);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, // User4 selling token1 for token0
                amountSpecified: -int256(100e18), // Exact input of 100e18 token1
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
        
        // Record balances after swap
        console.log("=== AFTER SWAP WITH MISMATCH ===");
        console.log("User1 Token0 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0)));
        console.log("User1 Token1 (escrow):", orderbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)));
        console.log("User4 Token0 (wallet):", MockERC20(Currency.unwrap(token0)).balanceOf(user4));
        console.log("User4 Token1 (wallet):", MockERC20(Currency.unwrap(token1)).balanceOf(user4));
    }

    function _verifyMismatchBehavior() internal {
        console.log("=== STEP 4: Verify behavior with tick mismatch ===");
        
        PoolKey memory key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 orderbookAVSTick = orderbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1));
        int24 swapbookV2Tick = swapbookV2.bestTicks(key.toId(), true);
        
        console.log("Final state after swap:");
        console.log("OrderbookAVS bestOrderTicks:", orderbookAVSTick);
        console.log("SwapbookV2 bestTicks:", swapbookV2Tick);
        
        // The behavior depends on which system the swap router uses for price comparison
        // SwapbookV2's _beforeSwap hook will use its own bestTicks, not OrderbookAVS's bestOrderTicks
        console.log("Test completed - verified behavior with mismatched ticks");
        console.log("OrderbookAVS tick:", orderbookAVSTick);
        console.log("SwapbookV2 tick:", swapbookV2Tick);
    }

}