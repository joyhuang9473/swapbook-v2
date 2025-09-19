#!/bin/bash

# Mint Test Tokens script for SwapbookV2 + SwapbookAVS testing
# This script mints tokens from deployed test token contracts to a specified user

set -e  # Exit on any error

echo "🪙 Minting Test Tokens to User..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "PRIVATE_KEY=0x..."
    echo "BASE_TESTNET_RPC=https://sepolia.base.org"
    echo "TOKEN0_ADDRESS=0x..."
    echo "TOKEN1_ADDRESS=0x..."
    echo "USER_ADDRESS=0x..."
    echo "MINT_AMOUNT=1000000000000000000000"
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

if [ -z "$TOKEN0_ADDRESS" ]; then
    echo "❌ Error: TOKEN0_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$TOKEN1_ADDRESS" ]; then
    echo "❌ Error: TOKEN1_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$SWAPBOOK_USER_ADDRESS" ]; then
    echo "❌ Error: SWAPBOOK_USER_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$UNISWAP_USER_ADDRESS" ]; then
    echo "❌ Error: UNISWAP_USER_ADDRESS not found in .env file"
    exit 1
fi

if [ -z "$MINT_AMOUNT" ]; then
    echo "❌ Error: MINT_AMOUNT not found in .env file"
    echo "Please set MINT_AMOUNT in your .env file (e.g., 1000000000000000000000 for 1000 tokens)"
    exit 1
fi

echo "✅ Environment variables loaded successfully"
echo "📍 RPC URL: $BASE_TESTNET_RPC"
echo "🔑 Private key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"
echo "🏗️  Token0 address: $TOKEN0_ADDRESS"
echo "🏗️  Token1 address: $TOKEN1_ADDRESS"
echo "👤 User address: $USER_ADDRESS"
echo "💰 Mint amount per token: $MINT_AMOUNT"

# Note: forge script will compile only the necessary files
echo "🔨 Compiling script and dependencies..."

# Mint test tokens
echo "🚀 Minting test tokens to user..."

forge script script/4_MintTestTokens.s.sol \
    --rpc-url "$BASE_TESTNET_RPC" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --chain base-sepolia

if [ $? -eq 0 ]; then
    echo "✅ Test tokens minted successfully!"
    echo "🎉 User now has tokens for testing!"
    echo ""
    echo "📋 Minting Summary:"
    echo "1. ✅ Token0 minted to user"
    echo "2. ✅ Token1 minted to user"
    echo "3. ✅ User balances updated"
    echo ""
    echo "🚀 Next steps:"
    echo "- User can now place limit orders"
    echo "- User can participate in swap testing"
    echo "- Run integration tests with funded user"
else
    echo "❌ Token minting failed!"
    echo "Please check the logs above for details"
    exit 1
fi
