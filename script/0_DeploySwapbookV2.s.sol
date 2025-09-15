// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title DeploySwapbookV2
 * @notice Deploy script for SwapbookV2 Hook on Base testnet
 * @dev This script deploys only the SwapbookV2 contract
 */
import {Script, console} from "forge-std/Script.sol";
import {SwapbookV2} from "../src/SwapbookV2.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

contract DeploySwapbookV2 is Script {
    // Base testnet addresses
    address constant POOL_MANAGER_BASE_TESTNET = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408; // Base testnet PoolManager
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Hook permissions for SwapbookV2
    uint160 constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | 
        Hooks.BEFORE_SWAP_FLAG | 
        Hooks.AFTER_SWAP_FLAG
    );

    function setUp() public {}

    function run() public returns (address swapbookV2Address) {
        console.log("=== Deploying SwapbookV2 Hook on Base Testnet ===");
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Mine hook address for SwapbookV2
        console.log("\n--- Mining SwapbookV2 Hook Address ---");
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER_BASE_TESTNET), "");
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            HOOK_FLAGS,
            type(SwapbookV2).creationCode,
            constructorArgs
        );

        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // Step 2: Deploy SwapbookV2 with the mined address
        console.log("\n--- Deploying SwapbookV2 ---");
        SwapbookV2 swapbookV2 = new SwapbookV2{salt: salt}(
            IPoolManager(POOL_MANAGER_BASE_TESTNET),
            ""
        );

        require(address(swapbookV2) == hookAddress, "Hook address mismatch");
        console.log("SwapbookV2 deployed at:", address(swapbookV2));

        vm.stopBroadcast();

        // Step 3: Verify deployment
        console.log("\n=== Deployment Summary ===");
        console.log("SwapbookV2 address:", address(swapbookV2));
        console.log("PoolManager address:", POOL_MANAGER_BASE_TESTNET);
        console.log("Hook flags:", HOOK_FLAGS);
        
        // Verify hook permissions
        console.log("\n--- Verifying Hook Permissions ---");
        Hooks.Permissions memory permissions = swapbookV2.getHookPermissions();
        console.log("After Initialize:", permissions.afterInitialize);
        console.log("Before Swap:", permissions.beforeSwap);
        console.log("After Swap:", permissions.afterSwap);

        return address(swapbookV2);
    }

}

/*
Deployment Commands:

1. Deploy to Base Testnet:
   forge script script/0_DeploySwapbookV2.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $BASE_ETHERSCAN_API_KEY --chain base-sepolia

2. Deploy to local network:
   forge script script/0_DeploySwapbookV2.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- PRIVATE_KEY: Your private key for deployment
- BASE_TESTNET_RPC: Base testnet RPC URL
- BASE_ETHERSCAN_API_KEY: Base Etherscan API key for verification

Example .env file:
PRIVATE_KEY=0x1234567890abcdef...
BASE_TESTNET_RPC=https://sepolia.base.org
BASE_ETHERSCAN_API_KEY=your_api_key_here
*/
