// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title DeployTestTokens
 * @notice Script to deploy test tokens for testing SwapbookV2 + SwapbookAVS integration
 * @dev This script deploys MockERC20 tokens and mints them to test users
 */
import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployTestTokens is Script {
    function setUp() public {}

    function run() public returns (address token0Address, address token1Address) {
        console.log("=== Deploying Test Tokens ===");
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy test tokens
        console.log("\n--- Deploying MockERC20 Tokens ---");
        MockERC20 tokenA = new MockERC20("TokenA", "TokenA", 18);
        MockERC20 tokenB = new MockERC20("TokenB", "TokenB", 18);
        
        console.log("TokenA deployed at:", address(tokenA));
        console.log("TokenB deployed at:", address(tokenB));
        
        // Ensure proper ordering: lower address = token0, higher address = token1
        MockERC20 token0;
        MockERC20 token1;
        
        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
            console.log("TokenA has lower address, using as token0");
        } else {
            token0 = tokenB;
            token1 = tokenA;
            console.log("TokenB has lower address, using as token0");
        }
        
        console.log("\n--- Final Token Assignment ---");
        console.log("Token0 address:", address(token0));
        console.log("Token1 address:", address(token1));
        console.log("Token0 name:", token0.name());
        console.log("Token1 name:", token1.name());
        console.log("Token0 symbol:", token0.symbol());
        console.log("Token1 symbol:", token1.symbol());
        console.log("Token0 decimals:", token0.decimals());
        console.log("Token1 decimals:", token1.decimals());

        vm.stopBroadcast();

        console.log("\n[SUCCESS] Test tokens deployed successfully!");
        console.log("[INFO] Token addresses:");
        console.log("  Token0:", address(token0));
        console.log("  Token1:", address(token1));
        console.log("[INFO] You can now use these tokens for testing SwapbookV2 + SwapbookAVS integration");
        console.log("\n[INFO] PoolKey creation helper:");
        console.log("  PoolKey memory key = PoolKey({");
        console.log("    currency0: Currency.wrap(address(token0)),");
        console.log("    currency1: Currency.wrap(address(token1)),");
        console.log("    fee: 3000,");
        console.log("    tickSpacing: 60,");
        console.log("    hooks: IHooks(address(swapbookV2))");
        console.log("  });");

        return (address(token0), address(token1));
    }
}

/*
Test Token Deployment Commands:

1. Deploy test tokens on Base Testnet:
   forge script script/3_DeployTestTokens.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $PRIVATE_KEY --broadcast --chain base-sepolia

2. Deploy test tokens on local network:
   forge script script/3_DeployTestTokens.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast

Environment Variables Required:
- PRIVATE_KEY: Your private key for deployment
- BASE_TESTNET_RPC: Base testnet RPC URL (for Base Testnet)

What this script does:
1. Deploys two MockERC20 tokens (TokenA and TokenB)
2. Ensures proper ordering: lower address = token0, higher address = token1
3. Displays token addresses and basic information
4. Returns the properly ordered token addresses for use in other scripts

Token Details:
- Token0: Lower address token (18 decimals)
- Token1: Higher address token (18 decimals)

Important: In Uniswap V4, tokens are ordered by address value, not deployment order!
*/
