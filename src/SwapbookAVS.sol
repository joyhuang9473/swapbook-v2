
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {console} from "forge-std/console.sol";
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
 * @title SwapbookAVS
 * @dev Manages escrowed funds for limit orders in the SwapbookV2 system
 * @notice Users can deposit and withdraw funds that are held in escrow for limit orders
 */
contract SwapbookAVS is Ownable, IAvsLogic, IERC1155Receiver {
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
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);

    // State variables
    mapping(address => mapping(address => uint256)) public escrowedFunds; // user => token => amount
    mapping(address => bool) public authorizedOperators; // contracts that can transfer funds
    SwapbookV2 public swapbookV2; // Reference to SwapbookV2 contract
    address public attestationCenter; // Reference to Attestation Center contract
    
    // Best order tracking - now supports both bid and ask orders
    mapping(address => mapping(address => mapping(bool => address))) public bestOrderUsers; // token0 => token1 => zeroForOne => user
    mapping(address => mapping(address => mapping(bool => int24))) public bestOrderTicks; // token0 => token1 => zeroForOne => tick
    mapping(address => mapping(address => mapping(bool => bool))) public bestOrderUseHigherTick; // token0 => token1 => zeroForOne => useHigherTick
    mapping(address => mapping(address => mapping(bool => uint256))) public bestOrderInputAmount; // token0 => token1 => zeroForOne => inputAmount
    mapping(address => mapping(address => mapping(bool => uint256))) public bestOrderOutputAmount; // token0 => token1 => zeroForOne => outputAmount

    // Modifiers
    modifier onlyAuthorized() {
        require(authorizedOperators[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    error OnlyAttestationCenter();

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
     * @dev Set the Attestation Center contract address
     * @param _attestationCenter The Attestation Center contract address
     */
    function setAttestationCenter(address _attestationCenter) external onlyOwner {
        require(_attestationCenter != address(0), "Invalid Attestation Center address");
        attestationCenter = _attestationCenter;
    }

    /**
     * @notice Approve a token for spending by a spender
     * @param token The token address to approve
     * @param spender The address to approve for spending
     * @param amount The amount to approve
     */
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
        emit TokenApproved(token, spender, amount);
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

        if (msg.sender != address(attestationCenter)) revert OnlyAttestationCenter();

        // Decode task data to get task type and parameters
        (TaskType taskType, bytes memory taskData) = abi.decode(_taskInfo.data, (TaskType, bytes));
        
        // Parse task_id from taskData (first parameter)
        uint256 taskId = abi.decode(taskData, (uint256));

        bool success = _processTask(taskId, taskData);
        require(success, "Task processing failed");
    }

    function _processTask(uint256 taskId, bytes memory taskData) internal returns (bool) {
        if (taskId == uint256(TaskType.NoOp)) {
            return _processNoOp(taskId);
        } else if (taskId == uint256(TaskType.UpdateBestPrice)) {
            return _processUpdateBestPrice(taskId, taskData);
        } else if (taskId == uint256(TaskType.PartialFill)) {
            return _processPartialFill(taskId, taskData);
        } else if (taskId == uint256(TaskType.CompleteFill)) {
            return _processCompleteFill(taskId, taskData);
        } else if (taskId == uint256(TaskType.ProcessWithdrawal)) {
            return _processWithdrawal(taskId, taskData);
        }
        return false;
    }

    function _processNoOp(uint256 taskId) internal returns (bool) {
        emit TaskProcessed(taskId, TaskType.NoOp, true);
        return true;
    }

    function _processUpdateBestPrice(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (uint256 task_id, address token0, address token1, int24 newBestTick, bool zeroForOne, uint256 inputAmount, uint256 outputAmount, address user, bool useHigherTick) = 
            abi.decode(taskData, (uint256, address, address, int24, bool, uint256, uint256, address, bool));

        // Store the best order information in OrderbookAVS
        bestOrderUsers[token0][token1][zeroForOne] = user;
        bestOrderTicks[token0][token1][zeroForOne] = newBestTick;
        bestOrderUseHigherTick[token0][token1][zeroForOne] = useHigherTick;
        bestOrderInputAmount[token0][token1][zeroForOne] = inputAmount;
        bestOrderOutputAmount[token0][token1][zeroForOne] = outputAmount;

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
                inputAmount,
                useHigherTick
            );
        }
        
        emit BestPriceUpdated(token0, token1, newBestTick, zeroForOne);
        emit TaskProcessed(taskId, TaskType.UpdateBestPrice, true);
        return true;
    }

    function _processPartialFill(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (uint256 task_id, OrderInfo memory order, uint256 fillAmount0, uint256 fillAmount1) = 
            abi.decode(taskData, (uint256, OrderInfo, uint256, uint256));
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(order.token0),
            currency1: Currency.wrap(order.token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        // Get the best order user from storage (opposite direction)
        bool oppositeDirection = !order.zeroForOne;
        address bestOrderUser = bestOrderUsers[order.token0][order.token1][oppositeDirection];
        require(bestOrderUser != address(0), "No best order found");
        
        // Check if the fill amount exceeds the best order's remaining order amount
        uint256 currentRemainingAmount = bestOrderInputAmount[order.token0][order.token1][oppositeDirection];
        
        if (order.zeroForOne) {
            // Incoming order is selling token0 for token1, best order is selling token1 for token0
            // Check if fillAmount0 (token0 that best order will give) exceeds their remaining order
            if (fillAmount1 >= currentRemainingAmount) {
                return false;
            }
        } else {
            // Incoming order is selling token1 for token0, best order is selling token0 for token1
            // Check if fillAmount0 (token0 that best order will give) exceeds their remaining order
            if (fillAmount0 >= currentRemainingAmount) {
                return false;
            }
        }
        
        // Calculate the actual fill amount (minimum of what incoming order wants and what best order can provide)
        uint256 actualFillAmount0 = fillAmount0 < currentRemainingAmount ? fillAmount0 : currentRemainingAmount;
        uint256 actualFillAmount1 = fillAmount1;
        
        // Direct peer-to-peer token exchange between incoming order and best order
        if (order.zeroForOne) {
            // Incoming order is selling token0 for token1, best order is selling token1 for token0
            // Transfer token0 from incoming order user to best order user
            _transferFunds(order.user, bestOrderUser, order.token0, actualFillAmount0);
            // Transfer token1 from best order user to incoming order user
            _transferFunds(bestOrderUser, order.user, order.token1, actualFillAmount1);

            // Update remaining amounts: best order's input (token1) decreases, output (token0) decreases
            bestOrderInputAmount[order.token0][order.token1][oppositeDirection] -= actualFillAmount1;
            bestOrderOutputAmount[order.token0][order.token1][oppositeDirection] -= actualFillAmount0;
        } else {
            // Incoming order is selling token1 for token0, best order is selling token0 for token1
            // Transfer token1 from incoming order user to best order user
            _transferFunds(order.user, bestOrderUser, order.token1, actualFillAmount1);
            // Transfer token0 from best order user to incoming order user
            _transferFunds(bestOrderUser, order.user, order.token0, actualFillAmount0);

            // Update remaining amounts: best order's input (token0) decreases, output (token1) decreases
            bestOrderInputAmount[order.token0][order.token1][oppositeDirection] -= actualFillAmount0;
            bestOrderOutputAmount[order.token0][order.token1][oppositeDirection] -= actualFillAmount1;
        }
        
        emit OrderExecuted(order.user, order.orderId, actualFillAmount0, actualFillAmount1);
        emit TaskProcessed(taskId, TaskType.PartialFill, true);
        return true;
    }

    function _processCompleteFill(uint256 taskId, bytes memory taskData) internal returns (bool) {
        (uint256 task_id, OrderInfo memory incomingOrder, uint256 fillAmount0, uint256 fillAmount1, OrderInfo memory newBestOrder) = 
            abi.decode(taskData, (uint256, OrderInfo, uint256, uint256, OrderInfo));
        
        // Get the best order user from storage (opposite direction)
        bool oppositeDirection = !incomingOrder.zeroForOne;
        address bestOrderUser = bestOrderUsers[incomingOrder.token0][incomingOrder.token1][oppositeDirection];
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
            bestOrderUsers[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.user;
            bestOrderTicks[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.tick;
            bestOrderUseHigherTick[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = false; // Default value

            if (newBestOrder.zeroForOne) {
                bestOrderInputAmount[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.amount1;
                bestOrderOutputAmount[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.amount0;
            } else {
                bestOrderInputAmount[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.amount0;
                bestOrderOutputAmount[newBestOrder.token0][newBestOrder.token1][newBestOrder.zeroForOne] = newBestOrder.amount1;
            }
            emit BestPriceUpdated(newBestOrder.token0, newBestOrder.token1, newBestOrder.tick, newBestOrder.zeroForOne);
        } else {
            // Clear best order if no new best order provided
            bestOrderUsers[incomingOrder.token0][incomingOrder.token1][oppositeDirection] = address(0);
            bestOrderTicks[incomingOrder.token0][incomingOrder.token1][oppositeDirection] = 0;
            bestOrderUseHigherTick[incomingOrder.token0][incomingOrder.token1][oppositeDirection] = false;
            bestOrderInputAmount[incomingOrder.token0][incomingOrder.token1][oppositeDirection] = 0;
            bestOrderOutputAmount[incomingOrder.token0][incomingOrder.token1][oppositeDirection] = 0;
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
        
        // Get the actual tick used by SwapbookV2 for execution
        // We need to use the same tick that SwapbookV2 used, not our stored tick
        bool useHigherTick = bestOrderUseHigherTick[token0][token1][zeroForOne];
        int24 executionTick = useHigherTick 
            ? swapbookV2.getHigherUsableTick(bestOrderTicks[token0][token1][zeroForOne], 60)
            : swapbookV2.getLowerUsableTick(bestOrderTicks[token0][token1][zeroForOne], 60);

        // Redeem the token by calling redeem function in SwapbookV2
        // Use the same tick that SwapbookV2 used for execution
        swapbookV2.redeem(
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: 3000,
                tickSpacing: 60,
                hooks: IHooks(address(swapbookV2))
            }),
            executionTick, // Use the same tick that SwapbookV2 used for execution
            zeroForOne,
            inputAmount
        );

        // Check if the output amount is greater than the minimum output amount
        if (outputAmount < bestOrderOutputAmount[token0][token1][zeroForOne]) {
            revert("Output amount is less than the minimum output amount");
        }

        // Note: We handle the order execution directly without using the task system
        // This is a callback from SwapbookV2 when an order is executed

        // Handle the order execution directly without using the task system
        // This is a callback from SwapbookV2 when an order is executed
        
        // Calculate the correct amounts for the transfer
        uint256 fillAmount0;
        uint256 fillAmount1;
        
        if (zeroForOne) {
            // User1's order was selling token0 for token1
            fillAmount0 = inputAmount;  // Amount of token0 User1 sold
            fillAmount1 = outputAmount; // Amount of token1 User1 received
        } else {
            // User1's order was selling token1 for token0
            fillAmount0 = outputAmount; // Amount of token0 User1 received
            fillAmount1 = inputAmount;  // Amount of token1 User1 sold
        }
        
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
        
        // Check if the order is completely filled by querying SwapbookV2
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 currentBestTick = swapbookV2.bestTicks(key.toId(), zeroForOne);
        
        // Only clear the best order if it's completely filled (no remaining amount)
        if (swapbookV2.pendingOrders(key.toId(), currentBestTick, zeroForOne) == 0) {
            bestOrderUsers[token0][token1][zeroForOne] = address(0);
            bestOrderTicks[token0][token1][zeroForOne] = 0;
            bestOrderUseHigherTick[token0][token1][zeroForOne] = false;
            bestOrderInputAmount[token0][token1][zeroForOne] = 0;
            bestOrderOutputAmount[token0][token1][zeroForOne] = 0;
            emit BestPriceUpdated(token0, token1, 0, zeroForOne);
        }
        
        emit OrderExecuted(bestOrderUser, 0, fillAmount0, fillAmount1);
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
