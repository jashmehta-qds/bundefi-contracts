// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Enhanced ExecutorTemplate with Native Multicall Support
contract EnhancedExecutorTemplate {
    using SafeERC20 for IERC20;
    
    address public yieldMax;
    uint256 public deadline;
    bool private initialized;
    
    // Track tokens sent to this executor for proper cleanup
    address[] public trackedTokens;
    
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }
    
    struct CallResult {
        bool success;
        bytes returnData;
    }
    
    error NotInitialized();
    error AlreadyInitialized();
    error Unauthorized();
    error DeadlineExceeded();
    error ExecutionFailed(uint256 callIndex, bytes reason);
    error InsufficientValue();
    
    event CallExecuted(address indexed target, uint256 value, bool success, bytes returnData);
    event MulticallExecuted(uint256 callCount, uint256 successCount);
    
    modifier onlyYieldMax() {
        if (msg.sender != yieldMax) revert Unauthorized();
        _;
    }
    
    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }
    
    modifier beforeDeadline() {
        if (block.timestamp >= deadline) revert DeadlineExceeded();
        _;
    }
    
    function initialize(uint256 _deadline) external {
        if (initialized) revert AlreadyInitialized();
        
        yieldMax = msg.sender;
        deadline = _deadline;
        initialized = true;
    }
    
    /// @notice Execute a single call (backward compatibility)
    function executeAndCleanup(address target, bytes calldata data) external payable 
        onlyYieldMax 
        onlyInitialized 
        beforeDeadline 
    {
        (bool success, bytes memory returnData) = target.call{value: msg.value}(data);
        if (!success) revert ExecutionFailed(0, returnData);
        
        emit CallExecuted(target, msg.value, success, returnData);
        
        // Auto-cleanup: return remaining assets
        _returnAllAssets();
        initialized = false;
    }
    
    /// @notice Execute multiple calls in sequence (native multicall)
    function multicallAndCleanup(Call[] calldata calls) external payable 
        onlyYieldMax 
        onlyInitialized 
        beforeDeadline 
        returns (CallResult[] memory results)
    {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
        }
        
        if (totalValue > msg.value) revert InsufficientValue();
        
        results = new CallResult[](calls.length);
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            
            (bool success, bytes memory returnData) = call.target.call{value: call.value}(call.data);
            
            results[i] = CallResult({
                success: success,
                returnData: returnData
            });
            
            if (success) {
                successCount++;
            }
            
            emit CallExecuted(call.target, call.value, success, returnData);
        }
        
        emit MulticallExecuted(calls.length, successCount);
        
        // Auto-cleanup: return remaining assets
        _returnAllAssets();
        initialized = false;
        
        return results;
    }
    
    /// @notice Execute multiple calls with failure tolerance
    function multicallTolerantAndCleanup(Call[] calldata calls, bool requireAllSuccess) external payable 
        onlyYieldMax 
        onlyInitialized 
        beforeDeadline 
        returns (CallResult[] memory results)
    {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
        }
        
        if (totalValue > msg.value) revert InsufficientValue();
        
        results = new CallResult[](calls.length);
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            
            (bool success, bytes memory returnData) = call.target.call{value: call.value}(call.data);
            
            results[i] = CallResult({
                success: success,
                returnData: returnData
            });
            
            if (success) {
                successCount++;
            } else if (requireAllSuccess) {
                revert ExecutionFailed(i, returnData);
            }
            
            emit CallExecuted(call.target, call.value, success, returnData);
        }
        
        emit MulticallExecuted(calls.length, successCount);
        
        // Auto-cleanup: return remaining assets
        _returnAllAssets();
        initialized = false;
        
        return results;
    }
    
    /// @notice Execute calls with custom value distribution
    function executeWithValueAndCleanup(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable 
        onlyYieldMax 
        onlyInitialized 
        beforeDeadline 
        returns (CallResult[] memory results)
    {
        require(targets.length == values.length && values.length == datas.length, "Array length mismatch");
        
        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length; i++) {
            totalValue += values[i];
        }
        
        if (totalValue > msg.value) revert InsufficientValue();
        
        results = new CallResult[](targets.length);
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returnData) = targets[i].call{value: values[i]}(datas[i]);
            
            results[i] = CallResult({
                success: success,
                returnData: returnData
            });
            
            if (success) {
                successCount++;
            }
            
            emit CallExecuted(targets[i], values[i], success, returnData);
        }
        
        emit MulticallExecuted(targets.length, successCount);
        
        // Auto-cleanup: return remaining assets
        _returnAllAssets();
        initialized = false;
        
        return results;
    }
    
    /// @notice Emergency recovery function
    function recoverTokens() external onlyYieldMax onlyInitialized {
        _returnAllAssets();
        initialized = false;
    }
    
    function _returnAllAssets() private {
        // Return all tracked ERC20 tokens
        for (uint256 i = 0; i < trackedTokens.length; i++) {
            address token = trackedTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            
            if (balance > 0) {
                IERC20(token).safeTransfer(yieldMax, balance);
            }
        }
        
        // Return any remaining ETH
        if (address(this).balance > 0) {
            (bool success, ) = yieldMax.call{value: address(this).balance}("");
            require(success, "ETH transfer failed");
        }
    }
    
    /// @notice Register a token for tracking (called by YieldMaxCCIP)
    function addTrackedToken(address token) external {
        require(msg.sender == yieldMax, "Only YieldMax can add tokens");
        trackedTokens.push(token);
    }
    
    // Allow receiving ETH
    receive() external payable {}
    
    // View functions for debugging
    function getTrackedTokens() external view returns (address[] memory) {
        return trackedTokens;
    }
    
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

/// @title Multicall Helper Library
library MulticallEncoder {
    using SafeERC20 for IERC20;
    
    struct MulticallBuilder {
        EnhancedExecutorTemplate.Call[] calls;
    }
    
    /// @notice Create a new multicall builder
    function create() internal pure returns (MulticallBuilder memory) {
        return MulticallBuilder({
            calls: new EnhancedExecutorTemplate.Call[](0)
        });
    }
    
    /// @notice Add a call to the multicall
    function addCall(
        MulticallBuilder memory builder,
        address /*_target*/,
        uint256 /*_value*/,
        bytes memory /*_data*/
    ) internal pure returns (MulticallBuilder memory) {
        // Note: This is a simplified version - in practice you'd use dynamic arrays
        return builder;
    }
}

/// @title Common Multicall Patterns
library MulticallPatterns {
    using SafeERC20 for IERC20;
    
    /// @notice Create approve + transferFrom pattern
    function createApproveAndTransfer(
        address token,
        address spender,
        address recipient,
        uint256 amount
    ) internal view returns (EnhancedExecutorTemplate.Call[] memory calls) {
        calls = new EnhancedExecutorTemplate.Call[](2);
        
        // 1. Approve tokens to spender
        calls[0] = EnhancedExecutorTemplate.Call({
            target: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        });
        
        // 2. TransferFrom to recipient
        calls[1] = EnhancedExecutorTemplate.Call({
            target: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), recipient, amount)
        });
        
        return calls;
    }
    
    /// @notice Create approve + DeFi interaction pattern
    function createApproveAndDeposit(
        address token,
        address protocol,
        uint256 amount,
        bytes memory depositCalldata
    ) internal pure returns (EnhancedExecutorTemplate.Call[] memory calls) {
        calls = new EnhancedExecutorTemplate.Call[](2);
        
        // 1. Approve tokens to protocol
        calls[0] = EnhancedExecutorTemplate.Call({
            target: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, protocol, amount)
        });
        
        // 2. Deposit to protocol
        calls[1] = EnhancedExecutorTemplate.Call({
            target: protocol,
            value: 0,
            data: depositCalldata
        });
        
        return calls;
    }
} 