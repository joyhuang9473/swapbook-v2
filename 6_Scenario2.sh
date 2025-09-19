#!/bin/bash

# Scenario 2: Limit Order and Large Swap
# SWAPBOOK_USER places a limit order (tick=60), UNISWAP_USER executes large swap

echo "=== Scenario 2: Limit Order and Large Swap ==="
echo "SWAPBOOK_USER places limit order (tick=60, 4000 tokenA -> 4007 tokenB)"
echo "UNISWAP_USER executes large swap (4,500 tokenB -> tokenA) via Universal Router"
echo "This triggers SwapbookV2 hook afterSwap and processes the limit order"
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
    "UNISWAP_USER_ADDRESS"
    "UNISWAP_USER_PRIVATE_KEY"
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
        echo "  SWAPBOOK_USER_ADDRESS: Swapbook user address for limit order"
        echo "  SWAPBOOK_USER_PRIVATE_KEY: Swapbook user's private key"
        echo "  UNISWAP_USER_ADDRESS: Uniswap user address for swap execution"
        echo "  UNISWAP_USER_PRIVATE_KEY: Uniswap user's private key"
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
        echo "UNISWAP_USER_ADDRESS=0x..."
        echo "UNISWAP_USER_PRIVATE_KEY=0x..."
        echo "PRIVATE_KEY=0x..."
        echo "BASE_TESTNET_RPC=https://sepolia.base.org"
        exit 1
    fi
done

echo "✅ All required environment variables are set"
echo ""

# Display scenario details
echo "📋 Scenario 2 Details:"
echo "  • SWAPBOOK_USER places limit order:"
echo "    - Tick: 60"
echo "    - Input: 4000 tokenA (to be sold)"
echo "    - Output: 4007 tokenB (expected to receive)"
echo "    - Escrow: 4000 tokenA (deposited for order)"
echo "  • UNISWAP_USER executes large swap:"
echo "    - Input: 4,500 tokenB (large amount)"
echo "    - Output: tokenA"
echo "    - Expected: Pool tick moves above 60"
echo "    - Triggers: SwapbookV2 afterSwap hook"
echo "  • Result: Limit order gets filled via afterSwap hook"
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
echo "  Uniswap User: $UNISWAP_USER_ADDRESS"
echo ""

# Check if users have sufficient tokens
echo "💰 Checking user token balances..."

# Check SWAPBOOK_USER token0 balance (needed for limit order)
echo "Checking SWAPBOOK_USER token0 balance..."
SWAPBOOK_USER_BALANCE=$(cast call $TOKEN0_ADDRESS "balanceOf(address)" $SWAPBOOK_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
SWAPBOOK_USER_BALANCE_DEC=$(cast to-dec $SWAPBOOK_USER_BALANCE)
echo "  SWAPBOOK_USER token0 balance: $SWAPBOOK_USER_BALANCE_DEC"

if [ "$SWAPBOOK_USER_BALANCE_DEC" -lt 4000000000000000000000 ]; then
    echo "❌ Error: SWAPBOOK_USER doesn't have enough token0"
    echo "  Required: 4000000000000000000000 (4000 tokens)"
    echo "  Available: $SWAPBOOK_USER_BALANCE_DEC"
    echo "  Please run 4_MintTestTokens.sh first"
    exit 1
fi

# Check UNISWAP_USER token1 balance
echo "Checking UNISWAP_USER token1 balance..."
UNISWAP_USER_BALANCE=$(cast call $TOKEN1_ADDRESS "balanceOf(address)" $UNISWAP_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
UNISWAP_USER_BALANCE_DEC=$(cast to-dec $UNISWAP_USER_BALANCE)
echo "  UNISWAP_USER token1 balance: $UNISWAP_USER_BALANCE_DEC"

if [ "$UNISWAP_USER_BALANCE_DEC" -lt 4500000000000000000000 ]; then
    echo "❌ Error: UNISWAP_USER doesn't have enough token1"
    echo "  Required: 4500000000000000000000 (4,500 tokens)"
    echo "  Available: $UNISWAP_USER_BALANCE_DEC"
    echo "  Please run 4_MintTestTokens.sh first"
    exit 1
fi

echo "✅ All users have sufficient token balances"
echo ""

# Run the scenario
echo "🚀 Running Scenario 2: Limit Order and Large Swap..."
echo ""

forge script script/6_Scenario2.s.sol \
    --rpc-url $BASE_TESTNET_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --chain base-sepolia \
    --via-ir

# Check exit status
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Scenario 2 completed successfully!"
    echo ""
    echo "📊 Summary:"
    echo "  • SWAPBOOK_USER placed limit order at tick 60"
    echo "  • UNISWAP_USER executed large swap (4,500 tokenB)"
    echo "  • Pool tick moved above 60"
    echo "  • SwapbookV2 afterSwap hook was triggered"
    echo "  • Limit order was processed and filled"
    echo ""
    echo "🎉 Scenario 2: Limit Order and Large Swap - SUCCESS!"
else
    echo ""
    echo "❌ Scenario 2 failed!"
    echo "Please check the logs above for details"
    exit 1
fi
