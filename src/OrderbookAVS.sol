
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IAvsLogic.sol";
import "./interface/IAttestationCenter.sol";

/**
 * @title OrderbookAVS
 * @dev Manages escrowed funds for limit orders in the SwapbookV2 system
 * @notice Users can deposit and withdraw funds that are held in escrow for limit orders
 */
contract OrderbookAVS is Ownable, IAvsLogic {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    // Task Types
    enum TaskType {
        NoOp,             // 0: Order does not cross spread and is not best price
        UpdateBestPrice,  // 1: Order does not cross spread but is best price OR best price order cancelled
        PartialFill,      // 2: Order crosses spread and partially fills best price
        CompleteFill,     // 3: Order crosses spread and completely fills best price, also update best price
        ProcessWithdrawal // 4: User requested withdrawal, send money back
    }

    // Task Data Structures
    struct OrderInfo {
        address user;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        int24 tick;
        bool zeroForOne;
        uint256 orderId;
    }

    struct WithdrawalInfo {
        address user;
        address token;
        uint256 amount;
    }

    // Events
    event FundsDeposited(address indexed user, address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed user, address indexed token, uint256 amount);
    event FundsTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);
    event TaskProcessed(uint256 indexed taskId, TaskType taskType, bool success);
    event OrderExecuted(address indexed user, uint256 indexed orderId, uint256 amount0, uint256 amount1);
    event BestPriceUpdated(address indexed token0, address indexed token1, int24 newBestTick, bool zeroForOne);
    event WithdrawalProcessed(address indexed user, address indexed token, uint256 amount);

    // State variables
    mapping(address => mapping(address => uint256)) public escrowedFunds; // user => token => amount
    mapping(address => bool) public authorizedOperators; // contracts that can transfer funds

    // Modifiers
    modifier onlyAuthorized() {
        require(authorizedOperators[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }


    /**
     * @dev Deposit funds to be held in escrow for limit orders
     * @param token The token contract address
     * @param amount The amount to deposit
     */
    function depositFunds(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        escrowedFunds[msg.sender][token] += amount;
        
        emit FundsDeposited(msg.sender, token, amount);
    }

    /**
     * @dev Withdraw funds from escrow
     * @param token The token contract address
     * @param amount The amount to withdraw
     */
    function withdrawFunds(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        require(escrowedFunds[msg.sender][token] >= amount, "Insufficient escrowed funds");
        
        escrowedFunds[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit FundsWithdrawn(msg.sender, token, amount);
    }

    /**
     * @dev Transfer funds between users (for order execution)
     * @param from The user to transfer from
     * @param to The user to transfer to
     * @param token The token contract address
     * @param amount The amount to transfer
     */
    function transferFunds(
        address from,
        address to,
        address token,
        uint256 amount
    ) external onlyAuthorized {
        _transferFunds(from, to, token, amount);
    }

    function _transferFunds(
        address from,
        address to,
        address token,
        uint256 amount
    ) internal {
        require(from != address(0), "Invalid from address");
        require(to != address(0), "Invalid to address");
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        require(escrowedFunds[from][token] >= amount, "Insufficient escrowed funds");
        
        escrowedFunds[from][token] -= amount;
        escrowedFunds[to][token] += amount;
        
        emit FundsTransferred(from, to, token, amount);
    }

    /**
     * @dev Get the escrowed balance for a user and token
     * @param user The user address
     * @param token The token contract address
     * @return The escrowed balance
     */
    function getEscrowedBalance(address user, address token) external view returns (uint256) {
        return escrowedFunds[user][token];
    }

    /**
     * @dev Authorize an operator (like SwapbookV2 contract) to transfer funds
     * @param operator The operator address
     * @param authorized Whether to authorize or revoke authorization
     */
    function setAuthorizedOperator(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        authorizedOperators[operator] = authorized;
    }

    /**
     * @dev Process tasks submitted to the AVS
     * @param _taskInfo The task information from the attestation center
     * @param _isApproved Whether the task is approved by attesters
     * @param _tpSignature Task proposer signature
     * @param _taSignature Task attestation signature
     * @param _attestersIds Array of attester IDs
     */
    function afterTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external override {
        require(_isApproved, "Task not approved by attesters");
        
        // Decode task data to get task type and parameters
        (TaskType taskType, bytes memory taskData) = abi.decode(_taskInfo.taskData, (TaskType, bytes));
        
        bool success = false;
        
        if (taskType == TaskType.NoOp) {
            // Task 1: No-op - Order does not cross spread and is not best price
            // No action needed, just log the task
            success = true;
            emit TaskProcessed(_taskInfo.taskId, taskType, success);
            
        } else if (taskType == TaskType.UpdateBestPrice) {
            // Task 2: Update best price - Order does not cross spread but is best price OR best price order cancelled
            (address token0, address token1, int24 newBestTick, bool zeroForOne) = 
                abi.decode(taskData, (address, address, int24, bool));
            
            // Update best price logic would go here
            // For now, just emit the event
            emit BestPriceUpdated(token0, token1, newBestTick, zeroForOne);
            success = true;
            emit TaskProcessed(_taskInfo.taskId, taskType, success);
            
        } else if (taskType == TaskType.PartialFill) {
            // Task 3: Partial fill - Order crosses spread and partially fills best price
            (OrderInfo memory order, uint256 fillAmount0, uint256 fillAmount1) = 
                abi.decode(taskData, (OrderInfo, uint256, uint256));
            
            // Transfer partial amounts between users
            if (order.zeroForOne) {
                // Selling token0 for token1
                _transferFunds(order.user, _taskInfo.taskSubmitter, order.token0, fillAmount0);
                _transferFunds(_taskInfo.taskSubmitter, order.user, order.token1, fillAmount1);
            } else {
                // Selling token1 for token0
                _transferFunds(order.user, _taskInfo.taskSubmitter, order.token1, fillAmount1);
                _transferFunds(_taskInfo.taskSubmitter, order.user, order.token0, fillAmount0);
            }
            
            emit OrderExecuted(order.user, order.orderId, fillAmount0, fillAmount1);
            success = true;
            emit TaskProcessed(_taskInfo.taskId, taskType, success);
            
        } else if (taskType == TaskType.CompleteFill) {
            // Task 4: Complete fill - Order crosses spread and completely fills best price, also update best price
            (OrderInfo memory order, OrderInfo memory nextOrder, uint256 fillAmount0, uint256 fillAmount1) = 
                abi.decode(taskData, (OrderInfo, OrderInfo, uint256, uint256));
            
            // Transfer complete amounts between users
            if (order.zeroForOne) {
                // Selling token0 for token1
                _transferFunds(order.user, _taskInfo.taskSubmitter, order.token0, fillAmount0);
                _transferFunds(_taskInfo.taskSubmitter, order.user, order.token1, fillAmount1);
            } else {
                // Selling token1 for token0
                _transferFunds(order.user, _taskInfo.taskSubmitter, order.token1, fillAmount1);
                _transferFunds(_taskInfo.taskSubmitter, order.user, order.token0, fillAmount0);
            }
            
            // Update best price to next order
            if (nextOrder.user != address(0)) {
                emit BestPriceUpdated(nextOrder.token0, nextOrder.token1, nextOrder.tick, nextOrder.zeroForOne);
            }
            
            emit OrderExecuted(order.user, order.orderId, fillAmount0, fillAmount1);
            success = true;
            emit TaskProcessed(_taskInfo.taskId, taskType, success);
            
        } else if (taskType == TaskType.ProcessWithdrawal) {
            // Task 5: Process withdrawal - User requested withdrawal, send money back
            WithdrawalInfo memory withdrawal = abi.decode(taskData, (WithdrawalInfo));
            
            // Process the withdrawal
            require(escrowedFunds[withdrawal.user][withdrawal.token] >= withdrawal.amount, "Insufficient escrowed funds");
            escrowedFunds[withdrawal.user][withdrawal.token] -= withdrawal.amount;
            IERC20(withdrawal.token).safeTransfer(withdrawal.user, withdrawal.amount);
            
            emit WithdrawalProcessed(withdrawal.user, withdrawal.token, withdrawal.amount);
            success = true;
            emit TaskProcessed(_taskInfo.taskId, taskType, success);
        }
        
        require(success, "Task processing failed");
    }

    /**
     * @dev Process tasks before submission (placeholder)
     */
    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external override {
        // Placeholder for before task submission logic
        // Could include validation, pre-processing, etc.
    }

}
