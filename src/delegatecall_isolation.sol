// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract YieldMaxCCIPWithDelegateCall {
    using SafeERC20 for IERC20;
    
    // Main contract storage (slots 0-99)
    address public owner;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    // ... other main contract state
    
    // Execution isolation storage (slots 100+)
    // Each execution gets a unique execution ID and uses dedicated storage slots
    struct ExecutionContext {
        address target;
        address sender;
        uint256 value;
        uint256 deadline;
        mapping(address => uint256) tokenBalances; // Isolated token balances
        bool active;
    }
    
    mapping(bytes32 => ExecutionContext) private executions;
    bytes32 private currentExecutionId;
    
    // Storage slots for current execution (used by delegatecall targets)
    uint256 private constant EXECUTION_STORAGE_START = 1000;
    
    modifier onlyDuringExecution() {
        require(currentExecutionId != bytes32(0), "No active execution");
        require(executions[currentExecutionId].active, "Execution not active");
        require(block.timestamp < executions[currentExecutionId].deadline, "Execution expired");
        _;
    }
    
    function _ccipReceive(bytes memory messageData) internal {
        (address target, uint256 value, bytes memory callData, address sender) = 
            abi.decode(messageData, (address, uint256, bytes, address));
        
        // Create unique execution context
        bytes32 executionId = keccak256(abi.encode(target, sender, block.timestamp, block.number));
        
        ExecutionContext storage ctx = executions[executionId];
        ctx.target = target;
        ctx.sender = sender;
        ctx.value = value;
        ctx.deadline = block.timestamp + 1 hours;
        ctx.active = true;
        
        // Set current execution context
        currentExecutionId = executionId;
        
        // Execute target code in our context but with isolated storage access
        try this.executeInIsolation{value: value}(target, callData) {
            // Success - cleanup
            _cleanupExecution(executionId);
        } catch {
            // Failure - attempt recovery
            _recoverExecution(executionId);
        }
        
        // Clear current execution
        currentExecutionId = bytes32(0);
    }
    
    function executeInIsolation(address target, bytes calldata data) external payable onlyDuringExecution {
        require(msg.sender == address(this), "Internal only");
        
        // This is where the magic happens - delegatecall to target
        // Target code runs in our context but can only access isolated storage
        (bool success, bytes memory result) = target.delegatecall(data);
        
        if (!success) {
            // Forward the revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
    
    // Helper functions that targets can call to access isolated storage
    function getExecutionSender() external view onlyDuringExecution returns (address) {
        return executions[currentExecutionId].sender;
    }
    
    function getExecutionValue() external view onlyDuringExecution returns (uint256) {
        return executions[currentExecutionId].value;
    }
    
    function getTokenBalance(address token) external view onlyDuringExecution returns (uint256) {
        return executions[currentExecutionId].tokenBalances[token];
    }
    
    function transferTokensFromExecution(address token, address to, uint256 amount) external onlyDuringExecution {
        ExecutionContext storage ctx = executions[currentExecutionId];
        require(ctx.tokenBalances[token] >= amount, "Insufficient balance");
        
        ctx.tokenBalances[token] -= amount;
        IERC20(token).safeTransfer(to, amount);
    }
    
    function _cleanupExecution(bytes32 executionId) private {
        ExecutionContext storage ctx = executions[executionId];
        ctx.active = false;
        
        // Return any unused tokens to the main contract
        // (In practice, you'd iterate through known tokens)
    }
    
    function _recoverExecution(bytes32 executionId) private {
        ExecutionContext storage ctx = executions[executionId];
        ctx.active = false;
        
        // Recovery logic - return tokens to sender or escrow
    }
}

// Example target contract that works with the isolation pattern
contract IsolatedTarget {
    // This contract is designed to work with YieldMaxCCIPWithDelegateCall
    // It can only access storage through the provided helper functions
    
    function processTokens(address token, uint256 amount, address recipient) external {
        // When called via delegatecall, this code runs in YieldMaxCCIP's context
        // But it can only access isolated storage through helper functions
        
        // Get execution context (this calls back to YieldMaxCCIP's helper)
        address sender = YieldMaxCCIPWithDelegateCall(address(this)).getExecutionSender();
        uint256 availableBalance = YieldMaxCCIPWithDelegateCall(address(this)).getTokenBalance(token);
        
        require(availableBalance >= amount, "Insufficient tokens");
        
        // Transfer tokens using the isolated transfer function
        YieldMaxCCIPWithDelegateCall(address(this)).transferTokensFromExecution(token, recipient, amount);
        
        // Emit event (this will be emitted from YieldMaxCCIP's context)
        emit TokensProcessed(sender, token, amount, recipient);
    }
    
    event TokensProcessed(address indexed sender, address indexed token, uint256 amount, address indexed recipient);
} 