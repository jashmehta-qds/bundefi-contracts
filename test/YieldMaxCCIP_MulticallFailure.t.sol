// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Multicall Failure Simulation
 * @dev Replicates the exact failure scenario where multicall uses regular call() 
 *      instead of delegatecall(), causing msg.sender to be Multicall3 instead of executor
 */
contract YieldMaxCCIP_MulticallFailure is Test {
    
    // Mock ERC20 token for testing
    MockToken public token;
    
    // Mock executor that holds tokens (like your predicted executor)
    MockExecutor public executor;
    
    // Mock multicall contract (simulates Multicall3)
    MockMulticall public multicall;
    
    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");
    
    uint256 public constant TRANSFER_AMOUNT = 1000 * 1e18; // 1000 tokens
    uint256 public constant GAS_LIMIT = 1_000_000;         // 1 million gas
    
    function setUp() public {
        // Deploy mock contracts
        token = new MockToken("Test Token", "TEST");
        executor = new MockExecutor();
        multicall = new MockMulticall();
        
        // Give executor some tokens (simulates CCIP transfer)
        token.mint(address(executor), TRANSFER_AMOUNT * 10);
        
        console.log("=== Setup Complete ===");
        console.log("Token:", address(token));
        console.log("Executor:", address(executor));
        console.log("Multicall:", address(multicall));
        console.log("User:", user);
        console.log("Recipient:", recipient);
        console.log("Executor token balance:", token.balanceOf(address(executor)));
    }
    
    /**
     * @dev Test that replicates the EXACT failure scenario
     * This shows how multicall with regular call() fails because:
     * 1. Executor owns the tokens (from CCIP transfer)
     * 2. Multicall uses call() not delegatecall()
     * 3. msg.sender becomes Multicall in approve/transfer calls
     * 4. Multicall doesn't own tokens, so calls fail
     */
    function test_MulticallFailureScenario() public {
        console.log("\n=== REPLICATING MULTICALL FAILURE SCENARIO ===");
        
        // 1. Build the failing multicall data
        bytes memory multicallData = _buildFailingMulticallData();
        
        // 2. Executor calls multicall (this simulates your CCIP execution)
        console.log("\nExecutor calling multicall...");
        
        // This will fail because multicall uses call(), not delegatecall()
        vm.expectRevert(); // We expect this to fail
        executor.executeMulticall(address(multicall), multicallData);
        
        console.log("\n=== FAILURE ANALYSIS ===");
        console.log("Executor has tokens:", token.balanceOf(address(executor)));
        console.log("Multicall has no tokens:", token.balanceOf(address(multicall)));
        console.log("Recipient got nothing:", token.balanceOf(recipient));
        console.log("Calls failed because msg.sender = Multicall, not Executor");
        
        // Verify the failure
        assertEq(token.balanceOf(recipient), 0, "Transfer should have failed");
        assertGt(token.balanceOf(address(executor)), 0, "Executor should still have tokens");
    }
    
    /**
     * @dev Test showing the correct approach with delegatecall
     */
    function test_MulticallSuccessWithDelegatecall() public {
        console.log("\n=== SHOWING CORRECT APPROACH WITH DELEGATECALL ===");
        
        // Build the same multicall data
        bytes memory multicallData = _buildWorkingMulticallData();
        
        // Executor calls multicall with delegatecall (correct approach)
        console.log("\nExecutor calling multicall with delegatecall...");
        
        executor.executeMulticallWithDelegatecall(address(multicall), multicallData);
        
        console.log("\n=== SUCCESS ANALYSIS ===");
        console.log("Executor used delegatecall");
        console.log("msg.sender = Executor in all calls");
        console.log("Executor can approve/transfer its own tokens");
        console.log("Recipient balance:", token.balanceOf(recipient));
        
        // Verify success
        assertEq(token.balanceOf(recipient), TRANSFER_AMOUNT, "Transfer should succeed");
        assertEq(token.balanceOf(address(executor)), TRANSFER_AMOUNT * 10 - TRANSFER_AMOUNT, "Executor balance reduced");
    }
    
    /**
     * @dev Builds multicall data that will FAIL with regular call()
     */
    function _buildFailingMulticallData() internal view returns (bytes memory) {
        console.log("\nBuilding FAILING multicall data (uses call)...");
        
        // Step 1: Approve multicall to spend executor's tokens
        // This FAILS because msg.sender = Multicall, not Executor
        bytes memory approveCall = abi.encodeWithSelector(
            IERC20.approve.selector,
            address(multicall),
            TRANSFER_AMOUNT
        );
        
        // Step 2: Transfer tokens to recipient
        // This FAILS because msg.sender = Multicall, not Executor  
        bytes memory transferCall = abi.encodeWithSelector(
            IERC20.transfer.selector,
            recipient,
            TRANSFER_AMOUNT
        );
        
        // Build multicall data that uses call()
        return abi.encodeWithSelector(
            MockMulticall.aggregate3WithCall.selector,
            address(token),
            approveCall,
            transferCall
        );
    }
    
    /**
     * @dev Builds multicall data that will WORK with delegatecall()
     */
    function _buildWorkingMulticallData() internal view returns (bytes memory) {
        console.log("\nBuilding WORKING multicall data (uses delegatecall)...");
        
        // Same calls, but will work with delegatecall
        bytes memory transferCall = abi.encodeWithSelector(
            IERC20.transfer.selector,
            recipient,
            TRANSFER_AMOUNT
        );
        
        // Build multicall data that uses delegatecall
        return abi.encodeWithSelector(
            MockMulticall.aggregate3WithDelegatecall.selector,
            address(token),
            transferCall
        );
    }
}

/**
 * @dev Mock ERC20 token for testing
 */
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @dev Mock executor that simulates your predicted executor contract
 */
contract MockExecutor {
    function executeMulticall(address target, bytes calldata data) external {
        console.log("Executor using CALL (will fail)");
        (bool success, bytes memory result) = target.call(data);
        require(success, "Multicall failed");
    }
    
    function executeMulticallWithDelegatecall(address target, bytes calldata data) external {
        console.log("Executor using DELEGATECALL (will work)");
        (bool success, bytes memory result) = target.delegatecall(data);
        require(success, "Multicall failed");
    }
}

/**
 * @dev Mock multicall contract that simulates Multicall3 behavior
 */
contract MockMulticall {
    
    /**
     * @dev Simulates Multicall3.aggregate3 with regular call()
     * This will FAIL because msg.sender becomes this contract
     */
    function aggregate3WithCall(
        address token,
        bytes calldata approveCall,
        bytes calldata transferCall
    ) external {
        console.log("Multicall using CALL - msg.sender:", msg.sender);
        console.log("This contract address:", address(this));
        
        // These calls will fail because msg.sender = this contract
        (bool success1,) = token.call(approveCall);
        console.log("Approve success:", success1);
        
        (bool success2,) = token.call(transferCall);
        console.log("Transfer success:", success2);
        
        require(success1 && success2, "Multicall operations failed");
    }
    
    /**
     * @dev Simulates multicall with delegatecall approach
     * This will WORK because msg.sender remains the executor
     */
    function aggregate3WithDelegatecall(
        address token,
        bytes calldata transferCall
    ) external {
        console.log("Multicall using context - msg.sender:", msg.sender);
        
        // Direct call works because we're in executor's context
        (bool success,) = token.call(transferCall);
        console.log("Transfer success:", success);
        
        require(success, "Transfer failed");
    }
} 