#!/bin/bash

# Deploy SwapbookV2 to Base Testnet
# This script loads environment variables from .env and deploys the contract

set -e  # Exit on any error

echo "🚀 Deploying SwapbookV2 to Base Testnet..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "PRIVATE_KEY=0x..."
    echo "BASE_TESTNET_RPC=https://sepolia.base.org"
    echo "BASE_ETHERSCAN_API_KEY=your_api_key_here"
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

echo "✅ Environment variables loaded successfully"
echo "📍 RPC URL: $BASE_TESTNET_RPC"
echo "🔑 Private key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"

# Build the project first
echo "🔨 Building project..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful"

# Deploy the contract
echo "🚀 Deploying SwapbookV2 to Base Testnet..."

forge script script/0_DeploySwapbookV2.s.sol \
    --rpc-url "$BASE_TESTNET_RPC" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --chain base-sepolia \
    --gas-limit 10000000

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo "🎉 SwapbookV2 has been deployed to Base Testnet"
    echo "📋 Check the output above for the contract address"
else
    echo "❌ Deployment failed!"
    exit 1
fi
