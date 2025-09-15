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

        vm.stopBroadcast();

        // Step 4: Verify integration
        console.log("\n=== Integration Verification ===");
        console.log("SwapbookV2.swapbookAVS():", address(swapbookV2.swapbookAVS()));
        console.log("SwapbookAVS.attestationCenter():", swapbookAVS.attestationCenter());
        console.log("SwapbookAVS.owner():", swapbookAVS.owner());

        // Verify connections
        require(address(swapbookV2.swapbookAVS()) == swapbookAVSAddress, "SwapbookV2 not connected to SwapbookAVS");
        require(swapbookAVS.attestationCenter() == attestationCenterAddress, "Attestation center not set correctly");

        console.log("\n[SUCCESS] Integration setup complete!");
        console.log("[INFO] System is now ready for use:");
        console.log("1. Users can deposit funds via SwapbookAVS");
        console.log("2. Limit orders can be placed and managed");
        console.log("3. Swaps will trigger order execution via SwapbookV2 hook");
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
- BASE_TESTNET_RPC: Base testnet RPC URL (for Base Testnet)

What this script does:
1. Sets the attestation center in SwapbookAVS
2. Sets SwapbookV2 address in SwapbookAVS
3. Sets SwapbookAVS address in SwapbookV2
4. Verifies all connections are correct
5. Confirms the system is ready for use
*/
