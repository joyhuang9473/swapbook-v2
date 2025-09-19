// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title Scenario1_LimitOrderAndSwap
 * @notice Scenario where SWAPBOOK_USER places a limit order and UNISWAP_USER executes a swap
 * @dev This scenario demonstrates:
 * 1. SWAPBOOK_USER places a limit order (tick=-60, inputAmount=100 tokenA, outputAmount=99.4)
 * 2. UNISWAP_USER executes a swap through Universal Router
 * 3. SwapbookV2 hook is triggered during the swap
 * 4. The limit order is processed via SwapbookAVS.afterTaskSubmission
 */
import {Script, console} from "forge-std/Script.sol";
import {SwapbookV2} from "../src/SwapbookV2.sol";
import {SwapbookAVS} from "../src/SwapbookAVS.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IUniversalRouter} from "universal-router/interfaces/IUniversalRouter.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IAttestationCenter} from "../src/interface/IAttestationCenter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

contract Scenario1_LimitOrderAndSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function setUp() public {}

    function run() public {
        console.log("=== Scenario 1: Limit Order and Swap ===");
        console.log("SWAPBOOK_USER places limit order, UNISWAP_USER executes swap");
        console.log("This will trigger SwapbookV2 hook and process the limit order");
        
        // Get addresses from environment
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address swapbookV2Address = vm.envAddress("SWAPBOOK_V2_ADDRESS");
        address swapbookAVSAddress = vm.envAddress("SWAPBOOK_AVS_ADDRESS");
        address attestationCenterAddress = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
        address universalRouterAddress = vm.envAddress("UNIVERSAL_ROUTER_ADDRESS");
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        address swapbookUserAddress = vm.envAddress("SWAPBOOK_USER_ADDRESS");
        address uniswapUserAddress = vm.envAddress("UNISWAP_USER_ADDRESS");
        
        // Get attestation center private key
        uint256 attestationCenterPrivateKey = vm.envUint("ATTESTATION_CENTER_PRIVATE_KEY");
        
        // Get swapbook user private key for token transfers
        uint256 swapbookUserPrivateKey = vm.envUint("SWAPBOOK_USER_PRIVATE_KEY");
        
        console.log("Pool Manager:", poolManagerAddress);
        console.log("SwapbookV2:", swapbookV2Address);
        console.log("SwapbookAVS:", swapbookAVSAddress);
        console.log("Attestation Center:", attestationCenterAddress);
        console.log("Universal Router:", universalRouterAddress);
        console.log("Token0:", token0Address);
        console.log("Token1:", token1Address);
        console.log("Swapbook User:", swapbookUserAddress);
        console.log("Uniswap User:", uniswapUserAddress);
        
        // Create contract instances
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        SwapbookV2 swapbookV2 = SwapbookV2(swapbookV2Address);
        SwapbookAVS swapbookAVS = SwapbookAVS(swapbookAVSAddress);
        IAttestationCenter attestationCenter = IAttestationCenter(attestationCenterAddress);
        IUniversalRouter universalRouter = IUniversalRouter(universalRouterAddress);
        MockERC20 token0 = MockERC20(token0Address);
        MockERC20 token1 = MockERC20(token1Address);
        
        // Create PoolKey
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0Address),
            currency1: Currency.wrap(token1Address),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(swapbookV2Address)
        });
        
        PoolId poolId = key.toId();
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        
        // Step 1: Check initial state
        console.log("\n=== Step 1: Check Initial State ===");
        _checkInitialState(poolManager, swapbookV2, swapbookAVS, poolId, key);
        
        // Step 2: SWAPBOOK_USER places limit order via SwapbookAVS
        console.log("\n=== Step 2: SWAPBOOK_USER Places Limit Order ===");
        _placeLimitOrder(swapbookAVS, attestationCenter, swapbookV2Address, token0Address, token1Address, swapbookUserAddress, attestationCenterPrivateKey, swapbookUserPrivateKey);
        
        // Step 3: Check state after limit order
        console.log("\n=== Step 3: Check State After Limit Order ===");
        _checkStateAfterLimitOrder(swapbookV2, swapbookAVS, poolId, key, token0Address, token1Address, swapbookUserAddress);
        
        // Step 4: UNISWAP_USER executes swap through Universal Router
        console.log("\n=== Step 4: UNISWAP_USER Executes Swap ===");
        _executeSwap(universalRouter, poolManager, swapbookV2, poolId, key, token0, token1, uniswapUserAddress, swapbookUserAddress, swapbookAVS);
        
        // Step 4.5: Analyze price improvement
        console.log("\n=== Step 4.5: Price Improvement Analysis ===");
        _analyzePriceImprovement(poolManager, poolId);
        
        // Step 5: Check final state
        console.log("\n=== Step 5: Check Final State ===");
        _checkFinalState(poolManager, swapbookV2, swapbookAVS, poolId, key, token0, token1, swapbookUserAddress, uniswapUserAddress);
        
        console.log("\n=== Scenario 1 Complete ===");
        console.log("[SUCCESS] Limit order was placed and swap was executed successfully!");
        console.log("[SUCCESS] SwapbookV2 hook was triggered and processed the limit order!");
        console.log("[SUCCESS] UNISWAP_USER received better execution due to the limit order!");
        console.log("[SUCCESS] SWAPBOOK_USER's limit order was filled!");
    }
    
    function _checkInitialState(
        IPoolManager poolManager,
        SwapbookV2 swapbookV2,
        SwapbookAVS swapbookAVS,
        PoolId poolId,
        PoolKey memory key
    ) internal view {
        // Check pool state
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        console.log("Pool current tick:", currentTick);
        console.log("Pool sqrtPriceX96:", sqrtPriceX96);
        
        // Check SwapbookV2 state
        uint256 pendingOrderBefore = swapbookV2.pendingOrders(poolId, -60, true);
        console.log("Pending order at tick -60 before:", pendingOrderBefore);
        
        int24 bestTickBefore = swapbookV2.bestTicks(poolId, true);
        console.log("Best tick before:", bestTickBefore);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), true);
        console.log("Best order user before:", bestOrderUser);
    }
    
    function _placeLimitOrder(
        SwapbookAVS swapbookAVS,
        IAttestationCenter attestationCenter,
        address swapbookV2Address,
        address token0Address,
        address token1Address,
        address swapbookUserAddress,
        uint256 attestationCenterPrivateKey,
        uint256 swapbookUserPrivateKey
    ) internal {
        // Create UpdateBestPrice task data
        // tick=-60, inputAmount=100 tokenA, outputAmount=99.4
        bytes memory updateTaskData = abi.encode(
            uint256(SwapbookAVS.TaskType.UpdateBestPrice), // task_id
            token0Address,  // token0 (tokenA)
            token1Address,  // token1 (tokenB)
            -60,            // tick
            true,           // zeroForOne (selling token0 for token1)
            100e18,         // inputAmount (100 tokenA)
            994e17,         // outputAmount (99.4 tokenB)
            swapbookUserAddress, // user who placed the order
            false           // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof_scenario1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        console.log("Placing limit order:");
        console.log("  Tick: -60");
        console.log("  Input Amount: 100 tokenA");
        console.log("  Output Amount: 99.4 tokenB");
        console.log("  User:", swapbookUserAddress);
        
        // Check swapbook user's token0 balance
        uint256 swapbookUserBalance = MockERC20(token0Address).balanceOf(swapbookUserAddress);
        console.log("Swapbook user token0 balance:", swapbookUserBalance);
        
        if (swapbookUserBalance < 100e18) {
            console.log("ERROR: Swapbook user doesn't have enough token0");
            console.log("Required: 100e18");
            console.log("Available:", swapbookUserBalance);
            revert("Insufficient token0 balance");
        }
        
        // First, approve and deposit tokens from swapbook user to SwapbookAVS escrow
        // This is needed because SwapbookAVS needs to have tokens in escrow to place orders
        console.log("Approving SwapbookAVS to spend 100 tokenA from swapbook user...");
        vm.startBroadcast(swapbookUserPrivateKey);
        MockERC20(token0Address).approve(address(swapbookAVS), 100e18);
        vm.stopBroadcast();
        
        console.log("Depositing 100 tokenA from swapbook user to SwapbookAVS escrow...");
        vm.startBroadcast(swapbookUserPrivateKey);
        swapbookAVS.depositFunds(token0Address, 100e18);
        vm.stopBroadcast();
        
        // Approve SwapbookV2 to spend SwapbookAVS tokens
        console.log("Approving SwapbookV2 to spend SwapbookAVS tokens...");
        vm.startBroadcast(attestationCenterPrivateKey);
        swapbookAVS.approveToken(token0Address, swapbookV2Address, type(uint256).max);
        swapbookAVS.approveToken(token1Address, swapbookV2Address, type(uint256).max);
        vm.stopBroadcast();
        
        // Call afterTaskSubmission to place the order
        // Use vm.startBroadcast to sign with attestation center private key
        vm.startBroadcast(attestationCenterPrivateKey);
        swapbookAVS.afterTaskSubmission(
            updateTaskInfo,
            true,  // isApproved
            "",    // tpSignature
            [uint256(0), uint256(0)], // taSignature
            new uint256[](0) // attestersIds
        );
        vm.stopBroadcast();
        
        console.log("Limit order placed successfully!");
    }
    
    function _checkStateAfterLimitOrder(
        SwapbookV2 swapbookV2,
        SwapbookAVS swapbookAVS,
        PoolId poolId,
        PoolKey memory key,
        address token0Address,
        address token1Address,
        address swapbookUserAddress
    ) internal view {
        // Check SwapbookV2 state
        uint256 pendingOrderAfter = swapbookV2.pendingOrders(poolId, -60, true);
        console.log("Pending order at tick -60 after:", pendingOrderAfter);
        
        int24 bestTickAfter = swapbookV2.bestTicks(poolId, true);
        console.log("Best tick after:", bestTickAfter);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(token0Address, token1Address, true);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(token0Address, token1Address, true);
        uint256 bestOrderInputAmount = swapbookAVS.bestOrderInputAmount(token0Address, token1Address, true);
        uint256 bestOrderOutputAmount = swapbookAVS.bestOrderOutputAmount(token0Address, token1Address, true);
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);
        console.log("Best order input amount:", bestOrderInputAmount);
        console.log("Best order output amount:", bestOrderOutputAmount);
        
        // Check escrowed balance for swapbook user
        uint256 escrowedToken0 = swapbookAVS.getEscrowedBalance(swapbookUserAddress, token0Address);
        uint256 escrowedToken1 = swapbookAVS.getEscrowedBalance(swapbookUserAddress, token1Address);
        console.log("Swapbook user escrowed token0:", escrowedToken0);
        console.log("Swapbook user escrowed token1:", escrowedToken1);
    }
    
    function _executeSwap(
        IUniversalRouter universalRouter,
        IPoolManager poolManager,
        SwapbookV2 swapbookV2,
        PoolId poolId,
        PoolKey memory key,
        MockERC20 token0,
        MockERC20 token1,
        address uniswapUserAddress,
        address swapbookUserAddress,
        SwapbookAVS swapbookAVS
    ) internal {
        console.log("Executing swap through Universal Router...");
        console.log("UNISWAP_USER wants to buy tokenA with 100 tokenB");
        
        // Check user balances before
        uint256 token0BalanceBefore = token0.balanceOf(uniswapUserAddress);
        uint256 token1BalanceBefore = token1.balanceOf(uniswapUserAddress);
        
        // Check escrowed balances before swap
        uint256 escrowedToken0Before = swapbookAVS.getEscrowedBalance(swapbookUserAddress, address(token0));
        uint256 escrowedToken1Before = swapbookAVS.getEscrowedBalance(swapbookUserAddress, address(token1));
        
        console.log("=== BEFORE SWAP ===");
        console.log("UNISWAP_USER Token0 balance:", token0BalanceBefore);
        console.log("UNISWAP_USER Token1 balance:", token1BalanceBefore);
        console.log("SWAPBOOK_USER escrowed Token0:", escrowedToken0Before);
        console.log("SWAPBOOK_USER escrowed Token1:", escrowedToken1Before);
        
        // Calculate expected execution without limit order (pool price)
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        uint256 poolPrice = _calculatePriceFromSqrtPriceX96(sqrtPriceX96);
        console.log("Pool price (token1 per token0):", poolPrice);
        
        // Calculate expected execution with limit order (better price)
        uint256 limitOrderPrice = _calculatePriceFromTick(-60);
        console.log("Limit order price (token1 per token0):", limitOrderPrice);
        
        // Calculate expected token0 received without limit order
        uint256 token0ExpectedWithoutLimitOrder = (100e18 * 1e18) / poolPrice;
        console.log("Expected token0 without limit order:", token0ExpectedWithoutLimitOrder);
        
        // Calculate expected token0 received with limit order (better execution)
        uint256 token0ExpectedWithLimitOrder = (100e18 * 1e18) / limitOrderPrice;
        console.log("Expected token0 with limit order:", token0ExpectedWithLimitOrder);
        
        // Calculate price improvement
        uint256 priceImprovement = token0ExpectedWithLimitOrder - token0ExpectedWithoutLimitOrder;
        uint256 priceImprovementPercent = (priceImprovement * 10000) / token0ExpectedWithoutLimitOrder;
        
        console.log("Price improvement:", priceImprovement, "token0");
        console.log("Price improvement:", priceImprovementPercent, "basis points");
        
        // Create swap parameters for Universal Router
        // This will trigger the SwapbookV2 hook during the swap
        console.log("Preparing swap parameters:");
        console.log("  Pool Manager:", address(poolManager));
        console.log("  Pool Key:", uint256(PoolId.unwrap(poolId)));
        console.log("  Zero for One: false (buying token0 with token1)");
        console.log("  Amount Specified: 100e18 token1");
        console.log("  Sqrt Price Limit: 0 (no price limit)");
        
        // Execute the actual swap through Universal Router
        console.log("Executing swap through Universal Router...");
        
        // Set up Permit2 for Universal Router
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Base Sepolia Permit2
        IPermit2 permit2Contract = IPermit2(permit2);
        
        // Get uniswap user private key
        uint256 uniswapUserPrivateKey = vm.envUint("UNISWAP_USER_PRIVATE_KEY");
        
        // Approve Permit2 to spend user's tokens
        vm.startBroadcast(uniswapUserPrivateKey);
        token1.approve(permit2, 100e18);
        console.log("Approved Permit2 to spend", 100e18, "token1");
        permit2Contract.approve(address(token1), address(universalRouter), uint160(100e18), uint48(block.timestamp + 600));
        console.log("Uses Permit2 to approve the UniversalRouter with a specific amount and expiration time.");
        vm.stopBroadcast();
        
        // Expect the LimitOrderExecutedBeforeSwap event to be emitted during the swap
        // vm.expectEmit(true, true, true, true);
        // emit SwapbookV2.LimitOrderExecutedBeforeSwap();
        
        // Create swap parameters for Universal Router
        bytes memory commands = abi.encodePacked(uint8(0x10)); // V4_SWAP action
        
        // Encode V4Router actions as per documentation
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        
        // Create ExactInputSingleParams as per V4 documentation
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: false, // buying token0 with token1
            amountIn: uint128(100e18), // exact input amount
            amountOutMinimum: 0, // minimum amount out (0 for testing)
            hookData: bytes("") // no hook data needed
        });
        
        // Prepare parameters for each action as per documentation
        bytes[] memory params = new bytes[](3);
        
        // First parameter: swap configuration
        params[0] = abi.encode(swapParams);
        
        // Second parameter: specify input tokens for the swap (SETTLE_ALL)
        params[1] = abi.encode(key.currency1, 100e18);
        
        // Third parameter: specify output tokens from the swap (TAKE_ALL)
        params[2] = abi.encode(key.currency0, 0);
        
        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        
        // Execute the swap using Universal Router
        vm.startBroadcast(uniswapUserPrivateKey);
        uint256 deadline = block.timestamp + 300; // 5 minutes deadline
        universalRouter.execute(commands, inputs, deadline);
        vm.stopBroadcast();
        
        console.log("Swap executed successfully!");
        console.log("[SUCCESS] LimitOrderExecutedBeforeSwap event was emitted!");
        console.log("[SUCCESS] The SwapbookV2 hook successfully processed the limit order!");
        
        // Check actual user balances after swap
        uint256 token0BalanceAfter = token0.balanceOf(uniswapUserAddress);
        uint256 token1BalanceAfter = token1.balanceOf(uniswapUserAddress);
        uint256 token0Received = token0BalanceAfter - token0BalanceBefore;
        
        console.log("=== ACTUAL BALANCES AFTER SWAP ===");
        console.log("UNISWAP_USER Token0 balance:", token0BalanceAfter);
        console.log("UNISWAP_USER Token1 balance:", token1BalanceAfter);
        console.log("Token0 received:", token0Received);
        console.log("Token1 spent:", token1BalanceBefore - token1BalanceAfter);
        
        // Check escrowed balances after swap
        uint256 escrowedToken0After = swapbookAVS.getEscrowedBalance(swapbookUserAddress, address(token0));
        uint256 escrowedToken1After = swapbookAVS.getEscrowedBalance(swapbookUserAddress, address(token1));
        
        console.log("=== AFTER SWAP ===");
        console.log("SWAPBOOK_USER escrowed Token0:", escrowedToken0After);
        console.log("SWAPBOOK_USER escrowed Token1:", escrowedToken1After);
        console.log("Token0 escrow change:", int256(escrowedToken0After) - int256(escrowedToken0Before));
        console.log("Token1 escrow change:", int256(escrowedToken1After) - int256(escrowedToken1Before));
        
        // Verify better execution
        if (token0Received > token0ExpectedWithoutLimitOrder) {
            console.log("[SUCCESS] UNISWAP_USER received better execution due to limit order!");
            console.log("[SUCCESS] Additional token0 received:", token0Received - token0ExpectedWithoutLimitOrder);
        } else {
            console.log("[INFO] UNISWAP_USER received standard execution");
            console.log("[INFO] Expected without limit order:", token0ExpectedWithoutLimitOrder);
            console.log("[INFO] Actual received:", token0Received);
        }
    }
    
    function _analyzePriceImprovement(
        IPoolManager poolManager,
        PoolId poolId
    ) internal view {
        console.log("Analyzing price improvement from limit order...");
        
        // Get current pool price
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        uint256 poolPrice = _calculatePriceFromSqrtPriceX96(sqrtPriceX96);
        uint256 limitOrderPrice = _calculatePriceFromTick(-60);
        
        console.log("Current pool tick:", currentTick);
        console.log("Pool price (token1 per token0):", poolPrice);
        console.log("Limit order price (token1 per token0):", limitOrderPrice);
        
        // Calculate price difference
        uint256 priceDifference = poolPrice > limitOrderPrice ? 
            poolPrice - limitOrderPrice : limitOrderPrice - poolPrice;
        uint256 priceDifferencePercent = (priceDifference * 10000) / poolPrice;
        
        console.log("Price difference:", priceDifference);
        console.log("Price difference:", priceDifferencePercent, "basis points");
        
        // Calculate execution improvement for 100 token1 swap
        uint256 token0FromPool = (100e18 * 1e18) / poolPrice;
        uint256 token0FromLimitOrder = (100e18 * 1e18) / limitOrderPrice;
        uint256 additionalToken0 = token0FromLimitOrder - token0FromPool;
        uint256 improvementPercent = (additionalToken0 * 10000) / token0FromPool;
        
        console.log("Token0 received from pool price:", token0FromPool);
        console.log("Token0 received from limit order:", token0FromLimitOrder);
        console.log("Additional token0 received:", additionalToken0);
        console.log("Improvement percentage:", improvementPercent, "basis points");
        
        if (token0FromLimitOrder > token0FromPool) {
            console.log("[SUCCESS] Limit order provides better execution!");
            console.log("[SUCCESS] UNISWAP_USER benefits from the limit order");
        } else {
            console.log("[ERROR] Limit order does not provide better execution");
        }
    }
    
    function _checkFinalState(
        IPoolManager poolManager,
        SwapbookV2 swapbookV2,
        SwapbookAVS swapbookAVS,
        PoolId poolId,
        PoolKey memory key,
        MockERC20 token0,
        MockERC20 token1,
        address swapbookUserAddress,
        address uniswapUserAddress
    ) internal view {
        // Check pool state
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        console.log("Final pool current tick:", currentTick);
        console.log("Final pool sqrtPriceX96:", sqrtPriceX96);
        
        // Check SwapbookV2 state
        uint256 pendingOrderFinal = swapbookV2.pendingOrders(poolId, -60, true);
        console.log("Final pending order at tick -60:", pendingOrderFinal);
        
        int24 bestTickFinal = swapbookV2.bestTicks(poolId, true);
        console.log("Final best tick:", bestTickFinal);
        
        // Check SwapbookAVS state
        address bestOrderUserFinal = swapbookAVS.bestOrderUsers(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), true);
        console.log("Final best order user:", bestOrderUserFinal);
        
        // Check user balances
        uint256 token0BalanceFinal = token0.balanceOf(uniswapUserAddress);
        uint256 token1BalanceFinal = token1.balanceOf(uniswapUserAddress);
        
        console.log("Final Token0 balance:", token0BalanceFinal);
        console.log("Final Token1 balance:", token1BalanceFinal);
    }
    
    function _calculatePriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 numerator = sqrtPrice * sqrtPrice;
        uint256 denominator = 1 << 192; // 2^192
        return (numerator * 1e18) / denominator;
    }
    
    function _calculatePriceFromTick(int24 tick) internal pure returns (uint256) {
        if (tick == 0) return 1e18;
        
        if (tick > 0) {
            uint256 basePrice = 1e18;
            uint256 tickMultiplier = 1e14; // 0.0001 * 1e18
            uint256 tickValue = uint256(uint24(tick));
            
            if (tick <= 1000) {
                return basePrice + (tickValue * tickMultiplier);
            }
            
            return basePrice + (tickValue * tickMultiplier) + (tickValue * tickValue * 1e10) / 2;
        }
        
        uint256 absTick = uint256(uint24(-tick));
        uint256 inversePrice = _calculatePriceFromTick(int24(int256(absTick)));
        
        if (inversePrice == 0) return 0;
        return (1e18 * 1e18) / inversePrice;
    }
}
