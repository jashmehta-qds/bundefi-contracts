#!/usr/bin/env node

const Web3 = require('web3');

/**
 * ERC20 Approval Utility
 * Supports encoding approve function calls using web3.js
 */

class ERC20ApprovalUtility {
    constructor() {
        this.web3 = new Web3();
        
        // Standard ERC20 approve function ABI
        this.approveABI = {
            name: 'approve',
            type: 'function',
            inputs: [
                { type: 'address', name: 'spender' },
                { type: 'uint256', name: 'amount' }
            ]
        };
        
        // Common token configurations
        this.tokens = {
            // Base network tokens
            base: {
                usdc: {
                    address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
                    decimals: 6,
                    symbol: 'USDC'
                },
                weth: {
                    address: '0x4200000000000000000000000000000000000006',
                    decimals: 18,
                    symbol: 'WETH'
                }
            },
            // Ethereum mainnet tokens
            ethereum: {
                usdc: {
                    address: '0xA0b86a33E6441b8bF4C4d8C5a7F5d4F7E3F4A4A4',
                    decimals: 6,
                    symbol: 'USDC'
                },
                weth: {
                    address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
                    decimals: 18,
                    symbol: 'WETH'
                }
            }
        };
        
        // Common spender addresses (DeFi protocols, bridges, etc.)
        this.commonSpenders = {
            yieldMaxBase: '0xe97978aB28f4d340494293a519B8Ba7Ab6E9640F',
            yieldMaxAvalanche: '0x379154D8C0b0B19B773f841554f7b7Ad445cA244',
            uniswapRouter: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
            oneInchRouter: '0x1111111254EEB25477B68fb85Ed929f73A960582'
        };
    }

    /**
     * Encode approve function call using web3.js
     */
    encodeApprove(spender, amount) {
        try {
            return this.web3.eth.abi.encodeFunctionCall(this.approveABI, [spender, amount]);
        } catch (error) {
            throw new Error(`Failed to encode approve: ${error.message}`);
        }
    }

    /**
     * Encode approve with human-readable amount
     */
    encodeApproveWithDecimals(spender, amount, decimals = 18) {
        try {
            const amountWei = this.web3.utils.toWei(amount.toString(), this.getUnit(decimals));
            return this.encodeApprove(spender, amountWei);
        } catch (error) {
            // Fallback for non-standard decimals
            const multiplier = Math.pow(10, decimals);
            const amountBN = this.web3.utils.toBN(Math.floor(amount * multiplier));
            return this.encodeApprove(spender, amountBN.toString());
        }
    }

    /**
     * Encode unlimited approval (max uint256)
     */
    encodeUnlimitedApprove(spender) {
        const maxUint256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
        return this.encodeApprove(spender, maxUint256);
    }

    /**
     * Encode approval revocation (set to 0)
     */
    encodeRevokeApproval(spender) {
        return this.encodeApprove(spender, '0');
    }

    /**
     * Get appropriate unit for web3.utils.toWei based on decimals
     */
    getUnit(decimals) {
        const units = {
            18: 'ether',
            9: 'gwei',
            6: 'mwei',
            3: 'kwei',
            0: 'wei'
        };
        return units[decimals] || 'wei';
    }

    /**
     * Batch encode multiple approvals
     */
    encodeBatchApprovals(approvals) {
        return approvals.map(approval => {
            const { spender, amount, decimals = 18 } = approval;
            return {
                ...approval,
                encodedData: this.encodeApproveWithDecimals(spender, amount, decimals)
            };
        });
    }

    /**
     * Generate approval transaction object
     */
    generateApprovalTransaction(tokenAddress, spender, amount, decimals = 18, options = {}) {
        const data = this.encodeApproveWithDecimals(spender, amount, decimals);
        
        return {
            to: tokenAddress,
            data: data,
            value: '0x0', // ERC20 transfers don't send ETH
            gas: options.gasLimit || '0x11170', // 70,000 gas default
            gasPrice: options.gasPrice || undefined,
            maxFeePerGas: options.maxFeePerGas || undefined,
            maxPriorityFeePerGas: options.maxPriorityFeePerGas || undefined,
            nonce: options.nonce || undefined
        };
    }

    /**
     * Decode approval transaction
     */
    decodeApproval(data) {
        try {
            const decoded = this.web3.eth.abi.decodeParameters(
                ['address', 'uint256'],
                data.slice(10) // Remove function selector (first 4 bytes)
            );
            
            return {
                spender: decoded[0],
                amount: decoded[1],
                amountFormatted: this.web3.utils.fromWei(decoded[1], 'ether')
            };
        } catch (error) {
            throw new Error(`Failed to decode approval: ${error.message}`);
        }
    }

    /**
     * Get token info by symbol and network
     */
    getTokenInfo(network, symbol) {
        return this.tokens[network]?.[symbol.toLowerCase()];
    }

    /**
     * Get common spender address
     */
    getSpenderAddress(name) {
        return this.commonSpenders[name];
    }

    /**
     * Preset approval configurations
     */
    presets = {
        // Approve YieldMax for USDC
        yieldMaxUSDC: (amount = 'unlimited') => ({
            tokenAddress: this.tokens.base.usdc.address,
            spender: this.commonSpenders.yieldMaxBase,
            amount: amount === 'unlimited' ? 'unlimited' : amount,
            decimals: 6,
            description: 'Approve YieldMax to spend USDC'
        }),

        // Approve Uniswap for WETH
        uniswapWETH: (amount = 'unlimited') => ({
            tokenAddress: this.tokens.ethereum.weth.address,
            spender: this.commonSpenders.uniswapRouter,
            amount: amount === 'unlimited' ? 'unlimited' : amount,
            decimals: 18,
            description: 'Approve Uniswap to spend WETH'
        }),

        // Revoke all approvals
        revokeAll: (tokenAddress, spender) => ({
            tokenAddress,
            spender,
            amount: 0,
            decimals: 18,
            description: 'Revoke all approvals'
        })
    };
}

// CLI interface
async function main() {
    const utility = new ERC20ApprovalUtility();
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log(`
🔐 ERC20 Approval Utility

Usage: node erc20-approval-utility.js <command> [args...]

Commands:
  encode <spender> <amount> [decimals]     - Encode approval with decimals
  encode-raw <spender> <amount>            - Encode approval with raw amount
  unlimited <spender>                      - Encode unlimited approval
  revoke <spender>                         - Encode approval revocation
  transaction <token> <spender> <amount> [decimals] - Generate full transaction
  decode <data>                            - Decode approval data
  preset <name> [amount]                   - Use preset configuration
  batch <file>                             - Batch encode from JSON file

Presets:
  yieldmax-usdc [amount]                   - Approve YieldMax for USDC
  uniswap-weth [amount]                    - Approve Uniswap for WETH
  revoke-all <token> <spender>             - Revoke all approvals

Examples:
  node erc20-approval-utility.js encode 0xSpender 100 6
  node erc20-approval-utility.js unlimited 0xSpender
  node erc20-approval-utility.js preset yieldmax-usdc 1000
  node erc20-approval-utility.js transaction 0xToken 0xSpender 100 18
        `);
        return;
    }

    const command = args[0];
    
    try {
        switch (command) {
            case 'encode':
                const [spender, amount, decimals = 18] = args.slice(1);
                const encoded = utility.encodeApproveWithDecimals(spender, amount, parseInt(decimals));
                console.log('🔐 Encoded Approval:');
                console.log(encoded);
                break;

            case 'encode-raw':
                const [rawSpender, rawAmount] = args.slice(1);
                const rawEncoded = utility.encodeApprove(rawSpender, rawAmount);
                console.log('🔐 Encoded Approval (Raw):');
                console.log(rawEncoded);
                break;

            case 'unlimited':
                const [unlimitedSpender] = args.slice(1);
                const unlimitedEncoded = utility.encodeUnlimitedApprove(unlimitedSpender);
                console.log('♾️ Unlimited Approval:');
                console.log(unlimitedEncoded);
                break;

            case 'revoke':
                const [revokeSpender] = args.slice(1);
                const revokeEncoded = utility.encodeRevokeApproval(revokeSpender);
                console.log('🚫 Revoke Approval:');
                console.log(revokeEncoded);
                break;

            case 'transaction':
                const [token, txSpender, txAmount, txDecimals = 18] = args.slice(1);
                const transaction = utility.generateApprovalTransaction(
                    token, 
                    txSpender, 
                    txAmount, 
                    parseInt(txDecimals)
                );
                console.log('📋 Transaction Object:');
                console.log(JSON.stringify(transaction, null, 2));
                break;

            case 'decode':
                const [data] = args.slice(1);
                const decoded = utility.decodeApproval(data);
                console.log('🔍 Decoded Approval:');
                console.log(JSON.stringify(decoded, null, 2));
                break;

            case 'preset':
                const [presetName, presetAmount] = args.slice(1);
                const presetKey = presetName.replace('-', '');
                if (utility.presets[presetKey]) {
                    const config = utility.presets[presetKey](presetAmount);
                    let encodedData;
                    
                    if (config.amount === 'unlimited') {
                        encodedData = utility.encodeUnlimitedApprove(config.spender);
                    } else if (config.amount === 0) {
                        encodedData = utility.encodeRevokeApproval(config.spender);
                    } else {
                        encodedData = utility.encodeApproveWithDecimals(
                            config.spender, 
                            config.amount, 
                            config.decimals
                        );
                    }
                    
                    console.log('🎯 Preset Configuration:');
                    console.log(JSON.stringify(config, null, 2));
                    console.log('\n🔐 Encoded Data:');
                    console.log(encodedData);
                } else {
                    console.log('❌ Unknown preset:', presetName);
                    console.log('Available presets:', Object.keys(utility.presets));
                }
                break;

            case 'batch':
                const [file] = args.slice(1);
                const fs = require('fs');
                const approvals = JSON.parse(fs.readFileSync(file, 'utf8'));
                const batchResult = utility.encodeBatchApprovals(approvals);
                console.log('📦 Batch Approvals:');
                console.log(JSON.stringify(batchResult, null, 2));
                break;

            default:
                console.log('❌ Unknown command:', command);
        }
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

// Export for use as module
module.exports = ERC20ApprovalUtility;

// Run CLI if called directly
if (require.main === module) {
    main();
} 