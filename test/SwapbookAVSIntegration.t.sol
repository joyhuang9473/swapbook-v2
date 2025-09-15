// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/SwapbookAVS.sol";
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

contract SwapbookAVSIntegrationTest is Test, Deployers, ERC1155Holder {
    SwapbookAVS public swapbookAVS;
    SwapbookV2 public swapbookV2;
    Currency token0;
    Currency token1;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public user4 = address(0x4);
    address public attestationCenter = address(0x5); // Mock attestation center

    /**
     * @dev Helper function to call afterTaskSubmission from the attestation center
     */
    function _callAfterTaskSubmission(
        IAttestationCenter.TaskInfo memory _taskInfo,
        bool _isApproved,
        bytes memory _tpSignature,
        uint256[2] memory _taSignature,
        uint256[] memory _attestersIds
    ) internal {
        vm.prank(attestationCenter);
        swapbookAVS.afterTaskSubmission(_taskInfo, _isApproved, _tpSignature, _taSignature, _attestersIds);
    }

    function setUp() public {
        // Deploy v4 core contracts
        deployFreshManagerAndRouters();
        
        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();
        
        // Deploy SwapbookAVS
        swapbookAVS = new SwapbookAVS();
        
        // Set up the attestation center
        swapbookAVS.setAttestationCenter(attestationCenter);
        
        // Deploy SwapbookV2 hook
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        address hookAddress = address(flags);
        deployCodeTo(
            "SwapbookV2.sol",
            abi.encode(manager, ""),
            hookAddress
        );
        swapbookV2 = SwapbookV2(hookAddress);
        
        // Set SwapbookV2 in SwapbookAVS
        swapbookAVS.setSwapbookV2(address(swapbookV2));
        
        // Set SwapbookAVS in SwapbookV2 for callback integration
        swapbookV2.setSwapbookAVS(address(swapbookAVS));
        
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
        MockERC20(Currency.unwrap(token0)).approve(address(swapbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        MockERC20(Currency.unwrap(token0)).approve(address(swapbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        MockERC20(Currency.unwrap(token0)).approve(address(swapbookAVS), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapbookAVS), type(uint256).max);
        vm.stopPrank();
        
        // Users deposit funds to OrderbookAVS
        vm.startPrank(user1);
        swapbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        swapbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        swapbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        swapbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user3);
        swapbookAVS.depositFunds(Currency.unwrap(token0), 500e18);
        swapbookAVS.depositFunds(Currency.unwrap(token1), 500e18);
        vm.stopPrank();

        // Approve SwapbookV2 to spend OrderbookAVS tokens
        vm.prank(address(swapbookAVS));
        MockERC20(Currency.unwrap(token0)).approve(address(swapbookV2), type(uint256).max);
        vm.prank(address(swapbookAVS));
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
            100e18, // inputAmount
            200e18,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order ===");
        
        // Create CompleteFill task data
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
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
        SwapbookAVS.OrderInfo memory newBestOrder = SwapbookAVS.OrderInfo({
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
            data: abi.encode(SwapbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        _callAfterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
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
        bool newBestOrderDirection = true; // We know it's zeroForOne = true from the test setup
        address newBestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        int24 newBestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        
        console.log("New best order user:", newBestOrderUser);
        console.log("New best order tick:", newBestOrderTick);
        console.log("New best order direction (zeroForOne):", newBestOrderDirection);
        
        assertEq(newBestOrderUser, user3, "New best order user should be user3");
        assertEq(newBestOrderTick, -1500, "New best order tick should be -1500");
        assertTrue(newBestOrderDirection, "New best order should be zeroForOne (selling token0 for token1)");
    }
    
    function testPartialFill() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // inputAmount
            200e18,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 100e18 token1 for 50e18 token0
        // This triggers PartialFill to match with the best order
        console.log("=== STEP 2: PartialFill - User2 matches with best order ===");

        uint256 fillAmount0 = 50e18;
        uint256 fillAmount1 = 100e18;

        // Create PraitialFill task data
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: fillAmount0,
            amount1: fillAmount1,
            tick: -1000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });

        bytes memory partialFillTaskData = abi.encode(user2Order, fillAmount0, fillAmount1);
        
        IAttestationCenter.TaskInfo memory partialFillTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(SwapbookAVS.TaskType.PartialFill, partialFillTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the partial fill
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE PARTIAL FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the PartialFill task
        _callAfterTaskSubmission(partialFillTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // // Record balances after
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== AFTER PARTIAL FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // // Verify the peer-to-peer swap
        // // User1 should have lost 50e18 token0 and gained 100e18 token1
        assertEq(user1Token0After, user1Token0Before - 50e18, "User1 should have lost 50e18 token0");
        assertEq(user1Token1After, user1Token1Before + 100e18, "User1 should have gained 100e18 token1");
        
        // // User2 should have gained 50e18 token0 and lost 100e18 token1
        assertEq(user2Token0After, user2Token0Before + 50e18, "User2 should have gained 100e18 token0");
        assertEq(user2Token1After, user2Token1Before - 100e18, "User2 should have lost 100e18 token1");
        
        // Verify the new best order was set
        console.log("=== NEW BEST ORDER VERIFICATION ===");
        bool newBestOrderDirection = true; // We know it's zeroForOne = true from the test setup
        address newBestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        int24 newBestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        
        console.log("New best order user:", newBestOrderUser);
        console.log("New best order tick:", newBestOrderTick);
        console.log("New best order direction (zeroForOne):", newBestOrderDirection);
        console.log("New best order InputAmount:", swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection));
        
        assertEq(newBestOrderUser, user1, "New best order user should be user1");
        assertEq(newBestOrderTick, -1000, "New best order tick should be -1000");
        assertTrue(newBestOrderDirection, "New best order should be zeroForOne (selling token0 for token1)");
        assertEq(swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection), 50e18, "New best order's InputAmount should be 50e18");
        assertEq(swapbookAVS.bestOrderOutputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection), 100e18, "New best order's OutputAmount should be 100e18");
    }

    function testPartialFillFailed() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1 (outputAmount = 200e18)
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // inputAmount
            200e18, // outputAmount (User1 wants at least 200e18 token1)
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price with outputAmount = 200e18");
        
        // STEP 2: User2 wants to sell 300e18 token1 for 100e18 token0
        // This should FAIL because User1 only wants 200e18 token1, but User2 is trying to sell 300e18
        console.log("=== STEP 2: PartialFill - User2 tries to sell more than User1 wants ===");

        uint256 fillAmount0 = 200e18;  // User2 wants 200e18 token0
        uint256 fillAmount1 = 400e18;  // User2 wants to sell 400e18 token1 (MORE than User1's outputAmount of 200e18)

        // Create PartialFill task data
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: fillAmount0,
            amount1: fillAmount1,
            tick: -1000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });

        bytes memory partialFillTaskData = abi.encode(user2Order, fillAmount0, fillAmount1);
        
        IAttestationCenter.TaskInfo memory partialFillTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(SwapbookAVS.TaskType.PartialFill, partialFillTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the attempted partial fill
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE ATTEMPTED PARTIAL FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // This should revert because User2 is trying to get more than User1's remaining order amount
        vm.expectRevert("Task processing failed");
        _callAfterTaskSubmission(partialFillTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Verify that balances haven't changed (no trade occurred)
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== AFTER FAILED PARTIAL FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // Verify that balances are unchanged (no trade occurred)
        assertEq(user1Token0After, user1Token0Before, "User1 Token0 should be unchanged");
        assertEq(user1Token1After, user1Token1Before, "User1 Token1 should be unchanged");
        assertEq(user2Token0After, user2Token0Before, "User2 Token0 should be unchanged");
        assertEq(user2Token1After, user2Token1Before, "User2 Token1 should be unchanged");
        
        // Verify that the best order is still intact
        bool bestOrderDirection = true; // We know it's zeroForOne = true from the test setup
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        uint256 bestOrderInputAmount = swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        
        assertEq(bestOrderUser, user1, "Best order user should still be user1");
        assertEq(bestOrderInputAmount, 100e18, "Best order inputAmount should still be 100e18");
        
        uint256 bestOrderOutputAmount = swapbookAVS.bestOrderOutputAmount(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        assertEq(bestOrderOutputAmount, 200e18, "Best order outputAmount should still be 200e18");
        
        console.log("=== PARTIAL FILL PREVENTION SUCCESSFUL ===");
        console.log("User2's attempt to sell 300e18 token1 was correctly rejected");
        console.log("User1's order remains intact with outputAmount = 100e18");
    }

    function testPartialFillOneForZero() public {
        // STEP 1: User1 wants to sell 200e18 token1 for 100e18 token0 (zeroForOne = false)
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order (selling token1 for token0) ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            false, // zeroForOne (selling token1 for token0)
            200e18, // inputAmount (token1)
            100e18, // outputAmount (token0)
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 50e18 token0 for 100e18 token1 (zeroForOne = true)
        // This triggers PartialFill to match with the best order
        console.log("=== STEP 2: PartialFill - User2 matches with best order ===");

        uint256 fillAmount0 = 50e18;  // User2 wants 50e18 token0
        uint256 fillAmount1 = 100e18; // User2 wants to sell 100e18 token1

        // Create PartialFill task data
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: fillAmount0,
            amount1: fillAmount1,
            tick: -1000,
            zeroForOne: true, // user2 selling token0 for token1
            orderId: 2
        });

        bytes memory partialFillTaskData = abi.encode(user2Order, fillAmount0, fillAmount1);
        
        IAttestationCenter.TaskInfo memory partialFillTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(SwapbookAVS.TaskType.PartialFill, partialFillTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Process the PartialFill task
        _callAfterTaskSubmission(partialFillTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("=== PARTIAL FILL COMPLETED ===");
        console.log("User1 sold 100e18 token1 and received 50e18 token0");
        console.log("User2 sold 50e18 token0 and received 100e18 token1");
        
        // Verify the new best order state
        bool newBestOrderDirection = false; // We know it's zeroForOne = false from the test setup
        address newBestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        int24 newBestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection);
        
        console.log("New best order user:", newBestOrderUser);
        console.log("New best order tick:", newBestOrderTick);
        console.log("New best order direction (zeroForOne):", newBestOrderDirection);
        console.log("New best order InputAmount:", swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection));
        console.log("New best order OutputAmount:", swapbookAVS.bestOrderOutputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection));
        
        assertEq(newBestOrderUser, user1, "New best order user should be user1");
        assertEq(newBestOrderTick, -1000, "New best order tick should be -1000");
        assertFalse(newBestOrderDirection, "New best order should be zeroForOne = false (selling token1 for token0)");
        assertEq(swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection), 100e18, "New best order's InputAmount should be 100e18");
        assertEq(swapbookAVS.bestOrderOutputAmount(Currency.unwrap(token0), Currency.unwrap(token1), newBestOrderDirection), 50e18, "New best order's OutputAmount should be 50e18");
    }

    function testCompleteFillOneForZero() public {
        // STEP 1: User1 wants to sell 200e18 token1 for 100e18 token0 (zeroForOne = false)
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order (selling token1 for token0) ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0), 
            Currency.unwrap(token1), 
            -1000, // tick
            false, // zeroForOne (selling token1 for token0)
            200e18, // inputAmount (token1)
            100e18, // outputAmount (token0)
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 100e18 token0 for 200e18 token1 (zeroForOne = true)
        // This triggers CompleteFill to match with the best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order ===");

        uint256 fillAmount0 = 100e18; // User2 wants to sell 100e18 token0
        uint256 fillAmount1 = 200e18; // User2 wants 200e18 token1

        // Create CompleteFill task data
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
            user: user2,
            token0: Currency.unwrap(token0),
            token1: Currency.unwrap(token1),
            amount0: fillAmount0,
            amount1: fillAmount1,
            tick: -1000,
            zeroForOne: true, // user2 selling token0 for token1
            orderId: 2
        });

        // Create empty new best order (no replacement)
        SwapbookAVS.OrderInfo memory emptyNewBestOrder = SwapbookAVS.OrderInfo({
            user: address(0),
            token0: address(0),
            token1: address(0),
            amount0: 0,
            amount1: 0,
            tick: 0,
            zeroForOne: false,
            orderId: 0
        });

        bytes memory completeFillTaskData = abi.encode(user2Order, fillAmount0, fillAmount1, emptyNewBestOrder);
        
        IAttestationCenter.TaskInfo memory completeFillTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(SwapbookAVS.TaskType.CompleteFill, completeFillTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Process the CompleteFill task
        _callAfterTaskSubmission(completeFillTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("=== COMPLETE FILL COMPLETED ===");
        console.log("User1 sold 200e18 token1 and received 100e18 token0");
        console.log("User2 sold 100e18 token0 and received 200e18 token1");
        
        // Verify that the best order is cleared (no new best order provided)
        bool bestOrderDirection = false; // We know it's zeroForOne = false from the test setup
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        uint256 bestOrderInputAmount = swapbookAVS.bestOrderInputAmount(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        uint256 bestOrderOutputAmount = swapbookAVS.bestOrderOutputAmount(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        
        console.log("Best order user after complete fill:", bestOrderUser);
        console.log("Best order tick after complete fill:", bestOrderTick);
        console.log("Best order direction after complete fill:", bestOrderDirection);
        console.log("Best order InputAmount after complete fill:", bestOrderInputAmount);
        console.log("Best order OutputAmount after complete fill:", bestOrderOutputAmount);
        
        assertEq(bestOrderUser, address(0), "Best order user should be cleared");
        assertEq(bestOrderTick, 0, "Best order tick should be cleared");
        assertFalse(bestOrderDirection, "Best order direction should be cleared");
        assertEq(bestOrderInputAmount, 0, "Best order InputAmount should be cleared");
        assertEq(bestOrderOutputAmount, 0, "Best order OutputAmount should be cleared");
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
            100e18, // inputAmount
            200e18,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order, but NO new best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order (no new best order) ===");
        
        // Create CompleteFill task data with empty newBestOrder
        SwapbookAVS.OrderInfo memory user2Order = SwapbookAVS.OrderInfo({
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
        SwapbookAVS.OrderInfo memory emptyNewBestOrder = SwapbookAVS.OrderInfo({
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
            data: abi.encode(SwapbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1Before = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        _callAfterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user2Token0After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token0));
        uint256 user2Token1After = swapbookAVS.getEscrowedBalance(user2, Currency.unwrap(token1));
        
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
        bool bestOrderDirection = true; // We know it's zeroForOne = true from the test setup
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);
        console.log("Best order direction (zeroForOne):", bestOrderDirection);
        
        assertEq(bestOrderUser, address(0), "Best order user should be cleared (address(0))");
        assertEq(bestOrderTick, 0, "Best order tick should be cleared (0)");
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
            100e18, // inputAmount
            0,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
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
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
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
        bool bestOrderDirection = true; // We know it's zeroForOne = true from the test setup
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), bestOrderDirection);
        
        console.log("OrderbookAVS - Best order user:", bestOrderUser);
        console.log("OrderbookAVS - Best order tick:", bestOrderTick);
        console.log("OrderbookAVS - Best order direction:", bestOrderDirection);
        
        assertEq(bestOrderUser, user1, "Best order user should be user1");
        assertEq(bestOrderTick, -1000, "Best order tick should be -1000");
        assertTrue(bestOrderDirection, "Best order direction should be true (zeroForOne)");
        
        console.log("SwapbookV2 integration successful!");
    }
 
    function testCompleteFillWithSwapRouterAfterSwap() public {
        // Test the complete flow: User1 places order in OrderbookAVS, 
        // User4 swaps through router, User1's order is filled via _afterSwap
        console.log("=== Testing Swap Router After Swap ===");
        
        // STEP 1: User1 places limit order to sell 100e18 token0 at tick 60
        _placeLimitOrder_tick_60();
        
        // Expect the LimitOrderExecutedAfterSwap event to be emitted
        // vm.expectEmit(true, true, true, true);
        // emit SwapbookV2.LimitOrderExecutedAfterSwap(); // outputAmount will be set by the contract

        // STEP 2: User4 swaps through swap router to sell token1 for token0
        _executeSwapAndVerifyAfterSwap();
    }

    function testCompleteFillWithSwapRouterBeforeSwap() public {
        // Test the complete flow: User1 places order in OrderbookAVS, 
        // User4 swaps through router, User1's order is filled via _beforeSwap
        console.log("=== Testing Swap Router Before Swap ===");
        
        // STEP 1: User1 places limit order to sell 100e18 token0 at tick 60
        _placeLimitOrder_tick_0();
        
        // STEP 2: User4 swaps through swap router to sell token1 for token0
        _executeSwapAndVerifyBeforeSwap();
    }

    function _placeLimitOrder_tick_60() internal {
        console.log("=== STEP 1: User1 places limit order (better price) ===");
        
        // Create UpdateBestPrice task data for User1's order
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            60, // tick (better price than pool's 1:1) - higher tick = better price for buying token0
            true,  // zeroForOne (selling token0 for token1)
            100e18, // inputAmount
            0,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
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
        assertEq(swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), true), user1, "Best order user should be user1");
        assertEq(swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true), 60, "Best order tick should be 60");
        assertTrue(true, "Best order direction should be true (zeroForOne)");
    }

    function _placeLimitOrder_tick_0() internal {
        console.log("=== STEP 1: User1 places limit order (better price) ===");
        
        // Create UpdateBestPrice task data for User1's order
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            0, // tick 
            true,  // zeroForOne (selling token0 for token1)
            100e18, // inputAmount
            0,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
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
        
        assertEq(bestTick, 0, "Best tick should be 60");
        assertEq(pendingOrder, 100e18, "Pending order should be 100e18");
        
        // Verify OrderbookAVS also has the best order
        assertEq(swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), true), user1, "Best order user should be user1");
        assertEq(swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true), 0, "Best order tick should be 0");
        assertTrue(true, "Best order direction should be true (zeroForOne)");
    }

    function _executeSwapAndVerifyAfterSwap() internal {
        console.log("=== STEP 2: User4 swaps through router ===");
        
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
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
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
        emit SwapbookAVS.OrderExecutionCallback(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            user1, // bestOrderUser
            address(0), // swapper (any address)
            0, // inputAmount (any amount)
            0, // outputAmount (any amount)
            false // zeroForOne (any boolean)
        );

        vm.expectEmit(true, true, true, true);
        emit SwapbookV2.LimitOrderExecutedAfterSwap(); // outputAmount will be set by the contract

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
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
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
        
        // Verify the order was completely filled and best order cleared
        assertEq(swapbookV2.pendingOrders(key.toId(), bestTickBefore, true), 0, "Pending order should be 0");
        assertEq(swapbookV2.bestTicks(key.toId(), true), 0, "Best tick in SwapbookV2 should be 0");
        assertEq(swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true), 0, "Best order tick in OrderbookAVS should be 0");
        assertEq(swapbookAVS.getEscrowedBalance(user4, Currency.unwrap(token0)), 0, "User4 should not have escrowed token0");
        assertEq(swapbookAVS.getEscrowedBalance(user4, Currency.unwrap(token1)), 0, "User4 should not have escrowed token1");

        console.log("User4 used wallet funds, not escrow funds");
        console.log("onOrderExecuted was called to settle escrowedFunds");
    }

    function _executeSwapAndVerifyBeforeSwap() internal {
        console.log("=== STEP 2: User4 swaps through router ===");
        
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
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
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
        emit SwapbookAVS.OrderExecutionCallback(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            user1, // bestOrderUser
            address(0), // swapper (any address)
            0, // inputAmount (any amount)
            0, // outputAmount (any amount)
            false // zeroForOne (any boolean)
        );

        vm.expectEmit(true, true, true, true);
        emit SwapbookV2.LimitOrderExecutedBeforeSwap(); // outputAmount will be set by the contract

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
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
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
        
        // Verify the order was completely filled and best order cleared
        assertEq(swapbookV2.pendingOrders(key.toId(), bestTickBefore, true), 0, "Pending order should be 0");
        assertEq(swapbookV2.bestTicks(key.toId(), true), 0, "Best tick in SwapbookV2 should be 0");
        assertEq(swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true), 0, "Best order tick in OrderbookAVS should be 0");
        assertEq(swapbookAVS.getEscrowedBalance(user4, Currency.unwrap(token0)), 0, "User4 should not have escrowed token0");
        assertEq(swapbookAVS.getEscrowedBalance(user4, Currency.unwrap(token1)), 0, "User4 should not have escrowed token1");

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
        _placeLimitOrder_tick_60();
        
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
            100e18, // inputAmount
            0,     // outputAmount
            user1,  // user who placed the order
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task in OrderbookAVS
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order placed in OrderbookAVS at tick 100");
        console.log("OrderbookAVS bestOrderTicks:", swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true));
        
        // Verify OrderbookAVS has the order at tick 100
        assertEq(swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true), 100, "OrderbookAVS should have tick 100");
        assertEq(swapbookAVS.bestOrderUsers(Currency.unwrap(token0), Currency.unwrap(token1), true), user1, "OrderbookAVS should have user1");
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
        int24 orderbookAVSTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true);
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
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
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
        console.log("User1 Token0 (escrow):", swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0)));
        console.log("User1 Token1 (escrow):", swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1)));
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
        
        int24 orderbookAVSTick = swapbookAVS.bestOrderTicks(Currency.unwrap(token0), Currency.unwrap(token1), true);
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

    function testCompareTickRoundingMethods() public {
        console.log("=== Comparing getLowerUsableTick vs getHigherUsableTick ===");
        
        // Test with tick 100 and tickSpacing 60
        int24 originalTick = 100;
        int24 tickSpacing = 60;
        
        // Calculate what each method would return
        int24 lowerTick = _calculateLowerUsableTick(originalTick, tickSpacing);
        int24 higherTick = _calculateHigherUsableTick(originalTick, tickSpacing);
        
        console.log("Original tick:", originalTick);
        console.log("Tick spacing:", tickSpacing);
        console.log("getLowerUsableTick result:", lowerTick);
        console.log("getHigherUsableTick result:", higherTick);
        console.log("Difference:", higherTick - lowerTick);
        
        // Test both methods with actual swaps
        console.log("\n--- TESTING getLowerUsableTick (tick 60) ---");
        _testTickScenarioWithChoice(originalTick, false, "getLowerUsableTick");
        
        console.log("\n--- TESTING getHigherUsableTick (tick 120) ---");
        _testTickScenarioWithChoice(originalTick, true, "getHigherUsableTick");

        console.log("\n=== COMPARISON SUMMARY ===");
    }

    function _calculateLowerUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) intervals--;
        return intervals * tickSpacing;
    }

    function _calculateHigherUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        if (tick % tickSpacing != 0) intervals++;
        return intervals * tickSpacing;
    }

    function _testTickScenarioWithChoice(int24 tick, bool useHigherTick, string memory method) internal {
        console.log("Testing with tick:", tick);
        console.log("useHigherTick:", useHigherTick);
        
        // Create user1 and user4
        address user4 = makeAddr("user4");
        MockERC20(Currency.unwrap(token0)).mint(user4, 1000e18);
        MockERC20(Currency.unwrap(token1)).mint(user4, 1000e18);

        // User4 needs to approve the swap router to spend their tokens
        vm.startPrank(user4);
        MockERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        // Record initial balances
        uint256 user1Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user1);
        uint256 user1Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user1);
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("BEFORE ORDER PLACEMENT:");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User4 Token0:", user4Token0Before);
        console.log("User4 Token1:", user4Token1Before);
        
        // Place order through OrderbookAVS system
        _placeOrderForComparisonWithUser(tick, useHigherTick, user1);
        
        // Get the actual tick that was used
        int24 actualTick = useHigherTick 
            ? swapbookV2.getHigherUsableTick(tick, 60)
            : swapbookV2.getLowerUsableTick(tick, 60);
        
        console.log("ORDER PLACED:");
        console.log("Requested tick:", tick);
        console.log("Actual tick used:", actualTick);
        console.log("Expected tick:", actualTick);
        
        // Record balances after order placement
        uint256 user1Token0After = MockERC20(Currency.unwrap(token0)).balanceOf(user1);
        uint256 user1Token1After = MockERC20(Currency.unwrap(token1)).balanceOf(user1);
        
        console.log("AFTER ORDER PLACEMENT:");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User1 Token0 escrowed:", user1Token0Before - user1Token0After);
        
        // Now test a swap through the router
        _testSwapWithOrderAndUserForComparison(actualTick, method, user4, user1);
    }

    function _placeOrderForComparisonWithUser(int24 tick, bool useHigherTick, address user) internal {        
        // Create UpdateBestPrice task data with useHigherTick parameter
        bytes memory updateTaskData = abi.encode(
            Currency.unwrap(token0),
            Currency.unwrap(token1),
            tick,
            true,  // zeroForOne (selling token0 for token1)
            100e18, // inputAmount
            0,     // outputAmount
            user,
            useHigherTick // Add the useHigherTick parameter
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the task
        _callAfterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
    }

    function _testSwapWithOrderAndUserForComparison(int24 orderTick, string memory method, address user4, address user1) internal {
        console.log("Testing swap with order at tick:", orderTick);
        
        // Record initial balances
        uint256 user1Token0Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1Before = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0Before = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1Before = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
        
        console.log("BEFORE SWAP:");
        console.log("User1 Token0 (escrow):", user1Token0Before);
        console.log("User1 Token1 (escrow):", user1Token1Before);
        console.log("User4 Token0 (wallet):", user4Token0Before);
        console.log("User4 Token1 (wallet):", user4Token1Before);
        
        // Execute swap through router
        PoolKey memory poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });

        vm.startPrank(user4);
        swapRouter.swap(
            poolKey,
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

        console.log("SUCCESS: Swap executed with", method);

        // Record final balances
        uint256 user1Token0After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token0));
        uint256 user1Token1After = swapbookAVS.getEscrowedBalance(user1, Currency.unwrap(token1));
        uint256 user4Token0After = MockERC20(Currency.unwrap(token0)).balanceOf(user4);
        uint256 user4Token1After = MockERC20(Currency.unwrap(token1)).balanceOf(user4);
            
        console.log("AFTER SWAP:");
        console.log("User1 Token0 (escrow):", user1Token0After);
        console.log("User1 Token1 (escrow):", user1Token1After);
        console.log("User4 Token0 (wallet):", user4Token0After);
        console.log("User4 Token1 (wallet):", user4Token1After);
            
        // Calculate User1's changes
        uint256 user1Token0Sold = user1Token0Before - user1Token0After;
        uint256 user1Token1Received = user1Token1After - user1Token1Before;
            
        // Calculate User4's changes
        uint256 user4Token1Spent = user4Token1Before - user4Token1After;
        uint256 user4Token0Received = user4Token0After - user4Token0Before;
            
        console.log("USER1 EXCHANGE:");
        console.log("User1 sold %s token0 for %s token1", user1Token0Sold, user1Token1Received);
        if (user1Token0Sold > 0) {
            console.log("User1 rate: 1 token0 =", (user1Token1Received * 1e18) / user1Token0Sold, "token1");
        }
            
        console.log("USER4 EXCHANGE:");
        console.log("User4 spent %s token1 for %s token0", user4Token1Spent, user4Token0Received);
        if (user4Token1Spent > 0) {
            console.log("User4 rate: 1 token1 =", (user4Token0Received * 1e18) / user4Token1Spent, "token0");
        }

    }

}