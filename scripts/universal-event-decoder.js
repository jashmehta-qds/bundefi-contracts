#!/usr/bin/env node

const { ethers } = require('ethers');

/**
 * Universal Event Decoder for YieldMax Contract
 * Uses the complete contract ABI to decode all events with proper formatting
 */

class UniversalEventDecoder {
    constructor(rpcUrl, chainName, contractAddress) {
        this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
        this.chainName = chainName;
        this.contractAddress = contractAddress;
        
        // Complete YieldMax Contract ABI with all events and functions
        this.contractABI = [
            // Events
            "event CrossTxExecuted(address indexed sender, address indexed target, uint256 value, bytes data)",
            "event EscrowRescued(address indexed user, uint256 amount)",
            "event ERC20EscrowRescued(address indexed user, address token, uint256 amount)",
            "event ERC20Received(address indexed token, address indexed sender, uint256 amount)",
            "event ExecutorCreated(address indexed executor, address indexed target, uint256 deadline)",
            "event ExecutorExecuted(address indexed executor, bool success)",
            "event MessageFailed(bytes32 indexed messageId, bytes reason)",
            "event MessageRecovered(bytes32 indexed messageId)",
            "event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)",
            
            // Functions for additional context
            "function allowlistedDestinationChains(uint64) external view returns (bool)",
            "function allowlistedSourceChains(uint64) external view returns (bool)",
            "function owner() external view returns (address)",
            "function pendingEscrowNative(address) external view returns (uint256)",
            "function pendingEscrowERC20(address, address) external view returns (uint256)",
            "function getFailedMessages(uint256 offset, uint256 limit) external view returns (tuple(bytes32 messageId, uint8 errorCode)[] memory)",
            "function usedPayloads(bytes32) external view returns (bool)"
        ];
        
        this.contract = new ethers.Contract(contractAddress, this.contractABI, this.provider);
        this.interface = new ethers.utils.Interface(this.contractABI);
        
        // ERC20 ABI for token info
        this.erc20ABI = [
            "function name() external view returns (string)",
            "function symbol() external view returns (string)",
            "function decimals() external view returns (uint8)"
        ];
    }

    async decodeTransactionEvents(txHash) {
        console.log(`\n🔍 Decoding Events for Transaction: ${txHash}`);
        console.log(`📍 Chain: ${this.chainName}`);
        console.log(`📋 Contract: ${this.contractAddress}\n`);

        try {
            const receipt = await this.provider.getTransactionReceipt(txHash);
            if (!receipt) {
                console.log("❌ Transaction not found or still pending");
                return;
            }

            console.log("📊 Transaction Summary:");
            console.log(`   Status: ${receipt.status === 1 ? '✅ Success' : '❌ Failed'}`);
            console.log(`   Block: ${receipt.blockNumber}`);
            console.log(`   Gas Used: ${receipt.gasUsed.toString()}`);
            console.log(`   From: ${receipt.from}`);
            console.log(`   To: ${receipt.to}\n`);

            await this.analyzeEvents(receipt.logs, receipt.blockNumber);

        } catch (error) {
            console.error("❌ Error decoding transaction:", error.message);
        }
    }

    async decodeBlockRangeEvents(fromBlock, toBlock) {
        console.log(`\n📡 Decoding Events from Block ${fromBlock} to ${toBlock}`);
        console.log(`📍 Chain: ${this.chainName}`);
        console.log(`📋 Contract: ${this.contractAddress}\n`);

        try {
            const filter = {
                address: this.contractAddress,
                fromBlock: fromBlock,
                toBlock: toBlock
            };

            const logs = await this.provider.getLogs(filter);
            
            if (logs.length === 0) {
                console.log("ℹ️  No events found in the specified block range");
                return;
            }

            console.log(`📊 Found ${logs.length} total logs\n`);
            await this.analyzeEvents(logs);

        } catch (error) {
            console.error("❌ Error decoding block range:", error.message);
        }
    }

    async watchRecentEvents(blockCount = 100) {
        console.log(`\n👀 Watching Recent Events (Last ${blockCount} blocks)`);
        console.log(`📍 Chain: ${this.chainName}`);
        console.log(`📋 Contract: ${this.contractAddress}\n`);

        try {
            const currentBlock = await this.provider.getBlockNumber();
            const fromBlock = Math.max(0, currentBlock - blockCount);
            
            console.log(`📍 Scanning blocks ${fromBlock} to ${currentBlock}\n`);
            
            await this.decodeBlockRangeEvents(fromBlock, currentBlock);

        } catch (error) {
            console.error("❌ Error watching events:", error.message);
        }
    }

    async analyzeEvents(logs, specificBlock = null) {
        const eventsByType = {};
        let decodedCount = 0;
        let unknownCount = 0;

        for (const log of logs) {
            // Only process logs from our contract
            if (log.address.toLowerCase() !== this.contractAddress.toLowerCase()) {
                continue;
            }

            try {
                const parsed = this.interface.parseLog(log);
                decodedCount++;

                if (!eventsByType[parsed.name]) {
                    eventsByType[parsed.name] = [];
                }

                eventsByType[parsed.name].push({
                    log,
                    parsed,
                    blockNumber: log.blockNumber,
                    transactionHash: log.transactionHash
                });

            } catch (error) {
                unknownCount++;
                console.log(`❓ Unknown event in tx ${log.transactionHash}: ${log.topics[0]}`);
            }
        }

        if (decodedCount === 0) {
            console.log("ℹ️  No YieldMax events found");
            return;
        }

        console.log(`📊 Event Summary: ${decodedCount} decoded, ${unknownCount} unknown\n`);

        // Process each event type
        for (const [eventName, events] of Object.entries(eventsByType)) {
            console.log(`🎯 ${eventName} Events (${events.length}):`);
            console.log("=" + "=".repeat(eventName.length + 15));

            for (const eventData of events) {
                await this.formatEvent(eventData);
                console.log("");
            }
        }
    }

    async formatEvent(eventData) {
        const { parsed, log, blockNumber, transactionHash } = eventData;
        const timestamp = await this.getBlockTimestamp(blockNumber);

        console.log(`   📍 Block: ${blockNumber} | Tx: ${transactionHash}`);
        console.log(`   ⏰ Time: ${new Date(timestamp * 1000).toISOString()}`);

        switch (parsed.name) {
            case 'CrossTxExecuted':
                console.log(`   👤 Sender: ${parsed.args.sender}`);
                console.log(`   🎯 Target: ${parsed.args.target}`);
                console.log(`   💰 Value: ${ethers.utils.formatEther(parsed.args.value)} ETH`);
                console.log(`   📝 Data: ${parsed.args.data}`);
                
                // Check if target is a contract
                await this.checkTargetContract(parsed.args.target);
                break;

            case 'ExecutorCreated':
                console.log(`   ⚙️  Executor: ${parsed.args.executor}`);
                console.log(`   🎯 Target: ${parsed.args.target}`);
                console.log(`   ⏳ Deadline: ${new Date(parsed.args.deadline * 1000).toISOString()}`);
                
                // Check target contract and executor status
                await this.checkTargetContract(parsed.args.target);
                await this.checkExecutorStatus(parsed.args.executor);
                break;

            case 'ExecutorExecuted':
                console.log(`   ⚙️  Executor: ${parsed.args.executor}`);
                console.log(`   ✅ Success: ${parsed.args.success ? '✅ Yes' : '❌ No'}`);
                
                if (!parsed.args.success) {
                    console.log(`   ⚠️  Execution failed - check executor for remaining assets`);
                }
                break;

            case 'ERC20Received':
                console.log(`   🪙 Token: ${parsed.args.token}`);
                console.log(`   👤 Sender: ${parsed.args.sender}`);
                console.log(`   💰 Amount: ${parsed.args.amount.toString()}`);
                
                // Get token info
                await this.getTokenInfo(parsed.args.token, parsed.args.amount);
                break;

            case 'MessageFailed':
                console.log(`   📨 Message ID: ${parsed.args.messageId}`);
                console.log(`   ❌ Reason: ${parsed.args.reason}`);
                console.log(`   🔧 Recovery: Owner can use retryFailedMessage()`);
                break;

            case 'MessageRecovered':
                console.log(`   📨 Message ID: ${parsed.args.messageId}`);
                console.log(`   ✅ Status: Successfully recovered by owner`);
                break;

            case 'EscrowRescued':
                console.log(`   👤 User: ${parsed.args.user}`);
                console.log(`   💰 Amount: ${ethers.utils.formatEther(parsed.args.amount)} ETH`);
                break;

            case 'ERC20EscrowRescued':
                console.log(`   👤 User: ${parsed.args.user}`);
                console.log(`   🪙 Token: ${parsed.args.token}`);
                console.log(`   💰 Amount: ${parsed.args.amount.toString()}`);
                
                // Get token info
                await this.getTokenInfo(parsed.args.token, parsed.args.amount);
                break;

            case 'OwnershipTransferred':
                console.log(`   👤 Previous Owner: ${parsed.args.previousOwner}`);
                console.log(`   👤 New Owner: ${parsed.args.newOwner}`);
                break;

            default:
                console.log(`   📝 Raw args:`, parsed.args);
        }
    }

    async checkTargetContract(address) {
        try {
            const code = await this.provider.getCode(address);
            if (code === '0x') {
                console.log(`   ⚠️  Target ${address} has no code (EOA or non-deployed)`);
            } else {
                console.log(`   ✅ Target ${address} is a valid contract`);
                
                // Try to identify if it's an ERC20
                try {
                    const contract = new ethers.Contract(address, this.erc20ABI, this.provider);
                    const [name, symbol] = await Promise.all([
                        contract.name().catch(() => null),
                        contract.symbol().catch(() => null)
                    ]);
                    
                    if (name && symbol) {
                        console.log(`   📄 Token: ${name} (${symbol})`);
                    }
                } catch (error) {
                    // Not an ERC20, that's fine
                }
            }
        } catch (error) {
            console.log(`   ❓ Could not check target contract: ${error.message}`);
        }
    }

    async checkExecutorStatus(executorAddress) {
        try {
            const [code, balance] = await Promise.all([
                this.provider.getCode(executorAddress),
                this.provider.getBalance(executorAddress)
            ]);

            if (code === '0x') {
                console.log(`   ✅ Executor self-destructed (normal cleanup)`);
            } else {
                console.log(`   ⚠️  Executor still exists`);
            }

            if (balance.gt(0)) {
                console.log(`   💰 Executor balance: ${ethers.utils.formatEther(balance)} ETH`);
            }
        } catch (error) {
            console.log(`   ❓ Could not check executor status: ${error.message}`);
        }
    }

    async getTokenInfo(tokenAddress, amount) {
        try {
            const contract = new ethers.Contract(tokenAddress, this.erc20ABI, this.provider);
            const [name, symbol, decimals] = await Promise.all([
                contract.name(),
                contract.symbol(),
                contract.decimals()
            ]);

            const formattedAmount = ethers.utils.formatUnits(amount, decimals);
            console.log(`   📄 ${formattedAmount} ${symbol} (${name})`);
        } catch (error) {
            console.log(`   📄 Token info unavailable for ${tokenAddress}`);
        }
    }

    async getBlockTimestamp(blockNumber) {
        try {
            const block = await this.provider.getBlock(blockNumber);
            return block.timestamp;
        } catch (error) {
            return Math.floor(Date.now() / 1000); // Fallback to current time
        }
    }

    async getContractInfo() {
        console.log(`\n📋 Contract Information`);
        console.log(`📍 Chain: ${this.chainName}`);
        console.log(`📋 Address: ${this.contractAddress}\n`);

        try {
            const [owner, currentBlock] = await Promise.all([
                this.contract.owner(),
                this.provider.getBlockNumber()
            ]);

            console.log(`👤 Owner: ${owner}`);
            console.log(`📊 Current Block: ${currentBlock}`);

            // Check failed messages
            try {
                const failedMessages = await this.contract.getFailedMessages(0, 10);
                console.log(`❌ Failed Messages: ${failedMessages.length}`);
                
                if (failedMessages.length > 0) {
                    console.log(`   Recent failed message IDs:`);
                    failedMessages.slice(0, 3).forEach((msg, i) => {
                        console.log(`   ${i + 1}. ${msg.messageId}`);
                    });
                }
            } catch (error) {
                console.log(`❌ Could not fetch failed messages: ${error.message}`);
            }

        } catch (error) {
            console.error("❌ Error getting contract info:", error.message);
        }
    }
}

// CLI Usage
async function main() {
    const args = process.argv.slice(2);
    
    if (args.length < 1) {
        console.log(`
🔍 Universal YieldMax Event Decoder

Usage: node universal-event-decoder.js <command> [args...]

Commands:
  decode-tx <chain> <tx_hash>                    - Decode events in transaction
  decode-range <chain> <from_block> <to_block>   - Decode events in block range  
  watch <chain> [block_count]                    - Watch recent events (default: 100 blocks)
  info <chain>                                   - Show contract information

Chains:
  base       - Base Mainnet
  avalanche  - Avalanche C-Chain

Examples:
  node universal-event-decoder.js decode-tx base 0x1234...
  node universal-event-decoder.js decode-range base 15000000 15000100
  node universal-event-decoder.js watch base 50
  node universal-event-decoder.js info base
        `);
        process.exit(1);
    }

    const command = args[0];
    
    // Chain configurations
    const chains = {
        base: {
            rpc: 'https://mainnet.base.org',
            contract: '0xe97978aB28f4d340494293a519B8Ba7Ab6E9640F',
            name: 'Base Mainnet'
        },
        avalanche: {
            rpc: 'https://api.avax.network/ext/bc/C/rpc',
            contract: '0x379154D8C0b0B19B773f841554f7b7Ad445cA244',
            name: 'Avalanche C-Chain'
        }
    };

    switch (command) {
        case 'decode-tx':
            if (args.length !== 3) {
                console.error('Usage: decode-tx <chain> <tx_hash>');
                process.exit(1);
            }
            const [, chain1, txHash] = args;
            if (!chains[chain1]) {
                console.error(`Unknown chain: ${chain1}`);
                process.exit(1);
            }
            const decoder1 = new UniversalEventDecoder(
                chains[chain1].rpc,
                chains[chain1].name,
                chains[chain1].contract
            );
            await decoder1.decodeTransactionEvents(txHash);
            break;

        case 'decode-range':
            if (args.length !== 4) {
                console.error('Usage: decode-range <chain> <from_block> <to_block>');
                process.exit(1);
            }
            const [, chain2, fromBlock, toBlock] = args;
            if (!chains[chain2]) {
                console.error(`Unknown chain: ${chain2}`);
                process.exit(1);
            }
            const decoder2 = new UniversalEventDecoder(
                chains[chain2].rpc,
                chains[chain2].name,
                chains[chain2].contract
            );
            await decoder2.decodeBlockRangeEvents(parseInt(fromBlock), parseInt(toBlock));
            break;

        case 'watch':
            if (args.length < 2 || args.length > 3) {
                console.error('Usage: watch <chain> [block_count]');
                process.exit(1);
            }
            const [, chain3, blockCountStr] = args;
            const blockCount = blockCountStr ? parseInt(blockCountStr) : 100;
            if (!chains[chain3]) {
                console.error(`Unknown chain: ${chain3}`);
                process.exit(1);
            }
            const decoder3 = new UniversalEventDecoder(
                chains[chain3].rpc,
                chains[chain3].name,
                chains[chain3].contract
            );
            await decoder3.watchRecentEvents(blockCount);
            break;

        case 'info':
            if (args.length !== 2) {
                console.error('Usage: info <chain>');
                process.exit(1);
            }
            const [, chain4] = args;
            if (!chains[chain4]) {
                console.error(`Unknown chain: ${chain4}`);
                process.exit(1);
            }
            const decoder4 = new UniversalEventDecoder(
                chains[chain4].rpc,
                chains[chain4].name,
                chains[chain4].contract
            );
            await decoder4.getContractInfo();
            break;

        default:
            console.error(`Unknown command: ${command}`);
            process.exit(1);
    }
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { UniversalEventDecoder }; 