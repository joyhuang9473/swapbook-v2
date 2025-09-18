#!/bin/bash

# Scenario 0: Basic Swap (Actual Execution)
# Uniswap User wants to buy token0 with 100 token1

echo "=== Scenario 0: Basic Swap (Actual Execution) ==="
echo "Uniswap User wants to buy token0 with 100 token1"
echo ""

# Load environment variables from .env
echo "📁 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# Check if required environment variables are set
required_vars=("POOL_MANAGER_ADDRESS" "SWAPBOOK_V2_ADDRESS" "UNIVERSAL_ROUTER_ADDRESS" "TOKEN0_ADDRESS" "TOKEN1_ADDRESS" "UNISWAP_USER_ADDRESS" "UNISWAP_USER_PRIVATE_KEY" "BASE_TESTNET_RPC")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set"
        echo "Please set all required environment variables:"
        echo "  POOL_MANAGER_ADDRESS: Uniswap V4 Pool Manager contract address"
        echo "  SWAPBOOK_V2_ADDRESS: SwapbookV2 hook contract address"
        echo "  TOKEN0_ADDRESS: Token0 contract address (lower address)"
        echo "  TOKEN1_ADDRESS: Token1 contract address (higher address)"
        echo "  UNISWAP_USER_ADDRESS: Uniswap user address for testing"
        echo "  UNISWAP_USER_PRIVATE_KEY: Uniswap user's private key for executing the swap"
        echo "  BASE_TESTNET_RPC: Base testnet RPC URL"
        exit 1
    fi
done

echo "Environment variables loaded:"
echo "  POOL_MANAGER_ADDRESS: $POOL_MANAGER_ADDRESS"
echo "  SWAPBOOK_V2_ADDRESS: $SWAPBOOK_V2_ADDRESS"
echo "  UNIVERSAL_ROUTER_ADDRESS: $UNIVERSAL_ROUTER_ADDRESS"
echo "  TOKEN0_ADDRESS: $TOKEN0_ADDRESS"
echo "  TOKEN1_ADDRESS: $TOKEN1_ADDRESS"
echo "  UNISWAP_USER_ADDRESS: $UNISWAP_USER_ADDRESS"
echo "  BASE_TESTNET_RPC: $BASE_TESTNET_RPC"
echo ""

# Check if user has enough token1 balance
echo "Checking user token1 balance..."
USER_BALANCE=$(cast call $TOKEN1_ADDRESS "balanceOf(address)" $UNISWAP_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
echo "User Token1 balance: $USER_BALANCE"

# Convert to decimal for display
USER_BALANCE_DECIMAL=$(cast to-dec $USER_BALANCE)
USER_BALANCE_DECIMAL_FORMATTED=$(echo "scale=18; $USER_BALANCE_DECIMAL / 1000000000000000000" | bc)
echo "User Token1 balance (decimal): $USER_BALANCE_DECIMAL_FORMATTED"

REQUIRED_AMOUNT=100000000000000000000  # 100 tokens in wei
if [ "$USER_BALANCE_DECIMAL" -lt "$REQUIRED_AMOUNT" ]; then
    echo "Error: User doesn't have enough token1"
    echo "Required: 100 tokens"
    echo "Available: $USER_BALANCE_DECIMAL_FORMATTED tokens"
    echo ""
    echo "Please mint more tokens first using:"
    echo "  TOKEN0_ADDRESS=$TOKEN0_ADDRESS TOKEN1_ADDRESS=$TOKEN1_ADDRESS USER_ADDRESS=$USER_ADDRESS MINT_AMOUNT=1000000000000000000000 forge script script/4_MintTestTokens.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $USER_PRIVATE_KEY --broadcast --chain base-sepolia"
    exit 1
fi

echo "User has sufficient token1 balance ✓"
echo ""

# Run the scenario
echo "Running Scenario 0: Basic Swap (Actual Execution)..."
echo ""

forge script script/Scenario0_Basic_Swap.s.sol \
    --rpc-url $BASE_TESTNET_RPC \
    --private-key $UNISWAP_USER_PRIVATE_KEY \
    --broadcast \
    --chain base-sepolia \
    --via-ir

echo ""
echo "=== Scenario 0 Complete ==="
echo "Check the transaction on Base Sepolia explorer:"
echo "https://sepolia.basescan.org/tx/<transaction_hash>"
