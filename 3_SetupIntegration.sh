#!/bin/bash

# Integration Test script for SwapbookV2 + SwapbookAVS
# This script tests the integration by simulating the testSwapbookV2Integration test case

set -e  # Exit on any error

echo "🧪 Testing SwapbookV2 + SwapbookAVS Integration..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "PRIVATE_KEY=0x..."
    echo "BASE_TESTNET_RPC=https://sepolia.base.org"
    echo "SWAPBOOK_V2_ADDRESS=0x..."
    echo "SWAPBOOK_AVS_ADDRESS=0x..."
    echo "ATTESTATION_CENTER_ADDRESS=0x..."
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

echo "✅ Environment variables loaded successfully"
echo "📍 RPC URL: $BASE_TESTNET_RPC"
echo "🔑 Private key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"
echo "🏗️  SwapbookV2 address: $SWAPBOOK_V2_ADDRESS"
echo "🏗️  SwapbookAVS address: $SWAPBOOK_AVS_ADDRESS"
echo "🏗️  Attestation Center address: $ATTESTATION_CENTER_ADDRESS"

# Build the project first
echo "🔨 Building project..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful"

# Run the integration test script
echo "🚀 Running integration test..."

forge script script/3_SetupIntegration.s.sol \
    --rpc-url "$BASE_TESTNET_RPC" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --chain base-sepolia

if [ $? -eq 0 ]; then
    echo "✅ Integration test successful!"
    echo "🎉 SwapbookV2 + SwapbookAVS integration is working correctly!"
    echo ""
    echo "📋 Test Summary:"
    echo "1. ✅ Test tokens deployed and minted"
    echo "2. ✅ UpdateBestPrice task processed"
    echo "3. ✅ Order placed in SwapbookV2"
    echo "4. ✅ Best order information stored in SwapbookAVS"
    echo "5. ✅ All verifications passed"
    echo ""
    echo "🚀 The integration is functioning as expected!"
else
    echo "❌ Integration test failed!"
    echo "Please check the logs above for details"
    exit 1
fi
