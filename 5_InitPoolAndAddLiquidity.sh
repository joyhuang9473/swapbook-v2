#!/bin/bash

# Initialize Pool and Add Liquidity
# This script mints tokens, initializes a new pool, and adds initial liquidity

echo "=== Initialize Pool and Add Liquidity ==="
echo "Minting tokens and setting up pool for trading with SwapbookV2 hook"
echo ""

# Load environment variables from .env
echo "📁 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# Check if required environment variables are set
required_vars=("POOL_MANAGER_ADDRESS" "SWAPBOOK_V2_ADDRESS" "TOKEN0_ADDRESS" "TOKEN1_ADDRESS" "PRIVATE_KEY" "BASE_TESTNET_RPC")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set"
        echo "Please set all required environment variables:"
        echo "  POOL_MANAGER_ADDRESS: Uniswap V4 Pool Manager contract address"
        echo "  SWAPBOOK_V2_ADDRESS: SwapbookV2 hook contract address"
        echo "  TOKEN0_ADDRESS: Token0 contract address (lower address)"
        echo "  TOKEN1_ADDRESS: Token1 contract address (higher address)"
        echo "  PRIVATE_KEY: Your private key for deployment"
        echo "  BASE_TESTNET_RPC: Base testnet RPC URL"
        exit 1
    fi
done

echo "Environment variables loaded:"
echo "  POOL_MANAGER_ADDRESS: $POOL_MANAGER_ADDRESS"
echo "  SWAPBOOK_V2_ADDRESS: $SWAPBOOK_V2_ADDRESS"
echo "  TOKEN0_ADDRESS: $TOKEN0_ADDRESS"
echo "  TOKEN1_ADDRESS: $TOKEN1_ADDRESS"
echo "  BASE_TESTNET_RPC: $BASE_TESTNET_RPC"
echo ""

# Check deployer address
echo "Checking deployer address..."
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
echo "Deployer address: $DEPLOYER_ADDRESS"

# Note: The script will automatically mint tokens for the deployer
echo "Note: The script will automatically mint 1,000,000 tokens of each type for the deployer"
echo "This ensures sufficient balance for adding large amounts of liquidity to the pool"
echo ""

# Run the pool initialization
echo "Running pool initialization..."
echo ""

forge script script/5_InitPoolAndAddLiquidity.s.sol \
    --rpc-url $BASE_TESTNET_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --chain base-sepolia \
    --via-ir

echo ""
echo "=== Pool Initialization Complete ==="
echo "Pool is now ready for trading!"
echo "You can now run Scenario0_Basic_Swap to query prices and simulate swaps"
echo ""
echo "Next steps:"
echo "1. Run: ./6_Scenario0_Basic_Swap.sh"
echo "2. Or run other scenarios that require an initialized pool"
