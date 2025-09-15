// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title MintTestTokens
 * @notice Script to mint test tokens to a specified user
 * @dev This script mints tokens from deployed test token contracts to a target user
 */
import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MintTestTokens is Script {
    function setUp() public {}

    function run() public {
        console.log("=== Minting Test Tokens to User ===");
        
        // Get token addresses and user address from environment
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        address userAddress = vm.envAddress("USER_ADDRESS");
        uint256 mintAmount = vm.envUint("MINT_AMOUNT");
        
        console.log("Token0 address:", token0Address);
        console.log("Token1 address:", token1Address);
        console.log("User address:", userAddress);
        console.log("Mint amount per token:", mintAmount);
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Create token instances
        MockERC20 token0 = MockERC20(token0Address);
        MockERC20 token1 = MockERC20(token1Address);
        
        // Check current balances
        console.log("\n--- Current Balances ---");
        console.log("User Token0 balance:", token0.balanceOf(userAddress));
        console.log("User Token1 balance:", token1.balanceOf(userAddress));
        
        // Mint tokens to user
        console.log("\n--- Minting Tokens ---");
        token0.mint(userAddress, mintAmount);
        token1.mint(userAddress, mintAmount);
        
        console.log("Minted", mintAmount, "Token0 to user");
        console.log("Minted", mintAmount, "Token1 to user");
        
        // Check new balances
        console.log("\n--- New Balances ---");
        console.log("User Token0 balance:", token0.balanceOf(userAddress));
        console.log("User Token1 balance:", token1.balanceOf(userAddress));
        
        // Calculate total minted
        uint256 totalMinted = mintAmount * 2; // 2 tokens
        console.log("Total tokens minted:", totalMinted);

        vm.stopBroadcast();

        console.log("\n[SUCCESS] Test tokens minted successfully!");
        console.log("[INFO] User now has sufficient tokens for testing");
        console.log("[INFO] Token0 balance:", token0.balanceOf(userAddress));
        console.log("[INFO] Token1 balance:", token1.balanceOf(userAddress));
    }
}

/*
Token Minting Commands:

1. Mint tokens on Base Testnet:
   TOKEN0_ADDRESS=0x... TOKEN1_ADDRESS=0x... USER_ADDRESS=0x... MINT_AMOUNT=1000000000000000000000 forge script script/4_MintTestTokens.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --chain base-sepolia

2. Mint tokens on local network:
   TOKEN0_ADDRESS=0x... TOKEN1_ADDRESS=0x... USER_ADDRESS=0x... MINT_AMOUNT=1000000000000000000000 forge script script/4_MintTestTokens.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- TOKEN0_ADDRESS: Address of deployed Token0 contract
- TOKEN1_ADDRESS: Address of deployed Token1 contract
- USER_ADDRESS: Address of user to mint tokens to
- MINT_AMOUNT: Amount to mint per token (in wei, e.g., 1000000000000000000000 for 1000 tokens)
- PRIVATE_KEY: Your private key for minting
- BASE_TESTNET_RPC: Base testnet RPC URL (for Base Testnet)

What this script does:
1. Loads token addresses and user address from environment
2. Creates MockERC20 instances from deployed addresses
3. Checks current user balances
4. Mints specified amount of each token to the user
5. Displays new balances after minting

Common MINT_AMOUNT values:
- 1000000000000000000000 (1000 tokens with 18 decimals)
- 10000000000000000000000 (10000 tokens with 18 decimals)
- 100000000000000000000000 (100000 tokens with 18 decimals)

Note: MINT_AMOUNT should be in wei (18 decimals for standard ERC20 tokens)
*/
