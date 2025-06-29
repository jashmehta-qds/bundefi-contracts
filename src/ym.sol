// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableMap.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title YieldMaxCCIP - Defensive Cross-Chain Execution with Safety Features
/// @notice Uses chain-only validation for scalability - any user from allowlisted chains can interact
/// @dev Removed individual sender validation to improve UX and reduce management overhead
contract YieldMaxCCIP is CCIPReceiver {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    // Custom errors for better revert messages
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error OnlySelf();
    error MessageNotFailed(bytes32 messageId);
    error Unauthorized();
    error GasLimitTooLow(uint256 provided, uint256 minimum);
    error GasLimitTooHigh(uint256 provided, uint256 maximum);

    // Error codes for failed messages
    enum ErrorCode {
        RESOLVED,
        FAILED
    }

    struct FailedMessage {
        bytes32 messageId;
        ErrorCode errorCode;
    }

    address immutable i_router;
    address immutable i_executorTemplate;
    address public owner;
    
    // Gas limit safety bounds
    uint256 public constant MIN_GAS_LIMIT = 21_000;     // Minimum for basic operations
    uint256 public constant MAX_GAS_LIMIT = 5_000_000;  // Maximum to prevent abuse
    
    // Allowlisting mappings
    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    
    // Security mappings
    mapping(bytes32 => bool) public usedPayloads;
    mapping(address => uint256) public pendingEscrowNative;
    mapping(address => mapping(address => uint256)) public pendingEscrowERC20;
    
    // Failed message recovery system
    mapping(bytes32 messageId => Client.Any2EVMMessage contents) public s_messageContents;
    EnumerableMap.Bytes32ToUintMap internal s_failedMessages;
    
    // Multicall contract registry - tracks which contracts should use delegatecall
    mapping(address => bool) public isMulticallContract;

    // Events
    event CrossTxExecuted(address indexed sender, address indexed target, uint256 value, bytes data);
    event EscrowRescued(address indexed user, uint256 amount);
    event ERC20EscrowRescued(address indexed user, address token, uint256 amount);
    event ERC20Received(address indexed token, address indexed sender, uint256 amount);
    event ExecutorCreated(address indexed executor, address indexed target, uint256 deadline);
    event ExecutorReused(address indexed executor, address indexed target, uint256 deadline);
    event ExecutorExecuted(address indexed executor, bool success);
    event MessageFailed(bytes32 indexed messageId, bytes reason);
    event MessageRecovered(bytes32 indexed messageId);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    modifier onlyAllowlistedSourceChain(uint64 _sourceChainSelector) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    constructor(address router) CCIPReceiver(router) {
        i_router = router;
        owner = msg.sender;
        
        // Deploy the executor template once during construction
        i_executorTemplate = address(new ExecutorTemplate());
        
        // Initialize default multicall contracts
        isMulticallContract[0xcA11bde05977b3631167028862bE2a173976CA11] = true; // Multicall3
        
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // Allowlisting functions
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    // Removed setApprovedTarget - no longer needed with executor pattern

    /// @notice Validate gas limit is within safety bounds
    /// @param gasLimit The gas limit to validate
    function _validateGasLimit(uint256 gasLimit) internal pure {
        if (gasLimit < MIN_GAS_LIMIT) revert GasLimitTooLow(gasLimit, MIN_GAS_LIMIT);
        if (gasLimit > MAX_GAS_LIMIT) revert GasLimitTooHigh(gasLimit, MAX_GAS_LIMIT);
    }

    function sendCrossChainExecution(
        uint64 destinationChainSelector,
        address receiver,
        address targetContract,
        uint256 value,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts,
        bytes calldata callData,
        uint256 gasLimit
    ) external payable onlyAllowlistedDestinationChain(destinationChainSelector) {
        require(tokenAddresses.length == tokenAmounts.length, "Token input mismatch");
        _validateGasLimit(gasLimit);

        // Escrow and prepare tokens
        _handleTokenEscrow(tokenAddresses, tokenAmounts);
        
        // Send the message and handle escrow
        _sendMessage(
            destinationChainSelector,
            receiver,
            targetContract,
            value,
            tokenAddresses,
            tokenAmounts,
            callData,
            gasLimit
        );
    }



    /// @notice Internal function to send CCIP message and handle escrow
    function _sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        address targetContract,
        uint256 value,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts,
        bytes calldata callData,
        uint256 gasLimit
    ) internal {
        Client.EVM2AnyMessage memory message = _buildMessage(
            receiver,
            targetContract,
            value,
            tokenAddresses,
            tokenAmounts,
            callData,
            gasLimit
        );

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);
        if (msg.value < fee + value) revert NotEnoughBalance(msg.value, fee + value);

        // Track native escrow
        pendingEscrowNative[msg.sender] += value + fee;

        // Send the message
        IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);

        // Update escrows only after successful send
        pendingEscrowNative[msg.sender] -= value + fee;
        _clearTokenEscrow(tokenAddresses, tokenAmounts);
    }

    function _handleTokenEscrow(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts
    ) internal {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            IERC20(tokenAddresses[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
            IERC20(tokenAddresses[i]).approve(i_router, tokenAmounts[i]);
            pendingEscrowERC20[msg.sender][tokenAddresses[i]] += tokenAmounts[i];
        }
    }

    function _clearTokenEscrow(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts
    ) internal {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            pendingEscrowERC20[msg.sender][tokenAddresses[i]] -= tokenAmounts[i];
        }
    }

    function _buildMessage(
        address receiver,
        address targetContract,
        uint256 value,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts,
        bytes calldata callData,
        uint256 gasLimit
    ) internal view returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            tokens[i] = Client.EVMTokenAmount({token: tokenAddresses[i], amount: tokenAmounts[i]});
        }

        bytes memory payload = abi.encode(targetContract, value, callData, msg.sender);

        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: payload,
            tokenAmounts: tokens,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: gasLimit,
                    allowOutOfOrderExecution: false
                })
            ),
            feeToken: address(0) // fee in native ETH
        });
    }

    function estimateFee(
        uint64 destinationChainSelector,
        address receiver,
        address targetContract,
        uint256 value,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts,
        bytes calldata callData,
        uint256 gasLimit
    ) external view returns (uint256) {
        require(tokenAddresses.length == tokenAmounts.length, "Token input mismatch");
        _validateGasLimit(gasLimit);

        Client.EVM2AnyMessage memory message = _buildMessage(
            receiver,
            targetContract,
            value,
            tokenAddresses,
            tokenAmounts,
            callData,
            gasLimit
        );

        return IRouterClient(i_router).getFee(destinationChainSelector, message);
    }

    /// @notice The entrypoint for the CCIP router to call. This function should
    /// never revert, all errors should be handled internally in this contract.
    function ccipReceive(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external override onlyRouter onlyAllowlistedSourceChain(
        any2EvmMessage.sourceChainSelector
    ) {
        /* solhint-disable no-empty-blocks */
        try this.processMessage(any2EvmMessage) {
            // Intentionally empty - success case
        } catch (bytes memory err) {
            s_failedMessages.set(any2EvmMessage.messageId, uint256(ErrorCode.FAILED));
            s_messageContents[any2EvmMessage.messageId] = any2EvmMessage;
            emit MessageFailed(any2EvmMessage.messageId, err);
            return;
        }
    }

    /// @notice Processes incoming messages with proper validation
    function processMessage(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external onlySelf onlyAllowlistedSourceChain(
        any2EvmMessage.sourceChainSelector
    ) {
        _ccipReceive(any2EvmMessage);
    }

    /// @notice Generate deterministic salt for executor deployment
    /// @param sender The address that will send the cross-chain message
    /// @return salt The deterministic salt for executor deployment
    function _generateExecutorSalt(address sender) internal view returns (bytes32 salt) {
        return keccak256(abi.encode(sender, address(this)));
    }

    /// @notice Get or create executor for a sender and target
    /// @param sender The address that sent the cross-chain message
    /// @param target The target contract address for execution
    /// @return executor The executor instance ready for use
    function _getOrCreateExecutor(address sender, address target) internal returns (ExecutorTemplate executor) {
        // Create deterministic salt and get predicted address
        bytes32 salt = _generateExecutorSalt(sender);
        address executorAddress = Clones.predictDeterministicAddress(i_executorTemplate, salt, address(this));
        
        // Check if executor already exists
        bool executorExists = executorAddress.code.length > 0;
        
        uint256 deadline = block.timestamp + 1 hours;
        
        if (!executorExists) {
            // Create new executor instance using deterministic deployment
            executorAddress = Clones.cloneDeterministic(i_executorTemplate, salt);
            executor = ExecutorTemplate(payable(executorAddress));
            executor.initialize(target, deadline);
            emit ExecutorCreated(address(executor), target, deadline);
        } else {
            // Reuse existing executor - reinitialize for new execution
            executor = ExecutorTemplate(payable(executorAddress));
            
            // Check if executor is available for reuse (not currently executing)
            if (executor.isInitialized()) {
                // If still initialized, it means previous execution is still pending
                // We can extend the deadline or handle this case
                require(block.timestamp >= executor.deadline(), "Executor still busy");
                
                // Force cleanup of previous execution if deadline passed
                executor.recoverTokens(address(this));
            }
            
            // Initialize for new execution
            executor.initialize(target, deadline);
            emit ExecutorReused(address(executor), target, deadline);
        }
        
        return executor;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        bytes32 hash = keccak256(message.data);
        require(!usedPayloads[hash], "Replay detected");
        usedPayloads[hash] = true;

        (address target, uint256 value, bytes memory callData, address sender) =
            abi.decode(message.data, (address, uint256, bytes, address));

        // Get or create executor for this sender and target
        ExecutorTemplate executor = _getOrCreateExecutor(sender, target);

        // Transfer tokens to isolated executor and register for tracking
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            address token = message.destTokenAmounts[i].token;
            uint256 amount = message.destTokenAmounts[i].amount;
            
            emit ERC20Received(token, sender, amount);
            IERC20(token).safeTransfer(address(executor), amount);
            
            // Register token with executor for proper cleanup
            executor.addTrackedToken(token);
        }

        // Execute in isolated environment with automatic cleanup
        try executor.executeAndCleanup{value: value}(callData) {
            emit ExecutorExecuted(address(executor), true);
            emit CrossTxExecuted(sender, target, value, callData);
        } catch {
            // Auto-recovery on failure - executor will return tokens to this contract
            emit ExecutorExecuted(address(executor), false);
            executor.recoverTokens(address(this));
        }
    }

    /// @notice Allows the owner to retry a failed message
    function retryFailedMessage(
        bytes32 messageId,
        address tokenReceiver
    ) external onlyOwner {
        if (s_failedMessages.get(messageId) != uint256(ErrorCode.FAILED))
            revert MessageNotFailed(messageId);

        s_failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

        Client.Any2EVMMessage memory message = s_messageContents[messageId];

        // Transfer any tokens to the specified receiver as an escape hatch
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            IERC20(message.destTokenAmounts[i].token).safeTransfer(
                tokenReceiver,
                message.destTokenAmounts[i].amount
            );
        }

        emit MessageRecovered(messageId);
    }

    /// @notice Get paginated list of failed messages
    function getFailedMessages(
        uint256 offset,
        uint256 limit
    ) external view returns (FailedMessage[] memory) {
        uint256 length = s_failedMessages.length();
        uint256 returnLength = (offset + limit > length) ? length - offset : limit;
        FailedMessage[] memory failedMessages = new FailedMessage[](returnLength);

        for (uint256 i = 0; i < returnLength; i++) {
            (bytes32 messageId, uint256 errorCode) = s_failedMessages.at(offset + i);
            failedMessages[i] = FailedMessage(messageId, ErrorCode(errorCode));
        }
        return failedMessages;
    }

    function rescueEscrow() external {
        uint256 amount = pendingEscrowNative[msg.sender];
        require(amount > 0, "No native escrow to rescue");
        pendingEscrowNative[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdraw failed");
        emit EscrowRescued(msg.sender, amount);
    }

    function rescueERC20Escrow(address token) external {
        uint256 amount = pendingEscrowERC20[msg.sender][token];
        require(amount > 0, "No token escrow to rescue");
        pendingEscrowERC20[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit ERC20EscrowRescued(msg.sender, token, amount);
    }

    /// @notice Emergency withdrawal function for owner
    function emergencyWithdraw(address beneficiary) external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "Nothing to withdraw");
        (bool sent, ) = beneficiary.call{value: amount}("");
        require(sent, "Withdraw failed");
    }

    /// @notice Emergency token withdrawal function for owner
    function emergencyWithdrawToken(address beneficiary, address token) external onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "Nothing to withdraw");
        IERC20(token).safeTransfer(beneficiary, amount);
    }

    /// @notice Predict the executor address for a given sender
    /// @param sender The address that will send the cross-chain message
    /// @return The predicted executor address
    function predictExecutorAddress(address sender) external view returns (address) {
        bytes32 salt = _generateExecutorSalt(sender);
        return Clones.predictDeterministicAddress(i_executorTemplate, salt, address(this));
    }
    
    /// @notice Update multicall contract registry
    /// @param contractAddress The contract address to register/unregister
    /// @param _isMulticall Whether this contract should use delegatecall
    function setMulticallContract(address contractAddress, bool _isMulticall) external onlyOwner {
        isMulticallContract[contractAddress] = _isMulticall;
    }

    receive() external payable {}
}

/// @title IExecutor - Interface for executor contracts
interface IExecutor {
    function initialize(address target, uint256 deadline) external;
    function executeAndCleanup(bytes calldata data) external payable;
    function recoverTokens(address recipient) external;
}

/// @title ExecutorTemplate - Isolated execution environment for cross-chain calls
contract ExecutorTemplate is IExecutor {
    using SafeERC20 for IERC20;
    
    address public yieldMax;
    address public target;
    uint256 public deadline;
    bool private initialized;
    
    // Track tokens sent to this executor for proper cleanup
    address[] public trackedTokens;
    
    error NotInitialized();
    error AlreadyInitialized();
    error Unauthorized();
    error DeadlineExceeded();
    error ExecutionFailed();
    
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
    
    function initialize(address _target, uint256 _deadline) external override {
        if (initialized) revert AlreadyInitialized();
        
        yieldMax = msg.sender;
        target = _target;
        deadline = _deadline;
        initialized = true;
    }
    
    /// @notice Check if executor is currently initialized
    function isInitialized() external view returns (bool) {
        return initialized;
    }
    
    function executeAndCleanup(bytes calldata data) external payable override 
        onlyYieldMax 
        onlyInitialized 
        beforeDeadline 
    {
        // Execute target call with appropriate calling method
        bool success;
        
        // Use delegatecall for registered multicall contracts to preserve msg.sender context
        // This ensures token approvals/transfers work correctly with executor as msg.sender
        if (YieldMaxCCIP(payable(yieldMax)).isMulticallContract(target)) {
            // For multicall contracts, use delegatecall to preserve executor context
            // msg.sender will be the executor, allowing it to approve/transfer its own tokens
            (success, ) = target.delegatecall(data);
        } else {
            // For regular contracts, use call as before
            (success, ) = target.call{value: msg.value}(data);
        }
        
        if (!success) revert ExecutionFailed();
        
        // Auto-cleanup: return remaining assets (ETH + ERC20) to YieldMax
        _returnAllAssets();
        
        // Mark as completed (tokens should be consumed by target execution)
        initialized = false;
    }
    
    function recoverTokens(address /* recipient */) external override onlyYieldMax onlyInitialized {
        // Emergency recovery function - return all remaining assets
        _returnAllAssets();
        
        // Mark as completed
        initialized = false;
    }
    
    function _returnAllETH() private {
        // Return any remaining ETH to YieldMax
        if (address(this).balance > 0) {
            (bool success, ) = yieldMax.call{value: address(this).balance}("");
            require(success, "ETH transfer failed");
        }
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
        _returnAllETH();
    }
    

    
    /// @notice Register a token for tracking (called by YieldMaxCCIP)
    function addTrackedToken(address token) external {
        require(msg.sender == yieldMax, "Only YieldMax can add tokens");
        trackedTokens.push(token);
    }
    
    // Allow receiving ETH
    receive() external payable {}
}

/// @dev Test contract to validate remote execution
contract EchoContract {
    event Echo(string msg, uint256 amount);

    function echo(string calldata msg_) external payable {
        emit Echo(msg_, msg.value);
    }
}

/// @dev Test contract that can use approved ERC20 tokens
contract TokenSpenderContract {
    using SafeERC20 for IERC20;
    
    event TokensUsed(address indexed token, uint256 amount, address indexed from);
    event TokensTransferred(address indexed token, uint256 amount, address indexed to);

    /// @notice Use approved tokens by transferring them to this contract
    function useApprovedTokens(address token, uint256 amount, address from) external {
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit TokensUsed(token, amount, from);
    }

    /// @notice Transfer tokens from this contract to another address
    function transferTokens(address token, uint256 amount, address to) external {
        IERC20(token).safeTransfer(to, amount);
        emit TokensTransferred(token, amount, to);
    }

    /// @notice Combined function: use approved tokens and transfer them to recipient
    function useAndTransferTokens(
        address token, 
        uint256 amount, 
        address from, 
        address to
    ) external {
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit TokensUsed(token, amount, from);
        
        IERC20(token).safeTransfer(to, amount);
        emit TokensTransferred(token, amount, to);
    }

    /// @notice Echo function that also uses approved tokens
    function echoAndUseTokens(
        string calldata msg_,
        address token,
        uint256 amount,
        address from,
        address to
    ) external payable {
        // Use the approved tokens
        if (amount > 0 && token != address(0)) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
            emit TokensUsed(token, amount, from);
            
            if (to != address(0)) {
                IERC20(token).safeTransfer(to, amount);
                emit TokensTransferred(token, amount, to);
            }
        }
        
        // Echo the message
        emit EchoContract.Echo(msg_, msg.value);
    }
}
