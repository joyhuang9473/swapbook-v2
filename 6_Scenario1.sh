#!/bin/bash

# Scenario 1: Limit Order and Swap
# SWAPBOOK_USER places a limit order, UNISWAP_USER executes a swap

echo "=== Scenario 1: Limit Order and Swap ==="
echo "SWAPBOOK_USER places limit order (tick=-60, 100 tokenA -> 99.4 tokenB)"
echo "UNISWAP_USER executes swap (100 tokenB -> tokenA) via Universal Router"
echo "This triggers SwapbookV2 hook and processes the limit order"
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
        echo "  BASE_TESTNET_RPC: Base testnet RPC URL"
        exit 1
    fi
done

echo "✅ Environment variables loaded successfully"
echo ""

# Display configuration
echo "📋 Configuration:"
echo "  Pool Manager: $POOL_MANAGER_ADDRESS"
echo "  SwapbookV2: $SWAPBOOK_V2_ADDRESS"
echo "  SwapbookAVS: $SWAPBOOK_AVS_ADDRESS"
echo "  Attestation Center: $ATTESTATION_CENTER_ADDRESS"
echo "  Universal Router: $UNIVERSAL_ROUTER_ADDRESS"
echo "  Token0: $TOKEN0_ADDRESS"
echo "  Token1: $TOKEN1_ADDRESS"
echo "  Swapbook User: $SWAPBOOK_USER_ADDRESS"
echo "  Uniswap User: $UNISWAP_USER_ADDRESS"
echo "  RPC URL: $BASE_TESTNET_RPC"
echo ""

# Check if users have sufficient token balances
echo "🔍 Checking user balances..."

# Check SWAPBOOK_USER token0 balance (for limit order)
SWAPBOOK_USER_TOKEN0_BALANCE=$(cast call $TOKEN0_ADDRESS "balanceOf(address)" $SWAPBOOK_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
SWAPBOOK_USER_TOKEN0_BALANCE_DECIMAL=$(cast to-dec $SWAPBOOK_USER_TOKEN0_BALANCE)
SWAPBOOK_USER_TOKEN0_BALANCE_FORMATTED=$(echo "scale=18; $SWAPBOOK_USER_TOKEN0_BALANCE_DECIMAL / 1000000000000000000" | bc)

echo "SWAPBOOK_USER Token0 balance: $SWAPBOOK_USER_TOKEN0_BALANCE_FORMATTED"

REQUIRED_TOKEN0_AMOUNT=100000000000000000000  # 100 tokens in wei
if [ "$SWAPBOOK_USER_TOKEN0_BALANCE_DECIMAL" -lt "$REQUIRED_TOKEN0_AMOUNT" ]; then
    echo "❌ Error: SWAPBOOK_USER doesn't have enough token0"
    echo "Required: 100 tokens"
    echo "Available: $SWAPBOOK_USER_TOKEN0_BALANCE_FORMATTED tokens"
    echo ""
    echo "Please mint more tokens first using:"
    echo "  TOKEN0_ADDRESS=$TOKEN0_ADDRESS TOKEN1_ADDRESS=$TOKEN1_ADDRESS USER_ADDRESS=$SWAPBOOK_USER_ADDRESS MINT_AMOUNT=1000000000000000000000 forge script script/4_MintTestTokens.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $SWAPBOOK_USER_PRIVATE_KEY --broadcast --chain base-sepolia"
    exit 1
fi

# Check UNISWAP_USER token1 balance (for swap)
UNISWAP_USER_TOKEN1_BALANCE=$(cast call $TOKEN1_ADDRESS "balanceOf(address)" $UNISWAP_USER_ADDRESS --rpc-url $BASE_TESTNET_RPC)
UNISWAP_USER_TOKEN1_BALANCE_DECIMAL=$(cast to-dec $UNISWAP_USER_TOKEN1_BALANCE)
UNISWAP_USER_TOKEN1_BALANCE_FORMATTED=$(echo "scale=18; $UNISWAP_USER_TOKEN1_BALANCE_DECIMAL / 1000000000000000000" | bc)

echo "UNISWAP_USER Token1 balance: $UNISWAP_USER_TOKEN1_BALANCE_FORMATTED"

REQUIRED_TOKEN1_AMOUNT=100000000000000000000  # 100 tokens in wei
if [ "$UNISWAP_USER_TOKEN1_BALANCE_DECIMAL" -lt "$REQUIRED_TOKEN1_AMOUNT" ]; then
    echo "❌ Error: UNISWAP_USER doesn't have enough token1"
    echo "Required: 100 tokens"
    echo "Available: $UNISWAP_USER_TOKEN1_BALANCE_FORMATTED tokens"
    echo ""
    echo "Please mint more tokens first using:"
    echo "  TOKEN0_ADDRESS=$TOKEN0_ADDRESS TOKEN1_ADDRESS=$TOKEN1_ADDRESS USER_ADDRESS=$UNISWAP_USER_ADDRESS MINT_AMOUNT=1000000000000000000000 forge script script/4_MintTestTokens.s.sol --rpc-url $BASE_TESTNET_RPC --private-key $UNISWAP_USER_PRIVATE_KEY --broadcast --chain base-sepolia"
    exit 1
fi

echo "✅ Both users have sufficient token balances"
echo ""

# Run the scenario
echo "🚀 Running Scenario 1: Limit Order and Swap..."
echo ""

forge script script/6_Scenario1.s.sol \
    --rpc-url $BASE_TESTNET_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --chain base-sepolia \
    --via-ir

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Scenario 1 completed successfully!"
    echo ""
    echo "📋 What happened:"
    echo "1. ✅ SWAPBOOK_USER placed limit order (tick=-60, 100 tokenA -> 99.4 tokenB)"
    echo "2. ✅ UNISWAP_USER executed swap (100 tokenB -> tokenA) via Universal Router"
    echo "3. ✅ SwapbookV2 hook was triggered during the swap"
    echo "4. ✅ Limit order was processed via SwapbookAVS.afterTaskSubmission"
    echo "5. ✅ UNISWAP_USER received better execution price due to limit order"
    echo "6. ✅ Price improvement was calculated and verified"
    echo ""
    echo "🔍 Check the transaction on Base Sepolia explorer:"
    echo "https://sepolia.basescan.org/tx/<transaction_hash>"
else
    echo "❌ Scenario 1 failed!"
    echo "Please check the logs above for details"
    exit 1
fi
