// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title SetupIntegration
 * @notice Setup script for completing SwapbookV2 + SwapbookAVS integration
 * @dev This script completes the integration by setting up the remaining connections
 */
import {Script, console} from "forge-std/Script.sol";
import {SwapbookV2} from "../src/SwapbookV2.sol";
import {SwapbookAVS} from "../src/SwapbookAVS.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract SetupIntegration is Script {
    function setUp() public {}

    function run() public {
        console.log("=== Setting up SwapbookV2 + SwapbookAVS Integration ===");
        
        // Get contract addresses from environment or input
        address swapbookV2Address = vm.envAddress("SWAPBOOK_V2_ADDRESS");
        address swapbookAVSAddress = vm.envAddress("SWAPBOOK_AVS_ADDRESS");
        address attestationCenterAddress = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
        
        console.log("SwapbookV2 address:", swapbookV2Address);
        console.log("SwapbookAVS address:", swapbookAVSAddress);
        console.log("Attestation Center address:", attestationCenterAddress);
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Create contract instances
        SwapbookV2 swapbookV2 = SwapbookV2(swapbookV2Address);
        SwapbookAVS swapbookAVS = SwapbookAVS(swapbookAVSAddress);

        // Step 1: Set attestation center in SwapbookAVS
        console.log("\n--- Step 1: Setting Attestation Center ---");
        swapbookAVS.setAttestationCenter(attestationCenterAddress);
        console.log("Attestation center set to:", swapbookAVS.attestationCenter());

        // Step 2: Set SwapbookV2 in SwapbookAVS
        console.log("\n--- Step 2: Setting SwapbookV2 in SwapbookAVS ---");
        swapbookAVS.setSwapbookV2(swapbookV2Address);
        console.log("SwapbookV2 set in SwapbookAVS");

        // Step 3: Set SwapbookAVS in SwapbookV2
        console.log("\n--- Step 3: Setting SwapbookAVS in SwapbookV2 ---");
        swapbookV2.setSwapbookAVS(swapbookAVSAddress);
        console.log("SwapbookAVS set in SwapbookV2");

        // Step 4: Approve SwapbookV2 to spend tokens from SwapbookAVS
        console.log("\n--- Step 4: Setting up token approvals ---");
        
        // Get token addresses from environment
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        
        console.log("Token0 address:", token0Address);
        console.log("Token1 address:", token1Address);
        
        // Import MockERC20 for approvals
        MockERC20 token0 = MockERC20(token0Address);
        MockERC20 token1 = MockERC20(token1Address);
        
        // Have SwapbookAVS approve SwapbookV2 to spend tokens
        // This allows SwapbookAVS to place orders in SwapbookV2
        console.log("SwapbookAVS approving Token0 for SwapbookV2...");
        swapbookAVS.approveToken(token0Address, swapbookV2Address, type(uint256).max);
        console.log("Token0 approval set to max uint256");
        
        console.log("SwapbookAVS approving Token1 for SwapbookV2...");
        swapbookAVS.approveToken(token1Address, swapbookV2Address, type(uint256).max);
        console.log("Token1 approval set to max uint256");

        vm.stopBroadcast();

        // Step 5: Verify integration
        console.log("\n=== Integration Verification ===");
        console.log("SwapbookV2.swapbookAVS():", address(swapbookV2.swapbookAVS()));
        console.log("SwapbookAVS.attestationCenter():", swapbookAVS.attestationCenter());
        console.log("SwapbookAVS.owner():", swapbookAVS.owner());
        
        // Verify token approvals
        console.log("Token0 allowance for SwapbookV2:", token0.allowance(swapbookAVSAddress, swapbookV2Address));
        console.log("Token1 allowance for SwapbookV2:", token1.allowance(swapbookAVSAddress, swapbookV2Address));

        // Verify connections
        require(address(swapbookV2.swapbookAVS()) == swapbookAVSAddress, "SwapbookV2 not connected to SwapbookAVS");
        require(swapbookAVS.attestationCenter() == attestationCenterAddress, "Attestation center not set correctly");
        require(token0.allowance(swapbookAVSAddress, swapbookV2Address) > 0, "Token0 not approved for SwapbookV2");
        require(token1.allowance(swapbookAVSAddress, swapbookV2Address) > 0, "Token1 not approved for SwapbookV2");

        console.log("\n[SUCCESS] Integration setup complete!");
        console.log("[INFO] System is now ready for use:");
        console.log("1. Users can deposit funds via SwapbookAVS");
        console.log("2. Limit orders can be placed and managed");
        console.log("3. Swaps will trigger order execution via SwapbookV2 hook");
        console.log("4. Token approvals are set for SwapbookV2 to spend from SwapbookAVS");
    }
}

/*
Integration Setup Commands:

1. Set up integration on Base Testnet:
   SWAPBOOK_V2_ADDRESS=0x... SWAPBOOK_AVS_ADDRESS=0x... ATTESTATION_CENTER_ADDRESS=0x... forge script script/2_SetupIntegration.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --chain base-sepolia

2. Set up integration on local network:
   SWAPBOOK_V2_ADDRESS=0x... SWAPBOOK_AVS_ADDRESS=0x... ATTESTATION_CENTER_ADDRESS=0x... forge script script/2_SetupIntegration.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- PRIVATE_KEY: Your private key for deployment
- SWAPBOOK_V2_ADDRESS: Address of deployed SwapbookV2 contract
- SWAPBOOK_AVS_ADDRESS: Address of deployed SwapbookAVS contract
- ATTESTATION_CENTER_ADDRESS: Address of the attestation center
- TOKEN0_ADDRESS: Address of Token0 (lower address token)
- TOKEN1_ADDRESS: Address of Token1 (higher address token)
- BASE_TESTNET_RPC: Base testnet RPC URL (for Base Testnet)

What this script does:
1. Sets the attestation center in SwapbookAVS
2. Sets SwapbookV2 address in SwapbookAVS
3. Sets SwapbookAVS address in SwapbookV2
4. Approves SwapbookV2 to spend tokens from SwapbookAVS
5. Verifies all connections and approvals are correct
6. Confirms the system is ready for use
*/
