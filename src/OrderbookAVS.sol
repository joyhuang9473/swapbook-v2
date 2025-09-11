
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title OrderbookAVS
 * @dev Manages escrowed funds for limit orders in the SwapbookV2 system
 * @notice Users can deposit and withdraw funds that are held in escrow for limit orders
 */
contract OrderbookAVS is Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    // Events
    event FundsDeposited(address indexed user, address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed user, address indexed token, uint256 amount);
    event FundsTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);

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

}
