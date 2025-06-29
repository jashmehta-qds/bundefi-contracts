// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Storage {
    uint256 public value;
    address public sender;
    address public owner;
    
    function setValue(uint256 _value) external {
        value = _value;
        sender = msg.sender;
        owner = address(this);
    }
}

contract Logic {
    uint256 public value;
    address public sender; 
    address public owner;
    
    function setValue(uint256 _value) external {
        value = _value;
        sender = msg.sender;
        owner = address(this);
    }
}

contract Caller {
    uint256 public value;
    address public sender;
    address public owner;
    
    Storage public storageContract;
    Logic public logicContract;
    
    constructor() {
        storageContract = new Storage();
        logicContract = new Logic();
    }
    
    // Regular call - executes in Storage contract's context
    function regularCall(uint256 _value) external {
        storageContract.setValue(_value);
        // After this call:
        // - storageContract.value = _value
        // - storageContract.sender = address(this) [Caller contract]
        // - storageContract.owner = address(storageContract)
        // - THIS contract's storage is unchanged
    }
    
    // Delegatecall - executes Logic contract's code in THIS contract's context
    function delegateCall(uint256 _value) external {
        (bool success,) = address(logicContract).delegatecall(
            abi.encodeWithSignature("setValue(uint256)", _value)
        );
        require(success, "Delegatecall failed");
        
        // After this call:
        // - THIS contract's value = _value
        // - THIS contract's sender = msg.sender [original caller]
        // - THIS contract's owner = address(this) [this Caller contract]
        // - logicContract's storage is unchanged
    }
} 