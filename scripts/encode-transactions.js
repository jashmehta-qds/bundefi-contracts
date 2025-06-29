#!/usr/bin/env node

const { ethers } = require('ethers');

/**
 * Transaction Encoding Utility Script
 * Supports various encoding patterns for cross-chain execution
 */

class TransactionEncoder {
    constructor() {
        // Common contract interfaces
        this.interfaces = {
            erc20: new ethers.utils.Interface([
                "function transfer(address to, uint256 amount)",
                "function approve(address spender, uint256 amount)",
                "function transferFrom(address from, address to, uint256 amount)",
                "function mint(address to, uint256 amount)",
                "function burn(uint256 amount)"
            ]),
            
            multicall: new ethers.utils.Interface([
                "function multicall(bytes[] calldata data) returns (bytes[] memory results)"
            ]),
            
            echo: new ethers.utils.Interface([
                "function echo(string calldata message)",
                "function echoWithValue(string calldata message) payable"
            ]),
            
            yieldMax: new ethers.utils.Interface([
                "function sendCrossChainExecution(uint64 destinationChainSelector, address receiver, address targetContract, uint256 value, address[] calldata tokenAddresses, uint256[] calldata tokenAmounts, bytes calldata callData) payable"
            ])
        };
        
        // Common chain selectors
        this.chainSelectors = {
            ethereum: "5009297550715157269",
            base: "10344971235874465080",
            avalanche: "14767482510784806043",
            arbitrum: "4949039107694359620",
            polygon: "4051577828743386545",
            optimism: "3734403246176062136"
        };
        
        // Common token addresses
        this.tokens = {
            base: {
                usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
                weth: "0x4200000000000000000000000000000000000006"
            },
            ethereum: {
                usdc: "0xA0b86a33E6441b8bF4C4d8C5a7F5d4F7E3F4A4A4",
                weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
            }
        };
    }

    /**
     * Generic function call encoder
     */
    encodeFunction(functionSignature, params = []) {
        try {
            const iface = new ethers.utils.Interface([functionSignature]);
            const functionName = this.extractFunctionName(functionSignature);
            return iface.encodeFunctionData(functionName, params);
        } catch (error) {
            throw new Error(`Failed to encode function: ${error.message}`);
        }
    }

    /**
     * ERC20 token operations
     */
    encodeERC20Transfer(to, amount, decimals = 18) {
        const parsedAmount = ethers.utils.parseUnits(amount.toString(), decimals);
        return this.interfaces.erc20.encodeFunctionData("transfer", [to, parsedAmount]);
    }

    encodeERC20Approve(spender, amount, decimals = 18) {
        const parsedAmount = ethers.utils.parseUnits(amount.toString(), decimals);
        return this.interfaces.erc20.encodeFunctionData("approve", [spender, parsedAmount]);
    }

    encodeERC20TransferFrom(from, to, amount, decimals = 18) {
        const parsedAmount = ethers.utils.parseUnits(amount.toString(), decimals);
        return this.interfaces.erc20.encodeFunctionData("transferFrom", [from, to, parsedAmount]);
    }

    /**
     * Echo contract operations
     */
    encodeEcho(message) {
        return this.interfaces.echo.encodeFunctionData("echo", [message]);
    }

    encodeEchoWithValue(message) {
        return this.interfaces.echo.encodeFunctionData("echoWithValue", [message]);
    }

    /**
     * Multicall encoder
     */
    encodeMulticall(calls) {
        return this.interfaces.multicall.encodeFunctionData("multicall", [calls]);
    }

    /**
     * YieldMax cross-chain execution encoder
     */
    encodeCrossChainExecution(params) {
        const {
            destinationChain,
            receiver,
            targetContract,
            value = 0,
            tokenAddresses = [],
            tokenAmounts = [],
            callData = "0x"
        } = params;

        const chainSelector = this.chainSelectors[destinationChain] || destinationChain;
        const parsedValue = typeof value === 'string' ? ethers.utils.parseEther(value) : value;
        
        return this.interfaces.yieldMax.encodeFunctionData("sendCrossChainExecution", [
            chainSelector,
            receiver,
            targetContract,
            parsedValue,
            tokenAddresses,
            tokenAmounts,
            callData
        ]);
    }

    /**
     * Batch encoder for multiple operations
     */
    encodeBatch(operations) {
        const encodedCalls = operations.map(op => {
            switch (op.type) {
                case 'erc20Transfer':
                    return this.encodeERC20Transfer(op.to, op.amount, op.decimals);
                case 'erc20Approve':
                    return this.encodeERC20Approve(op.spender, op.amount, op.decimals);
                case 'echo':
                    return this.encodeEcho(op.message);
                case 'custom':
                    return this.encodeFunction(op.signature, op.params);
                default:
                    throw new Error(`Unknown operation type: ${op.type}`);
            }
        });
        
        return this.encodeMulticall(encodedCalls);
    }

    /**
     * Decode transaction data
     */
    decodeTransaction(data, contractInterface) {
        try {
            const iface = typeof contractInterface === 'string' 
                ? new ethers.utils.Interface([contractInterface])
                : contractInterface;
            
            return iface.parseTransaction({ data });
        } catch (error) {
            throw new Error(`Failed to decode transaction: ${error.message}`);
        }
    }

    /**
     * Utility functions
     */
    extractFunctionName(signature) {
        return signature.split('(')[0].split(' ').pop();
    }

    formatAmount(amount, decimals = 18) {
        return ethers.utils.parseUnits(amount.toString(), decimals);
    }

    parseAmount(amount, decimals = 18) {
        return ethers.utils.formatUnits(amount, decimals);
    }

    /**
     * Preset templates for common operations
     */
    templates = {
        // Simple USDC transfer
        usdcTransfer: (to, amount) => ({
            type: 'crossChain',
            destinationChain: 'avalanche',
            receiver: to,
            targetContract: this.tokens.base.usdc,
            tokenAddresses: [this.tokens.base.usdc],
            tokenAmounts: [this.formatAmount(amount, 6)],
            callData: this.encodeERC20Transfer(to, amount, 6)
        }),

        // Echo message with tokens
        echoWithTokens: (message, tokenAddress, amount, decimals = 18) => ({
            type: 'crossChain',
            destinationChain: 'avalanche',
            receiver: "0x379154D8C0b0B19B773f841554f7b7Ad445cA244",
            targetContract: "0x379154D8C0b0B19B773f841554f7b7Ad445cA244",
            tokenAddresses: [tokenAddress],
            tokenAmounts: [this.formatAmount(amount, decimals)],
            callData: this.encodeEcho(message)
        }),

        // Multi-step operation
        multiStep: (operations) => ({
            type: 'crossChain',
            destinationChain: 'avalanche',
            receiver: "0x379154D8C0b0B19B773f841554f7b7Ad445cA244",
            targetContract: "0x379154D8C0b0B19B773f841554f7b7Ad445cA244",
            callData: this.encodeBatch(operations)
        })
    };
}

// CLI interface
async function main() {
    const encoder = new TransactionEncoder();
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log(`
🔧 Transaction Encoder Utility

Usage: node encode-transactions.js <command> [args...]

Commands:
  erc20-transfer <to> <amount> [decimals]     - Encode ERC20 transfer
  erc20-approve <spender> <amount> [decimals] - Encode ERC20 approval
  echo <message>                              - Encode echo call
  function <signature> <params...>            - Encode custom function
  cross-chain <template> [args...]            - Encode cross-chain execution
  decode <data> <signature>                   - Decode transaction data

Examples:
  node encode-transactions.js erc20-transfer 0x742d35Cc 100 6
  node encode-transactions.js echo "Hello World"
  node encode-transactions.js function "function mint(address,uint256)" 0x742d35Cc 1000
  node encode-transactions.js cross-chain usdc-transfer 0x742d35Cc 100
        `);
        return;
    }

    const command = args[0];
    
    try {
        switch (command) {
            case 'erc20-transfer':
                const [to, amount, decimals = 18] = args.slice(1);
                const transferData = encoder.encodeERC20Transfer(to, amount, decimals);
                console.log('📤 ERC20 Transfer Calldata:');
                console.log(transferData);
                break;

            case 'erc20-approve':
                const [spender, approveAmount, approveDecimals = 18] = args.slice(1);
                const approveData = encoder.encodeERC20Approve(spender, approveAmount, approveDecimals);
                console.log('✅ ERC20 Approve Calldata:');
                console.log(approveData);
                break;

            case 'echo':
                const [message] = args.slice(1);
                const echoData = encoder.encodeEcho(message);
                console.log('📢 Echo Calldata:');
                console.log(echoData);
                break;

            case 'function':
                const [signature, ...params] = args.slice(1);
                const functionData = encoder.encodeFunction(signature, params);
                console.log('🔧 Custom Function Calldata:');
                console.log(functionData);
                break;

            case 'cross-chain':
                const [template, ...templateArgs] = args.slice(1);
                if (encoder.templates[template]) {
                    const config = encoder.templates[template](...templateArgs);
                    const crossChainData = encoder.encodeCrossChainExecution(config);
                    console.log('🌉 Cross-Chain Execution Calldata:');
                    console.log(crossChainData);
                    console.log('\n📋 Configuration:');
                    console.log(JSON.stringify(config, null, 2));
                } else {
                    console.log('❌ Unknown template:', template);
                    console.log('Available templates:', Object.keys(encoder.templates));
                }
                break;

            case 'decode':
                const [data, decodeSignature] = args.slice(1);
                const decoded = encoder.decodeTransaction(data, decodeSignature);
                console.log('🔍 Decoded Transaction:');
                console.log(JSON.stringify(decoded, null, 2));
                break;

            default:
                console.log('❌ Unknown command:', command);
        }
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

// Export for use as module
module.exports = TransactionEncoder;

// Run CLI if called directly
if (require.main === module) {
    main();
} 