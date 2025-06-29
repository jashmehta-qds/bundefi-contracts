// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldMaxCCIP, ExecutorTemplate} from "../src/ym.sol";

/**
 * @title YieldMax Multicall Fix Test
 * @dev Tests that the delegatecall fix works correctly with real YieldMax contracts
 */
contract YieldMaxCCIP_MulticallFix is Test {
    
    YieldMaxCCIP public yieldMax;
    MockToken public token;
    MockMulticall3 public multicall3;
    
    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");
    
    // Real Multicall3 address
    address public constant MULTICALL3_ADDR = 0xcA11bde05977b3631167028862bE2a173976CA11;
    
    uint256 public constant TRANSFER_AMOUNT = 1000 * 1e18;
    uint256 public deadline;
    
    function setUp() public {
        deadline = block.timestamp + 1 hours;
        
        // Deploy mock router (for YieldMax constructor)
        address mockRouter = makeAddr("mockRouter");
        
        // Deploy YieldMax (it creates its own executor template)
        yieldMax = new YieldMaxCCIP(mockRouter);
        
        // Deploy mock token
        token = new MockToken("Test Token", "TEST");
        
        // Deploy mock Multicall3 at the expected address
        vm.etch(MULTICALL3_ADDR, type(MockMulticall3).runtimeCode);
        multicall3 = MockMulticall3(MULTICALL3_ADDR);
        
        console.log("=== Setup Complete ===");
        console.log("YieldMax:", address(yieldMax));
        console.log("Token:", address(token));
        console.log("Multicall3:", MULTICALL3_ADDR);
    }
    
    /**
     * @dev Test that multicall now works correctly with delegatecall fix
     */
    function test_MulticallFixWorks() public {
        console.log("\n=== TESTING MULTICALL FIX ===");
        
        // 1. Predict executor address
        address predictedExecutor = yieldMax.predictExecutorAddress(user);
        console.log("Predicted executor:", predictedExecutor);
        
        // 2. Give executor some tokens (simulates CCIP transfer)
        token.mint(predictedExecutor, TRANSFER_AMOUNT);
        console.log("Executor token balance:", token.balanceOf(predictedExecutor));
        
        // 3. Create executor by calling _getOrCreateExecutor
        vm.prank(address(yieldMax));
        address actualExecutor = yieldMax.predictExecutorAddress(user);
        
        // Deploy the executor manually for testing
        ExecutorTemplate executor = ExecutorTemplate(payable(predictedExecutor));
        vm.etch(predictedExecutor, type(ExecutorTemplate).runtimeCode);
        
        // Initialize the executor
        vm.prank(address(yieldMax));
        executor.initialize(MULTICALL3_ADDR, deadline);
        
        // 4. Build multicall data for token transfer
        bytes memory multicallData = _buildMulticallData();
        
        // 5. Execute via executor (this should now work with delegatecall)
        console.log("\nExecuting multicall via executor...");
        
        vm.prank(address(yieldMax));
        executor.executeAndCleanup(multicallData);
        
        // 6. Verify success
        console.log("\n=== VERIFICATION ===");
        console.log("Recipient balance:", token.balanceOf(recipient));
        console.log("Executor balance:", token.balanceOf(predictedExecutor));
        
        // Should succeed now!
        assertEq(token.balanceOf(recipient), TRANSFER_AMOUNT, "Transfer should succeed with delegatecall");
        assertEq(token.balanceOf(predictedExecutor), 0, "Executor should have no tokens left");
    }
    
    /**
     * @dev Test that regular contracts still use call() not delegatecall()
     */
    function test_RegularContractsStillUseCall() public {
        console.log("\n=== TESTING REGULAR CONTRACTS USE CALL ===");
        
        // Deploy a regular contract (not multicall)
        MockRegularContract regularContract = new MockRegularContract();
        
        // Predict and setup executor
        address predictedExecutor = yieldMax.predictExecutorAddress(user);
        token.mint(predictedExecutor, TRANSFER_AMOUNT);
        
        // Deploy and initialize executor
        ExecutorTemplate executor = ExecutorTemplate(payable(predictedExecutor));
        vm.etch(predictedExecutor, type(ExecutorTemplate).runtimeCode);
        
        vm.prank(address(yieldMax));
        executor.initialize(address(regularContract), deadline);
        
        // Build call data for regular contract
        bytes memory callData = abi.encodeWithSelector(
            MockRegularContract.doSomething.selector,
            "test message"
        );
        
        // Execute (should use call(), not delegatecall())
        vm.prank(address(yieldMax));
        executor.executeAndCleanup(callData);
        
        // Verify the regular contract was called correctly
        assertEq(regularContract.lastMessage(), "test message", "Regular contract should be called normally");
        console.log("Regular contract called successfully with call()");
    }
    
    /**
     * @dev Build multicall data for token transfer
     */
    function _buildMulticallData() internal view returns (bytes memory) {
        // Build transfer call
        bytes memory transferCall = abi.encodeWithSelector(
            IERC20.transfer.selector,
            recipient,
            TRANSFER_AMOUNT
        );
        
        // Build Multicall3.aggregate3 call
        return abi.encodeWithSelector(
            MockMulticall3.aggregate3.selector,
            address(token),
            transferCall
        );
    }
}

/**
 * @dev Mock ERC20 token
 */
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @dev Mock Multicall3 that simulates the real one
 */
contract MockMulticall3 {
    function aggregate3(address token, bytes calldata transferCall) external {
        console.log("Multicall3 aggregate3 called");
        console.log("msg.sender:", msg.sender);
        
        // This should work now because msg.sender = executor (via delegatecall)
        (bool success,) = token.call(transferCall);
        require(success, "Transfer failed in multicall");
        
        console.log("Transfer successful in multicall");
    }
}

/**
 * @dev Mock regular contract for testing call() vs delegatecall()
 */
contract MockRegularContract {
    string public lastMessage;
    
    function doSomething(string calldata message) external {
        lastMessage = message;
        console.log("Regular contract called with:", message);
        console.log("msg.sender:", msg.sender);
    }
} 