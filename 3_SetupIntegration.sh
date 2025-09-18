#!/bin/bash

# Setup Integration script for SwapbookV2 + SwapbookAVS
# This script completes the integration by setting up the remaining connections

set -e  # Exit on any error

echo "🔧 Setting up SwapbookV2 + SwapbookAVS Integration..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "PRIVATE_KEY=0x..."
    echo "BASE_TESTNET_RPC=https://sepolia.base.org"
    echo "SWAPBOOK_V2_ADDRESS=0x..."
    echo "SWAPBOOK_AVS_ADDRESS=0x..."
    echo "ATTESTATION_CENTER_ADDRESS=0x..."
    echo "TOKEN0_ADDRESS=0x..."
    echo "TOKEN1_ADDRESS=0x..."
    exit 1
fi

# Load environment variables from .env
echo "📁 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not found in .env file"
    exit 1
fi

if [ -z "$BASE_TESTNET_RPC" ]; then
    echo "❌ Error: BASE_TESTNET_RPC not found in .env file"
    exit 1
fi

if [ -z "$SWAPBOOK_V2_ADDRESS" ]; then
    echo "❌ Error: SWAPBOOK_V2_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$SWAPBOOK_AVS_ADDRESS" ]; then
    echo "❌ Error: SWAPBOOK_AVS_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$ATTESTATION_CENTER_ADDRESS" ]; then
    echo "❌ Error: ATTESTATION_CENTER_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$TOKEN0_ADDRESS" ]; then
    echo "❌ Error: TOKEN0_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$TOKEN1_ADDRESS" ]; then
    echo "❌ Error: TOKEN1_ADDRESS not found in .env file"
    exit 1
fi

echo "✅ Environment variables loaded successfully"
echo "📍 RPC URL: $BASE_TESTNET_RPC"
echo "🔑 Private key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"
echo "🏗️  SwapbookV2 address: $SWAPBOOK_V2_ADDRESS"
echo "🏗️  SwapbookAVS address: $SWAPBOOK_AVS_ADDRESS"
echo "🏗️  Attestation Center address: $ATTESTATION_CENTER_ADDRESS"
echo "🪙  Token0 address: $TOKEN0_ADDRESS"
echo "🪙  Token1 address: $TOKEN1_ADDRESS"

# Note: forge script will compile only the necessary files
echo "🔨 Compiling script and dependencies..."

# Run the integration setup script
echo "🚀 Setting up integration..."

forge script script/3_SetupIntegration.s.sol \
    --rpc-url "$BASE_TESTNET_RPC" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --chain base-sepolia

if [ $? -eq 0 ]; then
    echo "✅ Integration setup successful!"
    echo "🎉 SwapbookV2 + SwapbookAVS integration is now complete!"
    echo ""
    echo "📋 Integration Summary:"
    echo "1. ✅ Attestation center set in SwapbookAVS"
    echo "2. ✅ SwapbookV2 address set in SwapbookAVS"
    echo "3. ✅ SwapbookAVS address set in SwapbookV2"
    echo "4. ✅ Token approvals set for SwapbookV2"
    echo "5. ✅ All connections and approvals verified"
    echo ""
    echo "🚀 System is now ready for use:"
    echo "- Users can deposit funds via SwapbookAVS"
    echo "- Limit orders can be placed and managed"
    echo "- Swaps will trigger order execution via SwapbookV2 hook"
else
    echo "❌ Integration setup failed!"
    exit 1
fi
