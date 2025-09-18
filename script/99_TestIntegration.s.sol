// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title TestIntegration
 * @notice Simplified integration test script for SwapbookV2 + SwapbookAVS
 * @dev This script tests the integration flow by simulating UpdateBestPrice tasks
 */
import {Script, console} from "forge-std/Script.sol";
import {SwapbookV2} from "../src/SwapbookV2.sol";
import {SwapbookAVS} from "../src/SwapbookAVS.sol";
import {IAttestationCenter} from "../src/interface/IAttestationCenter.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/types/PoolId.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract TestIntegration is Script {
    function setUp() public {}

    function run() public {
        console.log("=== Integration Test ===");
        
        // Get addresses from environment
        address swapbookV2Address = vm.envAddress("SWAPBOOK_V2_ADDRESS");
        address swapbookAVSAddress = vm.envAddress("SWAPBOOK_AVS_ADDRESS");
        address attestationCenterAddress = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        address userAddress = vm.envAddress("USER_ADDRESS");
        
        console.log("Testing with addresses:");
        console.log("SwapbookV2:", swapbookV2Address);
        console.log("SwapbookAVS:", swapbookAVSAddress);
        console.log("Attestation Center:", attestationCenterAddress);
        console.log("Token0:", token0Address);
        console.log("Token1:", token1Address);
        console.log("User:", userAddress);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        // Create contract instances
        SwapbookV2 swapbookV2 = SwapbookV2(swapbookV2Address);
        SwapbookAVS swapbookAVS = SwapbookAVS(swapbookAVSAddress);

        // Create PoolKey
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0Address),
            currency1: Currency.wrap(token1Address),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });

        console.log("\n--- Step 1: Initial State ---");
        console.log("Pending order before:", swapbookV2.pendingOrders(key.toId(), -1000, true));
        console.log("Best tick before:", swapbookV2.bestTicks(key.toId(), true));

        console.log("\n--- Step 2: User Deposits Funds ---");
        
        // User needs to approve tokens first
        vm.prank(userAddress);
        MockERC20(token0Address).approve(address(swapbookAVS), 100e18);
        console.log("User approved 100e18 Token0 for SwapbookAVS");
        
        // User deposits funds to SwapbookAVS
        vm.prank(userAddress);
        swapbookAVS.depositFunds(token0Address, 100e18);
        console.log("User deposited 100e18 Token0 to SwapbookAVS");
        
        // Check escrowed funds
        console.log("User's escrowed Token0:", swapbookAVS.escrowedFunds(userAddress, token0Address));

        console.log("\n--- Step 3: Create Task ---");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            token0Address, 
            token1Address, 
            -1000, // tick
            true,  // zeroForOne
            100e18, // inputAmount
            100e18,     // outputAmount
            userAddress,
            false // useHigherTick
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(SwapbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });

        console.log("Task created successfully");

        console.log("\n--- Step 4: Process Task ---");
        
        // Simulate attestation center call
        vm.prank(attestationCenterAddress);
        swapbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));

        console.log("Task processed successfully");

        console.log("\n--- Step 5: Verify Results ---");
        
        // Check SwapbookV2 state
        uint256 pendingOrderAfter = swapbookV2.pendingOrders(key.toId(), -1020, true);
        int24 bestTickAfter = swapbookV2.bestTicks(key.toId(), true);
        
        console.log("Pending order after (tick -1020):", pendingOrderAfter);
        console.log("Best tick after:", bestTickAfter);
        
        // Check SwapbookAVS state
        address bestOrderUser = swapbookAVS.bestOrderUsers(token0Address, token1Address, true);
        int24 bestOrderTick = swapbookAVS.bestOrderTicks(token0Address, token1Address, true);
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);

        // vm.stopBroadcast();

        console.log("\n--- Verification ---");
        
        // Simple verification
        if (pendingOrderAfter == 100e18) {
            console.log("[SUCCESS] Pending order: 100e18");
        } else {
            console.log("[FAIL] Pending order:", pendingOrderAfter);
        }
        
        if (bestTickAfter == -1020) {
            console.log("[SUCCESS] Best tick: -1020");
        } else {
            console.log("[FAIL] Best tick:", bestTickAfter);
        }
        
        if (bestOrderUser == userAddress) {
            console.log("[SUCCESS] Best order user matches");
        } else {
            console.log("[FAIL] Best order user:", bestOrderUser);
        }
        
        if (bestOrderTick == -1000) {
            console.log("[SUCCESS] Best order tick: -1000");
        } else {
            console.log("[FAIL] Best order tick:", bestOrderTick);
        }

        console.log("\n[INFO] Integration test completed");
    }
}

/*
Integration Test Commands:

1. Test on Base Testnet:
   SWAPBOOK_V2_ADDRESS=0x... SWAPBOOK_AVS_ADDRESS=0x... ATTESTATION_CENTER_ADDRESS=0x... TOKEN0_ADDRESS=0x... TOKEN1_ADDRESS=0x... USER_ADDRESS=0x... forge script script/5_TestIntegration.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --chain base-sepolia

2. Test on local network:
   SWAPBOOK_V2_ADDRESS=0x... SWAPBOOK_AVS_ADDRESS=0x... ATTESTATION_CENTER_ADDRESS=0x... TOKEN0_ADDRESS=0x... TOKEN1_ADDRESS=0x... USER_ADDRESS=0x... forge script script/5_TestIntegration.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- PRIVATE_KEY: Your private key
- SWAPBOOK_V2_ADDRESS: SwapbookV2 contract address
- SWAPBOOK_AVS_ADDRESS: SwapbookAVS contract address
- ATTESTATION_CENTER_ADDRESS: Attestation center address
- TOKEN0_ADDRESS: Token0 contract address
- TOKEN1_ADDRESS: Token1 contract address
- USER_ADDRESS: User address for testing
- BASE_TESTNET_RPC: Base testnet RPC URL

What this script does:
1. User deposits funds to SwapbookAVS (approves and deposits tokens)
2. Creates UpdateBestPrice task data
3. Simulates attestation center calling afterTaskSubmission
4. Verifies SwapbookV2 pending order and best tick
5. Verifies SwapbookAVS best order information
6. Reports test results
*/