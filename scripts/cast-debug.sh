#!/bin/bash

# Cast-based On-Chain Debugging Script
# Provides quick commands to debug CCIP transactions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Chain RPC URLs
BASE_RPC="https://mainnet.base.org"
AVALANCHE_RPC="https://api.avax.network/ext/bc/C/rpc"

# Your contract addresses
BASE_YIELDMAX="0xe97978aB28f4d340494293a519B8Ba7Ab6E9640F"
AVALANCHE_YIELDMAX="0x379154D8C0b0B19B773f841554f7b7Ad445cA244"

echo -e "${BLUE}🔧 YieldMax CCIP On-Chain Debugger${NC}"
echo "=================================="

function usage() {
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  tx <chain> <tx_hash>                    - Debug transaction"
    echo "  receipt <chain> <tx_hash>               - Get transaction receipt"
    echo "  logs <chain> <tx_hash>                  - Decode transaction logs"
    echo "  check-contract <chain> <address>        - Check if address is a contract"
    echo "  check-token <chain> <token_address>     - Get token info"
    echo "  failed-messages <chain>                 - Check failed messages"
    echo "  executor-balance <chain> <executor>     - Check executor balance"
    echo "  ccip-events <chain> <block_range>       - Get CCIP events in block range"
    echo ""
    echo "Chains: base, avalanche"
    echo ""
    echo "Examples:"
    echo "  $0 tx base 0x1234..."
    echo "  $0 check-contract base 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"
    echo "  $0 failed-messages base"
    echo "  $0 ccip-events base 15000000:15000100"
}

function get_rpc() {
    case $1 in
        base)
            echo $BASE_RPC
            ;;
        avalanche)
            echo $AVALANCHE_RPC
            ;;
        *)
            echo -e "${RED}❌ Unknown chain: $1${NC}"
            exit 1
            ;;
    esac
}

function get_yieldmax_address() {
    case $1 in
        base)
            echo $BASE_YIELDMAX
            ;;
        avalanche)
            echo $AVALANCHE_YIELDMAX
            ;;
        *)
            echo -e "${RED}❌ Unknown chain: $1${NC}"
            exit 1
            ;;
    esac
}

function debug_transaction() {
    local chain=$1
    local tx_hash=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}🔍 Debugging transaction $tx_hash on $chain${NC}"
    echo ""
    
    # Get basic transaction info
    echo -e "${YELLOW}📋 Transaction Info:${NC}"
    cast tx $tx_hash --rpc-url $rpc
    echo ""
    
    # Get receipt
    echo -e "${YELLOW}📋 Transaction Receipt:${NC}"
    cast receipt $tx_hash --rpc-url $rpc
    echo ""
    
    # Decode logs
    echo -e "${YELLOW}📡 Decoded Logs:${NC}"
    decode_logs $chain $tx_hash
}

function get_receipt() {
    local chain=$1
    local tx_hash=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}📋 Transaction Receipt for $tx_hash on $chain${NC}"
    cast receipt $tx_hash --rpc-url $rpc
}

function decode_logs() {
    local chain=$1
    local tx_hash=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}📡 Decoding logs for $tx_hash on $chain${NC}"
    
    # Get receipt and extract logs
    local receipt=$(cast receipt $tx_hash --rpc-url $rpc --json 2>/dev/null)
    
    if [ -z "$receipt" ] || [ "$receipt" = "null" ]; then
        echo -e "${RED}❌ Could not get transaction receipt${NC}"
        return 1
    fi
    
    # Extract block number safely
    local block_number=$(echo "$receipt" | jq -r '.blockNumber // empty' 2>/dev/null)
    
    if [ -z "$block_number" ] || [ "$block_number" = "null" ] || [ "$block_number" = "empty" ]; then
        echo -e "${RED}❌ Could not extract block number from receipt${NC}"
        return 1
    fi
    
    # YieldMax event signatures
    local executor_created="ExecutorCreated(address,address,uint256)"
    local executor_executed="ExecutorExecuted(address,bool)"
    local cross_tx_executed="CrossTxExecuted(address,address,uint256,bytes)"
    local erc20_received="ERC20Received(address,address,uint256)"
    local message_failed="MessageFailed(bytes32,bytes)"
    
    echo "Attempting to decode YieldMax events from block $block_number..."
    
    # Try to decode each event type
    cast logs --from-block $block_number \
             --to-block $block_number \
             --address $(get_yieldmax_address $chain) \
             --rpc-url $rpc \
             "$executor_created" "$executor_executed" "$cross_tx_executed" "$erc20_received" "$message_failed" 2>/dev/null || echo "No events found or error occurred"
}

function check_contract() {
    local chain=$1
    local address=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}🔍 Checking contract $address on $chain${NC}"
    
    # Check if it has code
    local code=$(cast code $address --rpc-url $rpc)
    
    if [ "$code" = "0x" ]; then
        echo -e "${RED}❌ Address has no code (EOA or non-deployed contract)${NC}"
    else
        echo -e "${GREEN}✅ Address is a contract${NC}"
        echo "Code length: $((${#code} / 2 - 1)) bytes"
        
        # Try to get token info if it's an ERC20
        echo ""
        echo -e "${YELLOW}🔍 Checking if it's an ERC20 token:${NC}"
        
        # Try name()
        local name=$(cast call $address "name()(string)" --rpc-url $rpc 2>/dev/null || echo "N/A")
        local symbol=$(cast call $address "symbol()(string)" --rpc-url $rpc 2>/dev/null || echo "N/A")
        local decimals=$(cast call $address "decimals()(uint8)" --rpc-url $rpc 2>/dev/null || echo "N/A")
        
        if [ "$name" != "N/A" ] && [ "$symbol" != "N/A" ]; then
            echo -e "${GREEN}📄 Token Info: $name ($symbol) - $decimals decimals${NC}"
        else
            echo -e "${YELLOW}📄 Not a standard ERC20 token${NC}"
        fi
    fi
}

function check_token() {
    local chain=$1
    local token_address=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}🪙 Token info for $token_address on $chain${NC}"
    
    # Get token details
    local name=$(cast call $token_address "name()(string)" --rpc-url $rpc 2>/dev/null || echo "Unknown")
    local symbol=$(cast call $token_address "symbol()(string)" --rpc-url $rpc 2>/dev/null || echo "Unknown")
    local decimals=$(cast call $token_address "decimals()(uint8)" --rpc-url $rpc 2>/dev/null || echo "0")
    local total_supply=$(cast call $token_address "totalSupply()(uint256)" --rpc-url $rpc 2>/dev/null || echo "0")
    
    echo "Name: $name"
    echo "Symbol: $symbol"
    echo "Decimals: $decimals"
    echo "Total Supply: $total_supply"
}

function check_failed_messages() {
    local chain=$1
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}📋 Checking failed messages on $chain${NC}"
    
    # Call getFailedMessages(0, 10)
    local result=$(cast call $yieldmax "getFailedMessages(uint256,uint256)" 0 10 --rpc-url $rpc 2>/dev/null || echo "Failed to call")
    
    if [ "$result" = "Failed to call" ]; then
        echo -e "${RED}❌ Could not retrieve failed messages${NC}"
    else
        echo "Failed messages result: $result"
        # Note: You'd need to decode this properly - it's a complex tuple array
    fi
}

function check_executor_balance() {
    local chain=$1
    local executor=$2
    local rpc=$(get_rpc $chain)
    
    echo -e "${BLUE}💰 Executor balance for $executor on $chain${NC}"
    
    # Get ETH balance
    local eth_balance=$(cast balance $executor --rpc-url $rpc)
    echo "ETH Balance: $(cast --to-unit $eth_balance ether) ETH"
    
    # Check if executor still has code
    local code=$(cast code $executor --rpc-url $rpc)
    if [ "$code" = "0x" ]; then
        echo -e "${GREEN}✅ Executor self-destructed (normal cleanup)${NC}"
    else
        echo -e "${YELLOW}⚠️  Executor still exists${NC}"
    fi
}

function get_ccip_events() {
    local chain=$1
    local block_range=$2
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}📡 Getting CCIP events for block range $block_range on $chain${NC}"
    
    # Split block range
    local from_block=$(echo $block_range | cut -d':' -f1)
    local to_block=$(echo $block_range | cut -d':' -f2)
    
    echo "Searching blocks $from_block to $to_block..."
    
    # Get all events from YieldMax contract
    cast logs --from-block $from_block \
             --to-block $to_block \
             --address $yieldmax \
             --rpc-url $rpc || true
}

# Main command dispatcher
case $1 in
    tx)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 tx <chain> <tx_hash>${NC}"
            exit 1
        fi
        debug_transaction $2 $3
        ;;
    receipt)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 receipt <chain> <tx_hash>${NC}"
            exit 1
        fi
        get_receipt $2 $3
        ;;
    logs)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 logs <chain> <tx_hash>${NC}"
            exit 1
        fi
        decode_logs $2 $3
        ;;
    check-contract)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 check-contract <chain> <address>${NC}"
            exit 1
        fi
        check_contract $2 $3
        ;;
    check-token)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 check-token <chain> <token_address>${NC}"
            exit 1
        fi
        check_token $2 $3
        ;;
    failed-messages)
        if [ $# -ne 2 ]; then
            echo -e "${RED}Usage: $0 failed-messages <chain>${NC}"
            exit 1
        fi
        check_failed_messages $2
        ;;
    executor-balance)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 executor-balance <chain> <executor>${NC}"
            exit 1
        fi
        check_executor_balance $2 $3
        ;;
    ccip-events)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 ccip-events <chain> <block_range>${NC}"
            echo -e "${RED}Example: $0 ccip-events base 15000000:15000100${NC}"
            exit 1
        fi
        get_ccip_events $2 $3
        ;;
    *)
        usage
        exit 1
        ;;
esac 