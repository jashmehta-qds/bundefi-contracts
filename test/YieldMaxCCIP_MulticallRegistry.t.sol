// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {YieldMaxCCIP} from "../src/ym.sol";

/**
 * @title YieldMax Multicall Registry Test
 * @dev Tests the centralized multicall registry functionality
 */
contract YieldMaxCCIP_MulticallRegistry is Test {
    
    YieldMaxCCIP public yieldMax;
    
    address public owner;
    address public nonOwner = makeAddr("nonOwner");
    
    // Test multicall contracts
    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public customMulticall = makeAddr("customMulticall");
    address public regularContract = makeAddr("regularContract");
    
    function setUp() public {
        owner = address(this);
        
        // Deploy mock router
        address mockRouter = makeAddr("mockRouter");
        
        // Deploy YieldMax
        yieldMax = new YieldMaxCCIP(mockRouter);
        
        console.log("=== Setup Complete ===");
        console.log("YieldMax:", address(yieldMax));
        console.log("Owner:", owner);
    }
    
    /**
     * @dev Test that Multicall3 is initialized as multicall contract
     */
    function test_Multicall3InitializedOnDeploy() public {
        console.log("\n=== TESTING MULTICALL3 INITIALIZATION ===");
        
        bool isMulticall = yieldMax.isMulticallContract(MULTICALL3);
        console.log("Multicall3 registered:", isMulticall);
        
        assertEq(isMulticall, true, "Multicall3 should be registered on deploy");
    }
    
    /**
     * @dev Test adding a new multicall contract
     */
    function test_AddMulticallContract() public {
        console.log("\n=== TESTING ADD MULTICALL CONTRACT ===");
        
        // Initially should not be registered
        bool initialState = yieldMax.isMulticallContract(customMulticall);
        console.log("Custom multicall initial state:", initialState);
        assertEq(initialState, false, "Custom multicall should not be registered initially");
        
        // Add as multicall contract
        yieldMax.setMulticallContract(customMulticall, true);
        
        // Should now be registered
        bool finalState = yieldMax.isMulticallContract(customMulticall);
        console.log("Custom multicall final state:", finalState);
        assertEq(finalState, true, "Custom multicall should be registered after setting");
    }
    
    /**
     * @dev Test removing a multicall contract
     */
    function test_RemoveMulticallContract() public {
        console.log("\n=== TESTING REMOVE MULTICALL CONTRACT ===");
        
        // First add it
        yieldMax.setMulticallContract(customMulticall, true);
        assertEq(yieldMax.isMulticallContract(customMulticall), true, "Should be registered");
        
        // Then remove it
        yieldMax.setMulticallContract(customMulticall, false);
        
        bool finalState = yieldMax.isMulticallContract(customMulticall);
        console.log("Custom multicall after removal:", finalState);
        assertEq(finalState, false, "Custom multicall should not be registered after removal");
    }
    
    /**
     * @dev Test that only owner can update multicall registry
     */
    function test_OnlyOwnerCanUpdateRegistry() public {
        console.log("\n=== TESTING OWNER-ONLY ACCESS ===");
        
        // Non-owner should not be able to update
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        yieldMax.setMulticallContract(customMulticall, true);
        
        // Owner should be able to update
        yieldMax.setMulticallContract(customMulticall, true);
        assertEq(yieldMax.isMulticallContract(customMulticall), true, "Owner should be able to set");
        
        console.log("Access control working correctly");
    }
    
    /**
     * @dev Test multiple contracts in registry
     */
    function test_MultipleContractsInRegistry() public {
        console.log("\n=== TESTING MULTIPLE CONTRACTS ===");
        
        address multicall1 = makeAddr("multicall1");
        address multicall2 = makeAddr("multicall2");
        address multicall3 = makeAddr("multicall3");
        
        // Add multiple multicall contracts
        yieldMax.setMulticallContract(multicall1, true);
        yieldMax.setMulticallContract(multicall2, true);
        yieldMax.setMulticallContract(multicall3, true);
        
        // Verify all are registered
        assertEq(yieldMax.isMulticallContract(multicall1), true, "Multicall1 should be registered");
        assertEq(yieldMax.isMulticallContract(multicall2), true, "Multicall2 should be registered");
        assertEq(yieldMax.isMulticallContract(multicall3), true, "Multicall3 should be registered");
        
        // Verify regular contract is not registered
        assertEq(yieldMax.isMulticallContract(regularContract), false, "Regular contract should not be registered");
        
        // Remove one and verify others remain
        yieldMax.setMulticallContract(multicall2, false);
        assertEq(yieldMax.isMulticallContract(multicall1), true, "Multicall1 should still be registered");
        assertEq(yieldMax.isMulticallContract(multicall2), false, "Multicall2 should be removed");
        assertEq(yieldMax.isMulticallContract(multicall3), true, "Multicall3 should still be registered");
        
        console.log("Multiple contracts managed correctly");
    }
    
    /**
     * @dev Test that Multicall3 can be disabled if needed
     */
    function test_CanDisableMulticall3() public {
        console.log("\n=== TESTING MULTICALL3 DISABLE ===");
        
        // Initially enabled
        assertEq(yieldMax.isMulticallContract(MULTICALL3), true, "Multicall3 should be enabled initially");
        
        // Disable it
        yieldMax.setMulticallContract(MULTICALL3, false);
        assertEq(yieldMax.isMulticallContract(MULTICALL3), false, "Multicall3 should be disabled");
        
        // Re-enable it
        yieldMax.setMulticallContract(MULTICALL3, true);
        assertEq(yieldMax.isMulticallContract(MULTICALL3), true, "Multicall3 should be re-enabled");
        
        console.log("Multicall3 can be toggled successfully");
    }
} 