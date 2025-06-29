#!/usr/bin/env node

const { ethers } = require('ethers');

/**
 * On-Chain Transaction Debugger
 * Helps debug CCIP cross-chain executions and executor failures
 */

class OnChainDebugger {
    constructor(rpcUrl, chainName) {
        this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
        this.chainName = chainName;
        
        // Complete YieldMax ABI with all events and functions
        this.yieldMaxABI = [
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
            
            // Functions
            "function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external",
            "function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external",
            "function allowlistedDestinationChains(uint64) external view returns (bool)",
            "function allowlistedSourceChains(uint64) external view returns (bool)",
            "function emergencyWithdraw(address beneficiary) external",
            "function emergencyWithdrawToken(address beneficiary, address token) external",
            "function estimateFee(uint64 destinationChainSelector, address receiver, address targetContract, uint256 value, address[] calldata tokenAddresses, uint256[] calldata tokenAmounts, bytes calldata callData) external view returns (uint256)",
            "function getFailedMessages(uint256 offset, uint256 limit) external view returns (tuple(bytes32 messageId, uint8 errorCode)[] memory)",
            "function owner() external view returns (address)",
            "function pendingEscrowNative(address) external view returns (uint256)",
            "function pendingEscrowERC20(address, address) external view returns (uint256)",
            "function rescueEscrow() external",
            "function rescueERC20Escrow(address token) external",
            "function retryFailedMessage(bytes32 messageId, address tokenReceiver) external",
            "function sendCrossChainExecution(uint64 destinationChainSelector, address receiver, address targetContract, uint256 value, address[] calldata tokenAddresses, uint256[] calldata tokenAmounts, bytes calldata callData) external payable",
            "function transferOwnership(address newOwner) external",
            "function usedPayloads(bytes32) external view returns (bool)"
        ];
        
        this.erc20ABI = [
            "function balanceOf(address) external view returns (uint256)",
            "function transfer(address to, uint256 amount) external returns (bool)",
            "function name() external view returns (string)",
            "function symbol() external view returns (string)",
            "function decimals() external view returns (uint8)"
        ];
    }

    async debugTransaction(txHash) {
        console.log(`\n🔍 Debugging Transaction: ${txHash}`);
        console.log(`📍 Chain: ${this.chainName}\n`);

        try {
            // Get transaction receipt
            const receipt = await this.provider.getTransactionReceipt(txHash);
            if (!receipt) {
                console.log("❌ Transaction not found or still pending");
                return;
            }

            console.log("📋 Transaction Summary:");
            console.log(`   Status: ${receipt.status === 1 ? '✅ Success' : '❌ Failed'}`);
            console.log(`   Block: ${receipt.blockNumber}`);
            console.log(`   Gas Used: ${receipt.gasUsed.toString()}`);
            console.log(`   From: ${receipt.from}`);
            console.log(`   To: ${receipt.to}`);

            // Analyze events
            await this.analyzeEvents(receipt);

            // Get transaction details
            const tx = await this.provider.getTransaction(txHash);
            await this.analyzeTransactionData(tx);

        } catch (error) {
            console.error("❌ Error debugging transaction:", error.message);
        }
    }

    async analyzeEvents(receipt) {
        console.log("\n📡 Event Analysis:");
        
        if (receipt.logs.length === 0) {
            console.log("   No events emitted");
            return;
        }

        const yieldMaxInterface = new ethers.utils.Interface(this.yieldMaxABI);
        
        for (const log of receipt.logs) {
            try {
                const parsed = yieldMaxInterface.parseLog(log);
                console.log(`   🎯 ${parsed.name}:`);
                
                switch (parsed.name) {
                    case 'ExecutorCreated':
                        console.log(`      Executor: ${parsed.args.executor}`);
                        console.log(`      Target: ${parsed.args.target}`);
                        console.log(`      Deadline: ${new Date(parsed.args.deadline * 1000).toISOString()}`);
                        
                        // Check if target has code
                        await this.checkTargetContract(parsed.args.target);
                        break;
                        
                    case 'ExecutorExecuted':
                        console.log(`      Executor: ${parsed.args.executor}`);
                        console.log(`      Success: ${parsed.args.success ? '✅' : '❌'}`);
                        
                        if (!parsed.args.success) {
                            console.log("      ⚠️  Executor execution failed!");
                            await this.debugExecutorFailure(parsed.args.executor);
                        }
                        break;
                        
                    case 'CrossTxExecuted':
                        console.log(`      Sender: ${parsed.args.sender}`);
                        console.log(`      Target: ${parsed.args.target}`);
                        console.log(`      Value: ${parsed.args.value} wei`);
                        console.log(`      Data: ${parsed.args.data}`);
                        break;
                        
                    case 'ERC20Received':
                        console.log(`      Token: ${parsed.args.token}`);
                        console.log(`      Sender: ${parsed.args.sender}`);
                        console.log(`      Amount: ${parsed.args.amount}`);
                        
                        await this.analyzeToken(parsed.args.token);
                        break;
                        
                    case 'MessageFailed':
                        console.log(`      Message ID: ${parsed.args.messageId}`);
                        console.log(`      Reason: ${parsed.args.reason}`);
                        break;
                        
                    case 'MessageRecovered':
                        console.log(`      Message ID: ${parsed.args.messageId}`);
                        break;
                        
                    case 'EscrowRescued':
                        console.log(`      User: ${parsed.args.user}`);
                        console.log(`      Amount: ${ethers.utils.formatEther(parsed.args.amount)} ETH`);
                        break;
                        
                    case 'ERC20EscrowRescued':
                        console.log(`      User: ${parsed.args.user}`);
                        console.log(`      Token: ${parsed.args.token}`);
                        console.log(`      Amount: ${parsed.args.amount}`);
                        await this.analyzeToken(parsed.args.token);
                        break;
                        
                    case 'OwnershipTransferred':
                        console.log(`      Previous Owner: ${parsed.args.previousOwner}`);
                        console.log(`      New Owner: ${parsed.args.newOwner}`);
                        break;
                }
            } catch (error) {
                // Not a YieldMax event, try to decode as generic event
                console.log(`   📝 Raw Log: ${log.topics[0]} (${log.address})`);
            }
        }
    }

    async checkTargetContract(targetAddress) {
        const code = await this.provider.getCode(targetAddress);
        if (code === '0x') {
            console.log(`      ⚠️  WARNING: Target ${targetAddress} has no code (EOA or non-deployed contract)`);
        } else {
            console.log(`      ✅ Target ${targetAddress} is a valid contract`);
            
            // Try to identify if it's an ERC20
            try {
                const contract = new ethers.Contract(targetAddress, this.erc20ABI, this.provider);
                const [name, symbol, decimals] = await Promise.all([
                    contract.name().catch(() => 'Unknown'),
                    contract.symbol().catch(() => 'Unknown'),
                    contract.decimals().catch(() => 0)
                ]);
                console.log(`      📄 Token Info: ${name} (${symbol}) - ${decimals} decimals`);
            } catch (error) {
                console.log(`      📄 Contract type: Unknown (not standard ERC20)`);
            }
        }
    }

    async analyzeToken(tokenAddress) {
        try {
            const contract = new ethers.Contract(tokenAddress, this.erc20ABI, this.provider);
            const [name, symbol, decimals] = await Promise.all([
                contract.name(),
                contract.symbol(),
                contract.decimals()
            ]);
            console.log(`      📄 ${name} (${symbol}) - ${decimals} decimals`);
        } catch (error) {
            console.log(`      📄 Token info unavailable`);
        }
    }

    async debugExecutorFailure(executorAddress) {
        console.log(`\n🔧 Debugging Executor Failure: ${executorAddress}`);
        
        // Check if executor still exists
        const code = await this.provider.getCode(executorAddress);
        if (code === '0x') {
            console.log("   ✅ Executor self-destructed (normal cleanup)");
        } else {
            console.log("   ⚠️  Executor still exists - might indicate incomplete execution");
        }
        
        // Check executor balance
        const balance = await this.provider.getBalance(executorAddress);
        if (balance.gt(0)) {
            console.log(`   💰 Executor has remaining ETH: ${ethers.utils.formatEther(balance)}`);
        }
    }

    async analyzeTransactionData(tx) {
        console.log("\n📤 Transaction Data Analysis:");
        console.log(`   Value: ${ethers.utils.formatEther(tx.value)} ETH`);
        console.log(`   Gas Limit: ${tx.gasLimit.toString()}`);
        console.log(`   Gas Price: ${ethers.utils.formatUnits(tx.gasPrice, 'gwei')} gwei`);
        
        if (tx.data && tx.data !== '0x') {
            console.log(`   Data Length: ${tx.data.length / 2 - 1} bytes`);
            
            // Try to decode function call
            try {
                const yieldMaxInterface = new ethers.utils.Interface([
                    "function sendCrossChainExecution(uint64 destinationChainSelector, address receiver, address targetContract, uint256 value, address[] calldata tokenAddresses, uint256[] calldata tokenAmounts, bytes calldata callData) external payable"
                ]);
                
                const decoded = yieldMaxInterface.decodeFunctionData("sendCrossChainExecution", tx.data);
                console.log("   🎯 Decoded sendCrossChainExecution:");
                console.log(`      Destination Chain: ${decoded.destinationChainSelector}`);
                console.log(`      Receiver: ${decoded.receiver}`);
                console.log(`      Target Contract: ${decoded.targetContract}`);
                console.log(`      ETH Value: ${decoded.value} wei`);
                console.log(`      Token Addresses: [${decoded.tokenAddresses.join(', ')}]`);
                console.log(`      Token Amounts: [${decoded.tokenAmounts.join(', ')}]`);
                console.log(`      Call Data: ${decoded.callData}`);
                
                // Decode the inner call data
                await this.decodeCallData(decoded.callData);
                
            } catch (error) {
                console.log("   📝 Could not decode as sendCrossChainExecution");
            }
        }
    }

    async decodeCallData(callData) {
        if (!callData || callData === '0x' || callData.length < 10) {
            console.log("      📝 No call data or too short");
            return;
        }

        const selector = callData.substring(0, 10);
        console.log(`      🎯 Function Selector: ${selector}`);

        // Common ERC20 function selectors
        const knownSelectors = {
            '0xa9059cbb': 'transfer(address,uint256)',
            '0x095ea7b3': 'approve(address,uint256)',
            '0x23b872dd': 'transferFrom(address,address,uint256)',
            '0xcaa5c23f': 'multicall(tuple(address,bytes)[])',
            '0x70a08231': 'balanceOf(address)'
        };

        if (knownSelectors[selector]) {
            console.log(`      📋 Function: ${knownSelectors[selector]}`);
            
            if (selector === '0xa9059cbb') {
                // Decode transfer
                try {
                    const iface = new ethers.utils.Interface(['function transfer(address,uint256)']);
                    const decoded = iface.decodeFunctionData('transfer', callData);
                    console.log(`      📤 Transfer to: ${decoded[0]}`);
                    console.log(`      💰 Amount: ${decoded[1].toString()}`);
                } catch (error) {
                    console.log("      ❌ Failed to decode transfer parameters");
                }
            }
        } else {
            console.log("      📝 Unknown function selector");
        }
    }

    async checkFailedMessages(yieldMaxAddress) {
        console.log(`\n📋 Checking Failed Messages on ${yieldMaxAddress}:`);
        
        try {
            const contract = new ethers.Contract(yieldMaxAddress, this.yieldMaxABI, this.provider);
            const failedMessages = await contract.getFailedMessages(0, 10);
            
            if (failedMessages.length === 0) {
                console.log("   ✅ No failed messages found");
            } else {
                console.log(`   ⚠️  Found ${failedMessages.length} failed messages:`);
                failedMessages.forEach((msg, index) => {
                    console.log(`      ${index + 1}. Message ID: ${msg.messageId}`);
                    console.log(`         Source Chain: ${msg.sourceChainSelector}`);
                    console.log(`         Tokens: ${msg.tokens.length} token(s)`);
                });
            }
        } catch (error) {
            console.log("   ❌ Could not check failed messages:", error.message);
        }
    }
}

// CLI Usage
async function main() {
    const args = process.argv.slice(2);
    
    if (args.length < 3) {
        console.log(`
Usage: node debug-transaction.js <RPC_URL> <CHAIN_NAME> <TX_HASH> [YIELDMAX_ADDRESS]

Examples:
  # Debug Base transaction
  node debug-transaction.js "https://mainnet.base.org" "Base" "0x..."
  
  # Debug Avalanche transaction
  node debug-transaction.js "https://api.avax.network/ext/bc/C/rpc" "Avalanche" "0x..."
  
  # Also check failed messages
  node debug-transaction.js "https://mainnet.base.org" "Base" "0x..." "0xe97978aB28f4d340494293a519B8Ba7Ab6E9640F"
        `);
        process.exit(1);
    }

    const [rpcUrl, chainName, txHash, yieldMaxAddress] = args;
    
    const txDebugger = new OnChainDebugger(rpcUrl, chainName);
    
    await txDebugger.debugTransaction(txHash);
    
    if (yieldMaxAddress) {
        await txDebugger.checkFailedMessages(yieldMaxAddress);
    }
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = { OnChainDebugger }; 