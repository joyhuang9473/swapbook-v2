#!/bin/bash

# Scenario 3: Dual Limit Orders
# SWAPBOOK_USER places sell limit order, UNISWAP_USER places buy limit order at same tick

echo "=== Scenario 3: Order Matching ==="
echo "SWAPBOOK_USER places sell limit order (tick=0, 100 tokenA -> 100 tokenB)"
echo "SWAPBOOK_USER2 places buy order (CompleteFill) to match with sell order"
echo "Orders are matched and executed peer-to-peer"
echo ""

# Load environment variables from .env
echo "📁 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# Check if required environment variables are set
required_vars=(
    "POOL_MANAGER_ADDRESS" 
    "SWAPBOOK_V2_ADDRESS" 
    "SWAPBOOK_AVS_ADDRESS"
    "ATTESTATION_CENTER_ADDRESS"
    "ATTESTATION_CENTER_PRIVATE_KEY"
    "UNIVERSAL_ROUTER_ADDRESS" 
    "TOKEN0_ADDRESS" 
    "TOKEN1_ADDRESS" 
    "SWAPBOOK_USER_ADDRESS"
    "SWAPBOOK_USER_PRIVATE_KEY"
    "SWAPBOOK_USER2_ADDRESS"
    "SWAPBOOK_USER2_PRIVATE_KEY"
    "PRIVATE_KEY"
    "BASE_TESTNET_RPC"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: $var is not set"
        echo "Please set all required environment variables:"
        echo "  POOL_MANAGER_ADDRESS: Uniswap V4 Pool Manager contract address"
        echo "  SWAPBOOK_V2_ADDRESS: SwapbookV2 hook contract address"
        echo "  SWAPBOOK_AVS_ADDRESS: SwapbookAVS contract address"
        echo "  ATTESTATION_CENTER_ADDRESS: Attestation Center contract address"
        echo "  ATTESTATION_CENTER_PRIVATE_KEY: Attestation Center private key"
        echo "  UNIVERSAL_ROUTER_ADDRESS: Universal Router contract address"
        echo "  TOKEN0_ADDRESS: Token0 contract address (lower address)"
        echo "  TOKEN1_ADDRESS: Token1 contract address (higher address)"
        echo "  SWAPBOOK_USER_ADDRESS: Swapbook user address for sell order"
        echo "  SWAPBOOK_USER_PRIVATE_KEY: Swapbook user's private key"
        echo "  SWAPBOOK_USER2_ADDRESS: Swapbook user2 address for buy order"
        echo "  SWAPBOOK_USER2_PRIVATE_KEY: Swapbook user2's private key"
        echo "  PRIVATE_KEY: Deployer private key for gas fees"
        echo "  BASE_TESTNET_RPC: Base Sepolia RPC URL"
        echo ""
        echo "Example .env file:"
        echo "POOL_MANAGER_ADDRESS=0x..."
        echo "SWAPBOOK_V2_ADDRESS=0x..."
        echo "SWAPBOOK_AVS_ADDRESS=0x..."
        echo "ATTESTATION_CENTER_ADDRESS=0x..."
        echo "ATTESTATION_CENTER_PRIVATE_KEY=0x..."
        echo "UNIVERSAL_ROUTER_ADDRESS=0x..."
        echo "TOKEN0_ADDRESS=0x..."
        echo "TOKEN1_ADDRESS=0x..."
        echo "SWAPBOOK_USER_ADDRESS=0x..."
        echo "SWAPBOOK_USER_PRIVATE_KEY=0x..."
        echo "SWAPBOOK_USER2_ADDRESS=0x..."
        echo "SWAPBOOK_USER2_PRIVATE_KEY=0x..."
        echo "PRIVATE_KEY=0x..."
        echo "BASE_TESTNET_RPC=https://sepolia.base.org"
        exit 1
    fi
done

echo "✅ All required environment variables are set"
echo ""

# Display scenario details
echo "📋 Scenario 3 Details:"
echo "  • SWAPBOOK_USER places sell limit order:"
echo "    - Tick: 0"
echo "    - Input: 100 tokenA (to be sold)"
echo "    - Output: 100 tokenB (expected to receive)"
echo "    - Escrow: 100 tokenA (deposited for order)"
echo "  • SWAPBOOK_USER2 places buy order (CompleteFill):"
echo "    - Tick: 0"
echo "    - Input: 100 tokenB (to be sold)"
echo "    - Output: 100 tokenA (expected to receive)"
echo "    - Escrow: 100 tokenB (deposited for order)"
echo "  • CompleteFill matches with existing sell order"
echo "  • Orders are executed peer-to-peer automatically"
echo ""

# Check if contracts are deployed
echo "🔍 Checking contract addresses..."
echo "  Pool Manager: $POOL_MANAGER_ADDRESS"
echo "  SwapbookV2: $SWAPBOOK_V2_ADDRESS"
echo "  SwapbookAVS: $SWAPBOOK_AVS_ADDRESS"
echo "  Attestation Center: $ATTESTATION_CENTER_ADDRESS"
echo "  Universal Router: $UNIVERSAL_ROUTER_ADDRESS"
echo "  Token0: $TOKEN0_ADDRESS"
echo "  Token1: $TOKEN1_ADDRESS"
echo "  Swapbook User: $SWAPBOOK_USER_ADDRESS"
echo "  Swapbook User2: $SWAPBOOK_USER2_ADDRESS"
echo ""

# Check if users have sufficient tokens
echo "💰 Checking user token balances..."

# Check SWAPBOOK_USER token0 balance (needed for sell order)
echo "Checking SWAPBOOK_USER token0 balance..."
SWAPBOOK_USER_BALANCE=$(cast call $TOKEN0_ADDRESS "balanceOf(address)" $SWAPBOOK_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
SWAPBOOK_USER_BALANCE_DEC=$(cast to-dec $SWAPBOOK_USER_BALANCE)
echo "  SWAPBOOK_USER token0 balance: $SWAPBOOK_USER_BALANCE_DEC"

if [ "$SWAPBOOK_USER_BALANCE_DEC" -lt 100000000000000000000 ]; then
    echo "❌ Error: SWAPBOOK_USER doesn't have enough token0"
    echo "  Required: 100000000000000000000 (100 tokens)"
    echo "  Available: $SWAPBOOK_USER_BALANCE_DEC"
    echo "  Please run 4_MintTestTokens.sh first"
    exit 1
fi

# Check SWAPBOOK_USER2 token1 balance (needed for buy order)
echo "Checking SWAPBOOK_USER2 token1 balance..."
SWAPBOOK_USER2_BALANCE=$(cast call $TOKEN1_ADDRESS "balanceOf(address)" $SWAPBOOK_USER2_ADDRESS --rpc-url $BASE_TESTNET_RPC)
SWAPBOOK_USER2_BALANCE_DEC=$(cast to-dec $SWAPBOOK_USER2_BALANCE)
echo "  SWAPBOOK_USER2 token1 balance: $SWAPBOOK_USER2_BALANCE_DEC"

if [ "$SWAPBOOK_USER2_BALANCE_DEC" -lt 100000000000000000000 ]; then
    echo "❌ Error: SWAPBOOK_USER2 doesn't have enough token1"
    echo "  Required: 100000000000000000000 (100 tokens)"
    echo "  Available: $SWAPBOOK_USER2_BALANCE_DEC"
    echo "  Please run 4_MintTestTokens.sh first"
    exit 1
fi

echo "✅ All users have sufficient token balances"
echo ""

# Run the scenario
echo "🚀 Running Scenario 3: Dual Limit Orders..."
echo ""

forge script script/6_Scenario3.s.sol \
    --rpc-url $BASE_TESTNET_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --chain base-sepolia \
    --via-ir

# Check exit status
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Scenario 3 completed successfully!"
    echo ""
    echo "📊 Summary:"
    echo "  • SWAPBOOK_USER placed sell limit order at tick 0"
    echo "  • SWAPBOOK_USER2 placed buy order (CompleteFill)"
    echo "  • Orders were matched and executed peer-to-peer automatically"
    echo "  • Both users received their expected tokens"
    echo ""
    echo "🎉 Scenario 3: Order Matching - SUCCESS!"
else
    echo ""
    echo "❌ Scenario 3 failed!"
    echo "Please check the logs above for details"
    exit 1
fi
