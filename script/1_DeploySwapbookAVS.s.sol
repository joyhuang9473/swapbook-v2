// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title DeploySwapbookAVS
 * @notice Deploy script for SwapbookAVS contract
 * @dev This script deploys the SwapbookAVS contract which manages escrowed funds for limit orders
 */
import {Script, console} from "forge-std/Script.sol";
import {SwapbookAVS} from "../src/SwapbookAVS.sol";

contract DeploySwapbookAVS is Script {
    function setUp() public {}

    function run() public returns (address swapbookAVSAddress) {
        console.log("=== Deploying SwapbookAVS ===");
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SwapbookAVS
        console.log("\n--- Deploying SwapbookAVS ---");
        SwapbookAVS swapbookAVS = new SwapbookAVS();
        
        console.log("SwapbookAVS deployed at:", address(swapbookAVS));
        console.log("Owner:", swapbookAVS.owner());

        vm.stopBroadcast();

        // Step 3: Verify deployment
        console.log("\n=== Deployment Summary ===");
        console.log("SwapbookAVS address:", address(swapbookAVS));
        console.log("Owner:", swapbookAVS.owner());
        console.log("Deployer:", deployer);
        
        // Verify ownership
        require(swapbookAVS.owner() == deployer, "Ownership not set correctly");

        console.log("\n[SUCCESS] SwapbookAVS deployment successful!");
        console.log("[INFO] Next steps:");
        console.log("1. Set the attestation center: swapbookAVS.setAttestationCenter(address)");
        console.log("2. Set the SwapbookV2 hook: swapbookAVS.setSwapbookV2(address)");
        console.log("3. Users can now deposit funds for limit orders");

        return address(swapbookAVS);
    }
}

/*
Deployment Commands:

1. Deploy to Base Testnet:
   forge script script/1_DeploySwapbookAVS.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $BASE_ETHERSCAN_API_KEY --chain base-sepolia

2. Deploy to local network:
   forge script script/1_DeploySwapbookAVS.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- PRIVATE_KEY: Your private key for deployment
- BASE_TESTNET_RPC: Base testnet RPC URL
- BASE_ETHERSCAN_API_KEY: Base Etherscan API key for verification
*/
