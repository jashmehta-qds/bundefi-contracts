#!/bin/bash

# YieldMax ABI-based Event Decoder
# Uses the complete YieldMax contract ABI to decode all events properly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Chain RPC URLs
BASE_RPC="https://mainnet.base.org"
AVALANCHE_RPC="https://api.avax.network/ext/bc/C/rpc"

# Your contract addresses
BASE_YIELDMAX="0xe97978aB28f4d340494293a519B8Ba7Ab6E9640F"
AVALANCHE_YIELDMAX="0x8f843aC68EC028D8A1be023124b62f0096a6A19a"

echo -e "${BLUE}🔧 YieldMax ABI Event Decoder${NC}"
echo "====================================="

function usage() {
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  decode-tx <chain> <tx_hash>              - Decode all YieldMax events in transaction"
    echo "  decode-logs <chain> <from_block> <to_block> - Decode YieldMax events in block range"
    echo "  watch-events <chain>                     - Watch for new YieldMax events (latest 100 blocks)"
    echo "  decode-specific <chain> <tx_hash> <event> - Decode specific event type only"
    echo "  check-escrow <chain> <user_address>      - Check user's escrow balances"
    echo "  check-allowlist <chain> <chain_selector> - Check if chain is allowlisted"
    echo ""
    echo "Chains: base, avalanche"
    echo "Events: CrossTxExecuted, ExecutorCreated, ExecutorExecuted, ERC20Received, MessageFailed, MessageRecovered, EscrowRescued, ERC20EscrowRescued, OwnershipTransferred"
    echo ""
    echo "Examples:"
    echo "  $0 decode-tx base 0x1234..."
    echo "  $0 decode-logs base 15000000 15000100"
    echo "  $0 watch-events base"
    echo "  $0 decode-specific base 0x1234... ExecutorCreated"
    echo "  $0 check-escrow base 0x1958E5D7477ed777390e7034A9CC9719632838C3"
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

function decode_transaction_events() {
    local chain=$1
    local tx_hash=$2
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}🔍 Decoding YieldMax events in transaction $tx_hash on $chain${NC}"
    echo ""
    
    # Get transaction receipt to extract block number
    local receipt=$(cast receipt $tx_hash --rpc-url $rpc --json 2>/dev/null)
    
    if [ -z "$receipt" ] || [ "$receipt" = "null" ]; then
        echo -e "${RED}❌ Could not get transaction receipt${NC}"
        return 1
    fi
    
    local block_number=$(echo "$receipt" | jq -r '.blockNumber // empty' 2>/dev/null)
    
    if [ -z "$block_number" ] || [ "$block_number" = "null" ] || [ "$block_number" = "empty" ]; then
        echo -e "${RED}❌ Transaction not found or still pending${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}📋 Transaction Block: $block_number${NC}"
    echo ""
    
    # Decode each event type
    decode_all_events $chain $block_number $block_number $yieldmax
}

function decode_logs_range() {
    local chain=$1
    local from_block=$2
    local to_block=$3
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}📡 Decoding YieldMax events from block $from_block to $to_block on $chain${NC}"
    echo ""
    
    decode_all_events $chain $from_block $to_block $yieldmax
}

function decode_all_events() {
    local chain=$1
    local from_block=$2
    local to_block=$3
    local yieldmax=$4
    local rpc=$(get_rpc $chain)
    
    # Event signatures with proper formatting
    local events=(
        "CrossTxExecuted(address,address,uint256,bytes)"
        "EscrowRescued(address,uint256)"
        "ERC20EscrowRescued(address,address,uint256)"
        "ERC20Received(address,address,uint256)"
        "ExecutorCreated(address,address,uint256)"
        "ExecutorExecuted(address,bool)"
        "MessageFailed(bytes32,bytes)"
        "MessageRecovered(bytes32)"
        "OwnershipTransferred(address,address)"
    )
    
    local event_count=0
    
    for event in "${events[@]}"; do
        echo -e "${CYAN}🎯 Searching for $event events...${NC}"
        
        local logs=$(cast logs \
            --from-block $from_block \
            --to-block $to_block \
            --address $yieldmax \
            --rpc-url $rpc \
            "$event" 2>/dev/null || echo "")
        
        if [ -n "$logs" ] && [ "$logs" != "[]" ]; then
            echo -e "${GREEN}✅ Found $event events:${NC}"
            echo "$logs" | jq -r '.[] | "  Block: \(.blockNumber) | TxHash: \(.transactionHash) | Data: \(.data)"' 2>/dev/null || echo "  $logs"
            echo ""
            ((event_count++))
        fi
    done
    
    if [ $event_count -eq 0 ]; then
        echo -e "${YELLOW}ℹ️  No YieldMax events found in the specified range${NC}"
    else
        echo -e "${GREEN}📊 Found events from $event_count different event types${NC}"
    fi
}

function watch_events() {
    local chain=$1
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}👀 Watching for new YieldMax events on $chain${NC}"
    echo ""
    
    # Get current block
    local current_block=$(cast block-number --rpc-url $rpc)
    local from_block=64438469
    
    echo -e "${YELLOW}📍 Watching from block $from_block to latest${NC}"
    echo ""
    
    decode_all_events $chain $from_block $current_block $yieldmax
}

function decode_specific_event() {
    local chain=$1
    local tx_hash=$2
    local event_name=$3
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}🎯 Decoding $event_name events in transaction $tx_hash on $chain${NC}"
    echo ""
    
    # Get transaction receipt to extract block number
    local receipt=$(cast receipt $tx_hash --rpc-url $rpc --json 2>/dev/null)
    
    if [ -z "$receipt" ] || [ "$receipt" = "null" ]; then
        echo -e "${RED}❌ Could not get transaction receipt${NC}"
        return 1
    fi
    
    local block_number=$(echo "$receipt" | jq -r '.blockNumber // empty' 2>/dev/null)
    
    if [ -z "$block_number" ] || [ "$block_number" = "null" ] || [ "$block_number" = "empty" ]; then
        echo -e "${RED}❌ Transaction not found or still pending${NC}"
        return 1
    fi
    
    # Map event names to signatures
    local event_sig=""
    case $event_name in
        "CrossTxExecuted")
            event_sig="CrossTxExecuted(address,address,uint256,bytes)"
            ;;
        "EscrowRescued")
            event_sig="EscrowRescued(address,uint256)"
            ;;
        "ERC20EscrowRescued")
            event_sig="ERC20EscrowRescued(address,address,uint256)"
            ;;
        "ERC20Received")
            event_sig="ERC20Received(address,address,uint256)"
            ;;
        "ExecutorCreated")
            event_sig="ExecutorCreated(address,address,uint256)"
            ;;
        "ExecutorExecuted")
            event_sig="ExecutorExecuted(address,bool)"
            ;;
        "MessageFailed")
            event_sig="MessageFailed(bytes32,bytes)"
            ;;
        "MessageRecovered")
            event_sig="MessageRecovered(bytes32)"
            ;;
        "OwnershipTransferred")
            event_sig="OwnershipTransferred(address,address)"
            ;;
        *)
            echo -e "${RED}❌ Unknown event: $event_name${NC}"
            echo "Available events: CrossTxExecuted, EscrowRescued, ERC20EscrowRescued, ERC20Received, ExecutorCreated, ExecutorExecuted, MessageFailed, MessageRecovered, OwnershipTransferred"
            return 1
            ;;
    esac
    
    echo -e "${CYAN}🔍 Searching for $event_sig in block $block_number...${NC}"
    
    local logs=$(cast logs \
        --from-block $block_number \
        --to-block $block_number \
        --address $yieldmax \
        --rpc-url $rpc \
        "$event_sig" 2>/dev/null || echo "")
    
    if [ -n "$logs" ] && [ "$logs" != "[]" ]; then
        echo -e "${GREEN}✅ Found $event_name events:${NC}"
        echo "$logs" | jq '.' 2>/dev/null || echo "$logs"
    else
        echo -e "${YELLOW}ℹ️  No $event_name events found in transaction${NC}"
    fi
}

function check_escrow() {
    local chain=$1
    local user_address=$2
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}💰 Checking escrow balances for $user_address on $chain${NC}"
    echo ""
    
    # Check native ETH escrow
    local native_escrow=$(cast call $yieldmax "pendingEscrowNative(address)" $user_address --rpc-url $rpc 2>/dev/null || echo "0")
    local native_escrow_eth=$(cast --to-unit $native_escrow ether)
    
    echo -e "${YELLOW}📊 Escrow Balances:${NC}"
    echo "Native ETH: $native_escrow_eth ETH ($native_escrow wei)"
    
    # Note: ERC20 escrow requires token address, so we'll show how to check it
    echo ""
    echo -e "${CYAN}ℹ️  To check ERC20 escrow for a specific token:${NC}"
    echo "cast call $yieldmax \"pendingEscrowERC20(address,address)\" $user_address <TOKEN_ADDRESS> --rpc-url $rpc"
}

function check_allowlist() {
    local chain=$1
    local chain_selector=$2
    local rpc=$(get_rpc $chain)
    local yieldmax=$(get_yieldmax_address $chain)
    
    echo -e "${BLUE}🔒 Checking allowlist status for chain selector $chain_selector on $chain${NC}"
    echo ""
    
    # Check destination chain allowlist
    local dest_allowed=$(cast call $yieldmax "allowlistedDestinationChains(uint64)" $chain_selector --rpc-url $rpc 2>/dev/null || echo "false")
    
    # Check source chain allowlist  
    local source_allowed=$(cast call $yieldmax "allowlistedSourceChains(uint64)" $chain_selector --rpc-url $rpc 2>/dev/null || echo "false")
    
    echo -e "${YELLOW}📊 Allowlist Status:${NC}"
    echo "Destination Chain: $([ "$dest_allowed" = "true" ] && echo -e "${GREEN}✅ Allowed${NC}" || echo -e "${RED}❌ Not Allowed${NC}")"
    echo "Source Chain: $([ "$source_allowed" = "true" ] && echo -e "${GREEN}✅ Allowed${NC}" || echo -e "${RED}❌ Not Allowed${NC}")"
    
    # Show common chain selectors for reference
    echo ""
    echo -e "${CYAN}ℹ️  Common Chain Selectors:${NC}"
    echo "Base Mainnet: 15971525489660198786"
    echo "Avalanche: 6433500567565415381"
    echo "Ethereum: 5009297550715157269"
    echo "Polygon: 4051577828743386545"
}

# Main command dispatcher
case $1 in
    decode-tx)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 decode-tx <chain> <tx_hash>${NC}"
            exit 1
        fi
        decode_transaction_events $2 $3
        ;;
    decode-logs)
        if [ $# -ne 4 ]; then
            echo -e "${RED}Usage: $0 decode-logs <chain> <from_block> <to_block>${NC}"
            exit 1
        fi
        decode_logs_range $2 $3 $4
        ;;
    watch-events)
        if [ $# -ne 2 ]; then
            echo -e "${RED}Usage: $0 watch-events <chain>${NC}"
            exit 1
        fi
        watch_events $2
        ;;
    decode-specific)
        if [ $# -ne 4 ]; then
            echo -e "${RED}Usage: $0 decode-specific <chain> <tx_hash> <event>${NC}"
            exit 1
        fi
        decode_specific_event $2 $3 $4
        ;;
    check-escrow)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 check-escrow <chain> <user_address>${NC}"
            exit 1
        fi
        check_escrow $2 $3
        ;;
    check-allowlist)
        if [ $# -ne 3 ]; then
            echo -e "${RED}Usage: $0 check-allowlist <chain> <chain_selector>${NC}"
            exit 1
        fi
        check_allowlist $2 $3
        ;;
    *)
        usage
        exit 1
        ;;
esac 