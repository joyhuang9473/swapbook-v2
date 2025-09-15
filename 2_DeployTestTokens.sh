#!/bin/bash

# Deploy Test Tokens script for SwapbookV2 + SwapbookAVS testing
# This script deploys MockERC20 tokens and mints them to test users

set -e  # Exit on any error

echo "🪙 Deploying Test Tokens for SwapbookV2 + SwapbookAVS Testing..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "PRIVATE_KEY=0x..."
    echo "BASE_TESTNET_RPC=https://sepolia.base.org"
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

# Deploy test tokens
echo "🚀 Deploying test tokens..."

forge script script/3_DeployTestTokens.s.sol \
    --rpc-url "$BASE_TESTNET_RPC" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --chain base-sepolia

if [ $? -eq 0 ]; then
    echo "✅ Test tokens deployed successfully!"
    echo "🎉 Test tokens are now ready for use!"
    echo ""
    echo "📋 Deployment Summary:"
    echo "1. ✅ Token0 deployed"
    echo "2. ✅ Token1 deployed"
    echo "3. ✅ Token addresses ready for use"
    echo ""
    echo "🚀 Next steps:"
    echo "- Use these token addresses in your integration tests"
    echo "- Mint tokens to test users as needed"
    echo "- Run integration tests with the deployed tokens"
else
    echo "❌ Test token deployment failed!"
    echo "Please check the logs above for details"
    exit 1
fi
