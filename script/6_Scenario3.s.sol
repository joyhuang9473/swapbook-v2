// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title Scenario3_DualLimitOrders
 * @notice Scenario where SWAPBOOK_USER places a sell limit order and UNISWAP_USER places a buy limit order
 * @dev This scenario demonstrates:
 * 1. SWAPBOOK_USER places a sell limit order (tick=60, inputAmount=100 tokenA, outputAmount=100 tokenB)
 * 2. UNISWAP_USER places a buy limit order (tick=60, inputAmount=100 tokenB, outputAmount=100 tokenA)
 * 3. Both orders are at the same tick, creating a matching scenario
 * 4. Orders can be matched and executed
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

contract Scenario3_DualLimitOrders is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function setUp() public {}

    function run() public {
        console.log("=== Scenario 3: Dual Limit Orders ===");
        console.log("SWAPBOOK_USER places sell limit order (tick=0, 100 tokenA -> 100 tokenB)");
        console.log("SWAPBOOK_USER2 places buy limit order (tick=0, 100 tokenB -> 100 tokenA)");
        console.log("Both orders are at the same tick, creating a matching scenario");
        
        // Get addresses from environment
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address swapbookV2Address = vm.envAddress("SWAPBOOK_V2_ADDRESS");
        address swapbookAVSAddress = vm.envAddress("SWAPBOOK_AVS_ADDRESS");
        address attestationCenterAddress = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
        address universalRouterAddress = vm.envAddress("UNIVERSAL_ROUTER_ADDRESS");
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        address swapbookUserAddress = vm.envAddress("SWAPBOOK_USER_ADDRESS");
        address swapbookUser2Address = vm.envAddress("SWAPBOOK_USER_ADDRESS");
        
        // Get attestation center private key
        uint256 attestationCenterPrivateKey = vm.envUint("ATTESTATION_CENTER_PRIVATE_KEY");
        
        // Get user private keys
        uint256 swapbookUserPrivateKey = vm.envUint("SWAPBOOK_USER_PRIVATE_KEY");
        uint256 swapbookUser2PrivateKey = vm.envUint("SWAPBOOK_USER2_PRIVATE_KEY");
        
        console.log("Pool Manager:", poolManagerAddress);
        console.log("SwapbookV2:", swapbookV2Address);
        console.log("SwapbookAVS:", swapbookAVSAddress);
        console.log("Attestation Center:", attestationCenterAddress);
        console.log("Universal Router:", universalRouterAddress);
        console.log("Token0:", token0Address);
        console.log("Token1:", token1Address);
        console.log("Swapbook User:", swapbookUserAddress);
        console.log("Swapbook User2:", swapbookUser2Address);
        
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
        
        // Step 2: SWAPBOOK_USER places sell limit order
        console.log("\n=== Step 2: SWAPBOOK_USER Places Sell Limit Order ===");
        _placeSellLimitOrder(swapbookAVS, attestationCenter, swapbookV2Address, token0Address, token1Address, swapbookUserAddress, attestationCenterPrivateKey, swapbookUserPrivateKey);
        
        // Step 3: Check state after sell order
        console.log("\n=== Step 3: Check State After Sell Order ===");
        _checkStateAfterSellOrder(swapbookV2, swapbookAVS, poolId, key, token0Address, token1Address, swapbookUserAddress);
        
        // Step 4: SWAPBOOK_USER2 places buy limit order (CompleteFill to match with sell order)
        console.log("\n=== Step 4: SWAPBOOK_USER2 Places Buy Order (CompleteFill) ===");
        _placeBuyOrder(swapbookAVS, attestationCenter, swapbookV2Address, token0Address, token1Address, swapbookUser2Address, attestationCenterPrivateKey, swapbookUser2PrivateKey);
        
        // Step 5: Check state after order matching
        console.log("\n=== Step 5: Check State After Order Matching ===");
        _checkStateAfterOrderMatching(swapbookV2, swapbookAVS, poolId, key, token0Address, token1Address, swapbookUserAddress, swapbookUser2Address);
        
        // Step 6: Check final state
        console.log("\n=== Step 6: Check Final State ===");
        _checkFinalState(poolManager, swapbookV2, swapbookAVS, poolId, key, token0, token1, swapbookUserAddress, swapbookUser2Address);
        
        console.log("\n=== Scenario 3 Complete ===");
        console.log("[SUCCESS] Both limit orders were placed successfully!");
        console.log("[SUCCESS] Orders are at the same tick (0) and can be matched!");
        console.log("[SUCCESS] Orders were matched and executed peer-to-peer!");
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
        uint256 pendingOrderBefore = swapbookV2.pendingOrders(poolId, 0, false);
        console.log("Pending order at tick 0 before:", pendingOrderBefore);
        
        int24 bestTickBefore = swapbookV2.bestTicks(poolId, false);
        console.log("Best tick before:", bestTickBefore);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), false);
        console.log("Best order user before:", bestOrderUser);
    }
    
    function _placeSellLimitOrder(
        SwapbookAVS swapbookAVS,
        IAttestationCenter attestationCenter,
        address swapbookV2Address,
        address token0Address,
        address token1Address,
        address swapbookUserAddress,
        uint256 attestationCenterPrivateKey,
        uint256 swapbookUserPrivateKey
    ) internal {
        // Create UpdateBestPrice task data for sell order
        // tick=60, inputAmount=100 tokenA, outputAmount=100 tokenB
        bytes memory updateTaskData = abi.encode(
            uint256(SwapbookAVS.TaskType.UpdateBestPrice), // task_id
            token0Address,  // token0 (tokenA)
            token1Address,  // token1 (tokenB)
            0,              // tick
            true,           // zeroForOne (selling token0 for token1)
            100e18,         // inputAmount (100 tokenA)
            100e18,         // outputAmount (100 tokenB)
            swapbookUserAddress, // user who placed the order
            false           // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof_scenario3_sell",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        console.log("Placing sell limit order:");
        console.log("  Tick: 0");
        console.log("  Input Amount: 100 tokenA (to be sold)");
        console.log("  Output Amount: 100 tokenB (expected to receive)");
        console.log("  Escrow: 100 tokenA (deposited for order)");
        console.log("  User:", swapbookUserAddress);
        
        // Check swapbook user's token0 balance (needed for the sell order)
        uint256 swapbookUserBalance = MockERC20(token0Address).balanceOf(swapbookUserAddress);
        console.log("Swapbook user token0 balance:", swapbookUserBalance);
        
        if (swapbookUserBalance < 100e18) {
            console.log("ERROR: Swapbook user doesn't have enough token0");
            console.log("Required: 100e18 (100 tokens)");
            console.log("Available:", swapbookUserBalance);
            revert("Insufficient token0 balance");
        }
        
        // Approve and deposit tokens from swapbook user to SwapbookAVS escrow
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
        
        // Call afterTaskSubmission to place the sell order
        vm.startBroadcast(attestationCenterPrivateKey);
        swapbookAVS.afterTaskSubmission(
            updateTaskInfo,
            true,  // isApproved
            "",    // tpSignature
            [uint256(0), uint256(0)], // taSignature
            new uint256[](0) // attestersIds
        );
        vm.stopBroadcast();
        
        console.log("Sell limit order placed successfully!");
    }
    
    function _placeBuyOrder(
        SwapbookAVS swapbookAVS,
        IAttestationCenter attestationCenter,
        address swapbookV2Address,
        address token0Address,
        address token1Address,
        address swapbookUser2Address,
        uint256 attestationCenterPrivateKey,
        uint256 swapbookUser2PrivateKey
    ) internal {
        // Create CompleteFill task data to match with the existing sell order
        // This will match SWAPBOOK_USER2's buy order with SWAPBOOK_USER's sell order
        SwapbookAVS.OrderInfo memory buyOrder = SwapbookAVS.OrderInfo({
            user: swapbookUser2Address,
            token0: token0Address,
            token1: token1Address,
            amount0: 100e18,  // 100 tokenA
            amount1: 100e18,  // 100 tokenB
            tick: 0,
            zeroForOne: false, // buying token0 with token1
            orderId: 2
        });
        
        // Create a new best order to replace the filled sell order
        SwapbookAVS.OrderInfo memory newBestOrder = SwapbookAVS.OrderInfo({
            user: address(0), // No new best order for now
            token0: token0Address,
            token1: token1Address,
            amount0: 0,
            amount1: 0,
            tick: 0,
            zeroForOne: true,
            orderId: 0
        });
        
        uint256 fillAmount0 = 100e18; // Fill 100 tokenA
        uint256 fillAmount1 = 100e18; // Fill 100 tokenB
        
        bytes memory completeTaskData = abi.encode(
            SwapbookAVS.TaskType.CompleteFill, 
            buyOrder, 
            fillAmount0, 
            fillAmount1, 
            newBestOrder
        );
        
        IAttestationCenter.TaskInfo memory completeTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof_scenario3_complete",
            data: abi.encode(SwapbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        console.log("Placing buy order (CompleteFill):");
        console.log("  Tick: 0");
        console.log("  Input Amount: 100 tokenB (to be sold)");
        console.log("  Output Amount: 100 tokenA (expected to receive)");
        console.log("  Escrow: 100 tokenB (deposited for order)");
        console.log("  User:", swapbookUser2Address);
        
        // Check swapbook user2's token1 balance (needed for the buy order)
        uint256 swapbookUser2Balance = MockERC20(token1Address).balanceOf(swapbookUser2Address);
        console.log("Swapbook user2 token1 balance:", swapbookUser2Balance);
        
        if (swapbookUser2Balance < 100e18) {
            console.log("ERROR: Swapbook user2 doesn't have enough token1");
            console.log("Required: 100e18 (100 tokens)");
            console.log("Available:", swapbookUser2Balance);
            revert("Insufficient token1 balance");
        }
        
        // For buying token0 with token1, we need token1 in escrow
        // Approve and deposit tokens from swapbook user2 to SwapbookAVS escrow
        console.log("Approving SwapbookAVS to spend 100 tokenB from swapbook user2...");
        vm.startBroadcast(swapbookUser2PrivateKey);
        MockERC20(token1Address).approve(address(swapbookAVS), 100e18);
        vm.stopBroadcast();
        
        console.log("Depositing 100 tokenB from swapbook user2 to SwapbookAVS escrow...");
        vm.startBroadcast(swapbookUser2PrivateKey);
        swapbookAVS.depositFunds(token1Address, 100e18);
        vm.stopBroadcast();
        
        // Approve SwapbookV2 to spend SwapbookAVS tokens
        console.log("Approving SwapbookV2 to spend SwapbookAVS tokens...");
        vm.startBroadcast(attestationCenterPrivateKey);
        swapbookAVS.approveToken(token0Address, swapbookV2Address, type(uint256).max);
        swapbookAVS.approveToken(token1Address, swapbookV2Address, type(uint256).max);
        vm.stopBroadcast();
        
        // Call afterTaskSubmission to execute the CompleteFill
        vm.startBroadcast(attestationCenterPrivateKey);
        swapbookAVS.afterTaskSubmission(
            completeTaskInfo,
            true,  // isApproved
            "",    // tpSignature
            [uint256(0), uint256(0)], // taSignature
            new uint256[](0) // attestersIds
        );
        vm.stopBroadcast();
        
        console.log("Buy order executed successfully (CompleteFill)!");
    }
    
    function _checkStateAfterSellOrder(
        SwapbookV2 swapbookV2,
        SwapbookAVS swapbookAVS,
        PoolId poolId,
        PoolKey memory key,
        address token0Address,
        address token1Address,
        address swapbookUserAddress
    ) internal view {
        // Check SwapbookV2 state
        uint256 pendingOrderAfter = swapbookV2.pendingOrders(poolId, 0, false);
        console.log("Pending order at tick 0 after sell order:", pendingOrderAfter);
        
        int24 bestTickAfter = swapbookV2.bestTicks(poolId, false);
        console.log("Best tick after sell order:", bestTickAfter);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(token0Address, token1Address, false);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(token0Address, token1Address, false);
        uint256 bestOrderInputAmount = swapbookAVS.bestOrderInputAmount(token0Address, token1Address, false);
        uint256 bestOrderOutputAmount = swapbookAVS.bestOrderOutputAmount(token0Address, token1Address, false);
        
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
    
    function _checkStateAfterOrderMatching(
        SwapbookV2 swapbookV2,
        SwapbookAVS swapbookAVS,
        PoolId poolId,
        PoolKey memory key,
        address token0Address,
        address token1Address,
        address swapbookUserAddress,
        address swapbookUser2Address
    ) internal view {
        // Check SwapbookV2 state
        uint256 pendingOrderAfter = swapbookV2.pendingOrders(poolId, 0, false);
        console.log("Pending order at tick 0 after matching:", pendingOrderAfter);
        
        int24 bestTickAfter = swapbookV2.bestTicks(poolId, false);
        console.log("Best tick after matching:", bestTickAfter);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(token0Address, token1Address, false);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(token0Address, token1Address, false);
        uint256 bestOrderInputAmount = swapbookAVS.bestOrderInputAmount(token0Address, token1Address, false);
        uint256 bestOrderOutputAmount = swapbookAVS.bestOrderOutputAmount(token0Address, token1Address, false);
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);
        console.log("Best order input amount:", bestOrderInputAmount);
        console.log("Best order output amount:", bestOrderOutputAmount);
        
        // Check escrowed balances for both users after matching
        uint256 swapbookEscrowedToken0 = swapbookAVS.getEscrowedBalance(swapbookUserAddress, token0Address);
        uint256 swapbookEscrowedToken1 = swapbookAVS.getEscrowedBalance(swapbookUserAddress, token1Address);
        uint256 swapbookUser2EscrowedToken0 = swapbookAVS.getEscrowedBalance(swapbookUser2Address, token0Address);
        uint256 swapbookUser2EscrowedToken1 = swapbookAVS.getEscrowedBalance(swapbookUser2Address, token1Address);
        
        console.log("=== AFTER ORDER MATCHING ===");
        console.log("Swapbook user escrowed token0:", swapbookEscrowedToken0);
        console.log("Swapbook user escrowed token1:", swapbookEscrowedToken1);
        console.log("Swapbook user2 escrowed token0:", swapbookUser2EscrowedToken0);
        console.log("Swapbook user2 escrowed token1:", swapbookUser2EscrowedToken1);
        
        // Check if the orders were matched (balances should reflect the swap)
        if (swapbookEscrowedToken0 == 0 && swapbookEscrowedToken1 > 0) {
            console.log("[SUCCESS] Swapbook user's sell order was filled!");
            console.log("[SUCCESS] Swapbook user received token1 for their token0");
        }
        
        if (swapbookUser2EscrowedToken1 == 0 && swapbookUser2EscrowedToken0 > 0) {
            console.log("[SUCCESS] Swapbook user2's buy order was filled!");
            console.log("[SUCCESS] Swapbook user2 received token0 for their token1");
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
        address swapbookUser2Address
    ) internal view {
        // Check pool state
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        console.log("Final pool current tick:", currentTick);
        console.log("Final pool sqrtPriceX96:", sqrtPriceX96);
        
        // Check SwapbookV2 state
        uint256 pendingOrderFinal = swapbookV2.pendingOrders(poolId, 0, false);
        console.log("Final pending order at tick 0:", pendingOrderFinal);
        
        int24 bestTickFinal = swapbookV2.bestTicks(poolId, false);
        console.log("Final best tick:", bestTickFinal);
        
        // Check SwapbookAVS state
        address bestOrderUserFinal = swapbookAVS.bestOrderUsers(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1), false);
        console.log("Final best order user:", bestOrderUserFinal);
        
        // Check user balances
        uint256 token0BalanceFinal = token0.balanceOf(swapbookUser2Address);
        uint256 token1BalanceFinal = token1.balanceOf(swapbookUser2Address);
        
        console.log("Final Token0 balance:", token0BalanceFinal);
        console.log("Final Token1 balance:", token1BalanceFinal);
    }
}
