// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

// Pattern 1: IsolatedProxy - Regular call, tokens stay in proxy
contract IsolatedProxy {
    mapping(bytes32 => ExecutionContext) private contexts;
    
    struct ExecutionContext {
        address target;
        uint256 deadline;
        bool active;
        mapping(address => uint256) tokenBalances; // Tokens stay HERE
    }
    
    function executeIsolated(
        bytes32 executionId,
        address target,
        bytes calldata data
    ) external payable {
        ExecutionContext storage ctx = contexts[executionId];
        require(ctx.active && block.timestamp < ctx.deadline, "Invalid execution");
        
        // ❌ PROBLEM: Target needs approval to use tokens
        // Tokens are in IsolatedProxy, but target executes in its own context
        // Target would need: IERC20(token).transferFrom(address(IsolatedProxy), recipient, amount)
        // This requires IsolatedProxy to approve target first!
        
        (bool success,) = target.call{value: msg.value}(data);
        require(success, "Execution failed");
        
        delete contexts[executionId];
    }
    
    // Target would need to call this to get tokens
    function transferTokens(bytes32 executionId, address token, address to, uint256 amount) external {
        ExecutionContext storage ctx = contexts[executionId];
        require(ctx.active, "Invalid execution");
        require(ctx.tokenBalances[token] >= amount, "Insufficient balance");
        
        ctx.tokenBalances[token] -= amount;
        IERC20(token).transfer(to, amount);
    }
}

// Pattern 2: DelegatecallProxy - Delegatecall, tokens stay in proxy
contract DelegatecallProxy {
    mapping(bytes32 => ExecutionContext) private contexts;
    bytes32 private currentExecutionId;
    
    struct ExecutionContext {
        address target;
        uint256 deadline;
        bool active;
        mapping(address => uint256) tokenBalances; // Tokens stay HERE
    }
    
    function executeIsolated(
        bytes32 executionId,
        address target,
        bytes calldata data
    ) external payable {
        ExecutionContext storage ctx = contexts[executionId];
        require(ctx.active && block.timestamp < ctx.deadline, "Invalid execution");
        
        currentExecutionId = executionId;
        
        // ✅ WORKS: Target code runs in THIS context, can access tokens directly
        // Target can call: IERC20(token).transfer(recipient, amount)
        // Because it's running in DelegatecallProxy's context where tokens are stored
        
        (bool success,) = target.delegatecall(data);
        require(success, "Execution failed");
        
        currentExecutionId = bytes32(0);
        delete contexts[executionId];
    }
}

// Pattern 3: ExecutorProxy - Call to separate contract, tokens go to executor
contract ExecutorProxy {
    function executeIsolated(
        address target,
        bytes calldata data,
        address[] memory tokens,
        uint256[] memory amounts
    ) external payable {
        // Create fresh executor
        Executor executor = new Executor();
        
        // Transfer tokens TO the executor
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(address(executor), amounts[i]);
        }
        
        // ✅ WORKS: Target gets tokens from executor, executor is msg.sender
        // Target can call: IERC20(token).transferFrom(msg.sender, recipient, amount)
        // Because executor can approve itself
        
        executor.execute{value: msg.value}(target, data);
    }
}

contract Executor {
    function execute(address target, bytes calldata data) external payable {
        (bool success,) = target.call{value: msg.value}(data);
        require(success, "Execution failed");
    }
}

// Example target contract to show the differences
contract TargetContract {
    function processTokens(address token, uint256 amount, address recipient) external {
        // This function behavior depends on which pattern calls it:
        
        // With IsolatedProxy:
        // - msg.sender = IsolatedProxy
        // - Tokens are in IsolatedProxy
        // - ❌ This FAILS: IERC20(token).transferFrom(msg.sender, recipient, amount)
        // - Because IsolatedProxy never approved this contract
        
        // With DelegatecallProxy:
        // - msg.sender = Original caller (user)
        // - address(this) = DelegatecallProxy
        // - Tokens are in DelegatecallProxy (which is address(this))
        // - ✅ This WORKS: IERC20(token).transfer(recipient, amount)
        
        // With ExecutorProxy:
        // - msg.sender = Executor contract
        // - Tokens are in Executor contract
        // - ✅ This WORKS: IERC20(token).transferFrom(msg.sender, recipient, amount)
        // - If executor pre-approved this contract
        
        IERC20(token).transferFrom(msg.sender, recipient, amount);
    }
} 