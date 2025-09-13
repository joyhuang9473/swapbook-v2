
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "./interface/IAvsLogic.sol";
import "./interface/IAttestationCenter.sol";
import "./SwapbookV2.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/interfaces/IPoolManager.sol";

// Callback interface for order execution
interface IOrderbookCallback {
    function onOrderExecuted(
        address token0,
        address token1,
        address bestOrderUser,
        address swapper,
        uint256 inputAmount,
        uint256 outputAmount,
        bool zeroForOne
    ) external;
}

/**
 * @title OrderbookAVS
 * @dev Manages escrowed funds for limit orders in the SwapbookV2 system
 * @notice Users can deposit and withdraw funds that are held in escrow for limit orders
 */
contract OrderbookAVS is Ownable, IAvsLogic, IERC1155Receiver {
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
    event OrderExecutionCallback(address indexed token0, address indexed token1, address indexed bestOrderUser, address swapper, uint256 inputAmount, uint256 outputAmount, bool zeroForOne);

    // State variables
    mapping(address => mapping(address => uint256)) public escrowedFunds; // user => token => amount
    mapping(address => bool) public authorizedOperators; // contracts that can transfer funds
    SwapbookV2 public swapbookV2; // Reference to SwapbookV2 contract
    
    // Best order tracking
    mapping(address => mapping(address => address)) public bestOrderUsers; // token0 => token1 => user
    mapping(address => mapping(address => int24)) public bestOrderTicks; // token0 => token1 => tick
    mapping(address => mapping(address => bool)) public bestOrderDirections; // token0 => token1 => zeroForOne

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
     * @dev Set the SwapbookV2 contract address
     * @param _swapbookV2 The SwapbookV2 contract address
     */
    function setSwapbookV2(address _swapbookV2) external onlyOwner {
        require(_swapbookV2 != address(0), "Invalid SwapbookV2 address");
        swapbookV2 = SwapbookV2(_swapbookV2);
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
        (TaskType taskType, bytes memory taskData) = abi.decode(_taskInfo.data, (TaskType, bytes));
        
        bool success = _processTask(_taskInfo.taskDefinitionId, taskType, taskData);
        require(success, "Task processing failed");
    }

    function _processTask(uint256 taskId, TaskType taskType, bytes memory taskData) internal returns (bool) {
        if (taskType == TaskType.NoOp) {
            return _processNoOp(taskId);
        } else if (taskType == TaskType.UpdateBestPrice) {
            return _processUpdateBestPrice(taskId, taskData);
        } else if (taskType == TaskType.PartialFill) {
            return _processPartialFill(taskId, taskData);
        } else if (taskType == TaskType.CompleteFill) {
            return _processCompleteFill(taskId, taskData);
        } else if (taskType == TaskType.ProcessWithdrawal) {
            return _processWithdrawal(taskId, taskData);
        }
        return false;
    }

    function _processNoOp(uint256 taskId) internal returns (bool) {
        emit TaskProcessed(taskId, TaskType.NoOp, true);
        return true;
    }

    function _processUpdateBestPrice(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (address token0, address token1, int24 newBestTick, bool zeroForOne, uint256 amount, address user) = 
            abi.decode(taskData, (address, address, int24, bool, uint256, address));
        
        // Store the best order information in OrderbookAVS
        bestOrderUsers[token0][token1] = user;
        bestOrderTicks[token0][token1] = newBestTick;
        bestOrderDirections[token0][token1] = zeroForOne;
        
        // Also place the order in SwapbookV2 to record bestTicks for re-routing
        if (address(swapbookV2) != address(0)) {
            // Place order in SwapbookV2
            swapbookV2.placeOrder(
                PoolKey({
                    currency0: Currency.wrap(token0),
                    currency1: Currency.wrap(token1),
                    fee: 3000, // Default fee tier
                    tickSpacing: 60,
                    hooks: IHooks(address(swapbookV2))
                }),
                newBestTick,
                zeroForOne,
                amount
            );
        }
        
        emit BestPriceUpdated(token0, token1, newBestTick, zeroForOne);
        emit TaskProcessed(taskId, TaskType.UpdateBestPrice, true);
        return true;
    }

    function _processPartialFill(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (OrderInfo memory order, uint256 fillAmount0, uint256 fillAmount1) = 
            abi.decode(taskData, (OrderInfo, uint256, uint256));
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(order.token0),
            currency1: Currency.wrap(order.token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        // swapbookV2.executeOrderPublic(key, order.tick, order.zeroForOne, fillAmount0);
        
        if (order.zeroForOne) {
            _transferFunds(order.user, address(this), order.token0, fillAmount0);
            _transferFunds(address(this), order.user, order.token1, fillAmount1);
        } else {
            _transferFunds(order.user, address(this), order.token1, fillAmount1);
            _transferFunds(address(this), order.user, order.token0, fillAmount0);
        }
        
        emit OrderExecuted(order.user, order.orderId, fillAmount0, fillAmount1);
        emit TaskProcessed(taskId, TaskType.PartialFill, true);
        return true;
    }

    function _processCompleteFill(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (OrderInfo memory incomingOrder, uint256 fillAmount0, uint256 fillAmount1, OrderInfo memory newBestOrder) = 
            abi.decode(taskData, (OrderInfo, uint256, uint256, OrderInfo));
        
        // Get the best order user from storage
        address bestOrderUser = bestOrderUsers[incomingOrder.token0][incomingOrder.token1];
        require(bestOrderUser != address(0), "No best order found");
        
        // Direct peer-to-peer token exchange between incoming order and best order
        if (incomingOrder.zeroForOne) {
            // Incoming order is selling token0 for token1, best order is selling token1 for token0
            // Transfer token0 from incoming order user to best order user
            _transferFunds(incomingOrder.user, bestOrderUser, incomingOrder.token0, fillAmount0);
            // Transfer token1 from best order user to incoming order user
            _transferFunds(bestOrderUser, incomingOrder.user, incomingOrder.token1, fillAmount1);
        } else {
            // Incoming order is selling token1 for token0, best order is selling token0 for token1
            // Transfer token1 from incoming order user to best order user
            _transferFunds(incomingOrder.user, bestOrderUser, incomingOrder.token1, fillAmount1);
            // Transfer token0 from best order user to incoming order user
            _transferFunds(bestOrderUser, incomingOrder.user, incomingOrder.token0, fillAmount0);
        }
        
        // Update best order if newBestOrder is provided and valid
        if (newBestOrder.user != address(0)) {
            bestOrderUsers[newBestOrder.token0][newBestOrder.token1] = newBestOrder.user;
            bestOrderTicks[newBestOrder.token0][newBestOrder.token1] = newBestOrder.tick;
            bestOrderDirections[newBestOrder.token0][newBestOrder.token1] = newBestOrder.zeroForOne;
            emit BestPriceUpdated(newBestOrder.token0, newBestOrder.token1, newBestOrder.tick, newBestOrder.zeroForOne);
        } else {
            // Clear best order if no new best order provided
            bestOrderUsers[incomingOrder.token0][incomingOrder.token1] = address(0);
            bestOrderTicks[incomingOrder.token0][incomingOrder.token1] = 0;
            bestOrderDirections[incomingOrder.token0][incomingOrder.token1] = false;
        }
        
        emit OrderExecuted(incomingOrder.user, incomingOrder.orderId, fillAmount0, fillAmount1);
        emit TaskProcessed(taskId, TaskType.CompleteFill, true);
        return true;
    }

    function _processWithdrawal(uint256 taskId, bytes memory taskData) internal returns (bool) {
        WithdrawalInfo memory withdrawal = abi.decode(taskData, (WithdrawalInfo));
        
        require(escrowedFunds[withdrawal.user][withdrawal.token] >= withdrawal.amount, "Insufficient escrowed funds");
        escrowedFunds[withdrawal.user][withdrawal.token] -= withdrawal.amount;
        IERC20(withdrawal.token).safeTransfer(withdrawal.user, withdrawal.amount);
        
        emit WithdrawalProcessed(withdrawal.user, withdrawal.token, withdrawal.amount);
        emit TaskProcessed(taskId, TaskType.ProcessWithdrawal, true);
        return true;
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

    // Callback implementation for order execution
    function onOrderExecuted(
        address token0,
        address token1,
        address bestOrderUser,
        address swapper,
        uint256 inputAmount,
        uint256 outputAmount,
        bool zeroForOne
    ) external {
        // Only allow SwapbookV2 to call this function
        require(msg.sender == address(swapbookV2), "Only SwapbookV2 can call this function");
        
        // Emit event to show that SwapbookV2 is calling the onOrderExecuted callback
        emit OrderExecutionCallback(token0, token1, bestOrderUser, swapper, inputAmount, outputAmount, zeroForOne);
        
        // Get the original tick from our stored data instead of SwapbookV2
        // (because SwapbookV2 clears the best tick after execution)
        int24 originalTick = bestOrderTicks[token0][token1];

        // Redeem the token by calling redeem function in SwapbookV2
        // Use the original tick where the order was placed
        swapbookV2.redeem(
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: 3000,
                tickSpacing: 60,
                hooks: IHooks(address(swapbookV2))
            }),
            originalTick, // Use the original tick where the order was placed
            zeroForOne,
            inputAmount
        );

        // Note: We handle the order execution directly without using the task system
        // This is a callback from SwapbookV2 when an order is executed

        // Handle the order execution directly without using the task system
        // This is a callback from SwapbookV2 when an order is executed
        
        // Calculate the correct amounts for the transfer
        uint256 fillAmount0;
        uint256 fillAmount1;
        
        console.log("onOrderExecuted - inputAmount:", inputAmount);
        console.log("onOrderExecuted - outputAmount:", outputAmount);
        console.log("onOrderExecuted - zeroForOne:", zeroForOne);
        
        if (zeroForOne) {
            // User1's order was selling token0 for token1
            fillAmount0 = inputAmount;  // Amount of token0 User1 sold
            fillAmount1 = outputAmount; // Amount of token1 User1 received
        } else {
            // User1's order was selling token1 for token0
            fillAmount0 = outputAmount; // Amount of token0 User1 received
            fillAmount1 = inputAmount;  // Amount of token1 User1 sold
        }
        
        console.log("onOrderExecuted - fillAmount0:", fillAmount0);
        console.log("onOrderExecuted - fillAmount1:", fillAmount1);
        
        // Update User1's escrow balance to reflect the order execution
        // The swap is already completed in SwapbookV2, so we just need to settle the escrow
        
        if (zeroForOne) {
            // User1 sold token0, received token1
            // Update User1's escrow: reduce token0, increase token1
            escrowedFunds[bestOrderUser][token0] -= fillAmount0;
            escrowedFunds[bestOrderUser][token1] += fillAmount1;
        } else {
            // User1 sold token1, received token0
            // Update User1's escrow: reduce token1, increase token0
            escrowedFunds[bestOrderUser][token1] -= fillAmount1;
            escrowedFunds[bestOrderUser][token0] += fillAmount0;
        }
        
        // Clear the best order since it was completely filled
        bestOrderUsers[token0][token1] = address(0);
        bestOrderTicks[token0][token1] = 0;
        bestOrderDirections[token0][token1] = false;
        
        emit OrderExecuted(bestOrderUser, 0, fillAmount0, fillAmount1);
        emit BestPriceUpdated(token0, token1, 0, false);
    }

    // IERC1155Receiver implementation
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
