#!/bin/bash

# Contract verification script using Etherscan V1 API
echo "🔍 Contract Verification Script using Etherscan API"
echo "=================================================="
echo ""
echo "Usage:"
echo "  $0 [contract_address] [source_file]"
echo ""
echo "Examples:"
echo "  $0  # Interactive mode - will prompt for both inputs"
echo "  $0 0x6146B40c9c495c093077CC5141C5A6Ef7768d2bA  # Prompt for source file"
echo "  $0 0x6146B40c9c495c093077CC5141C5A6Ef7768d2bA src/SwapbookAVS.sol:SwapbookAVS  # Both provided"
echo ""

# Load environment variables from .env file
if [ -f .env ]; then
    echo "📖 Loading environment variables from .env..."
    source .env
else
    echo "❌ Error: .env file not found!"
    exit 1
fi

# Check if BASE_ETHERSCAN_API_KEY is set
if [ -z "$BASE_ETHERSCAN_API_KEY" ]; then
    echo "❌ Error: BASE_ETHERSCAN_API_KEY not found in .env file!"
    exit 1
fi

echo "✅ API Key loaded successfully"
echo ""

# Get contract address from user input
if [ -z "$1" ]; then
    echo "📍 Please enter the contract address to verify:"
    read -p "Contract Address: " CONTRACT_ADDRESS
else
    CONTRACT_ADDRESS="$1"
    echo "📍 Using provided contract address: $CONTRACT_ADDRESS"
fi

# Validate contract address format (basic check)
if [[ ! $CONTRACT_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "❌ Error: Invalid contract address format!"
    echo "   Expected format: 0x followed by 40 hexadecimal characters"
    exit 1
fi

# Get source file path from user input
if [ -z "$2" ]; then
    echo "📄 Please enter the source file path (e.g., src/SwapbookAVS.sol:SwapbookAVS):"
    read -p "Source File: " SOURCE_FILE
else
    SOURCE_FILE="$2"
    echo "📄 Using provided source file: $SOURCE_FILE"
fi

# Validate source file exists
if [[ $SOURCE_FILE == *":"* ]]; then
    # Format: path:contract
    FILE_PATH=$(echo "$SOURCE_FILE" | cut -d':' -f1)
    CONTRACT_NAME=$(echo "$SOURCE_FILE" | cut -d':' -f2)
else
    # Just file path, try to extract contract name
    FILE_PATH="$SOURCE_FILE"
    CONTRACT_NAME="SwapbookAVS"  # Default fallback
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ Error: Source file not found: $FILE_PATH"
    echo "   Please check the file path and try again."
    exit 1
fi

echo "🌐 Network: Base Sepolia (Chain ID: 84532)"
echo "📁 Source File: $SOURCE_FILE"
echo ""

# Run the verification command
echo "🚀 Starting contract verification..."
forge verify-contract --watch --chain-id 84532 "$CONTRACT_ADDRESS" "$SOURCE_FILE" --verifier custom --verifier-url "https://api.etherscan.io/api" --verifier-api-key "$BASE_ETHERSCAN_API_KEY"

# Check the exit status
if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Contract verification completed successfully!"
    echo "🔗 View on Basescan: https://sepolia.basescan.org/address/$CONTRACT_ADDRESS"
else
    echo ""
    echo "❌ Contract verification failed!"
    echo "🔧 Please check the error messages above and try again."
    exit 1
fi