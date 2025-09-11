
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IAvsLogic.sol";
import "./interface/IAttestationCenter.sol";
import "./SwapbookV2.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/types/Currency.sol";
import "v4-core/interfaces/IPoolManager.sol";

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
    SwapbookV2 public swapbookV2; // Reference to SwapbookV2 contract

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
        (address token0, address token1, int24 newBestTick, bool zeroForOne, uint256 amount) = 
            abi.decode(taskData, (address, address, int24, bool, uint256));
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(swapbookV2))
        });
        
        int24 placedTick = swapbookV2.placeOrder(key, newBestTick, zeroForOne, amount);
        emit BestPriceUpdated(token0, token1, placedTick, zeroForOne);
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
        (OrderInfo memory order, OrderInfo memory nextOrder, uint256 fillAmount0, uint256 fillAmount1) = 
            abi.decode(taskData, (OrderInfo, OrderInfo, uint256, uint256));
        
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
        
        if (nextOrder.user != address(0)) {
            PoolKey memory nextKey = PoolKey({
                currency0: Currency.wrap(nextOrder.token0),
                currency1: Currency.wrap(nextOrder.token1),
                fee: 3000,
                tickSpacing: 60,
                hooks: IHooks(address(swapbookV2))
            });
            
            int24 nextPlacedTick = swapbookV2.placeOrder(nextKey, nextOrder.tick, nextOrder.zeroForOne, nextOrder.amount0);
            emit BestPriceUpdated(nextOrder.token0, nextOrder.token1, nextPlacedTick, nextOrder.zeroForOne);
        }
        
        emit OrderExecuted(order.user, order.orderId, fillAmount0, fillAmount1);
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

}
