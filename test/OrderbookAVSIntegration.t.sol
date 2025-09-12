// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/OrderbookAVS.sol";
import "../src/interface/IAttestationCenter.sol";

contract OrderbookAVSIntegrationTest is Test {
    OrderbookAVS public orderbookAVS;
    MockERC20 public token0;
    MockERC20 public token1;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public taskSubmitter = address(0x4);

    function setUp() public {
        // Deploy contracts
        orderbookAVS = new OrderbookAVS();
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        
        // Setup users with tokens
        token0.mint(user1, 1000e18);
        token0.mint(user2, 1000e18);
        token0.mint(user3, 1000e18);
        token1.mint(user1, 1000e18);
        token1.mint(user2, 1000e18);
        token1.mint(user3, 1000e18);
        
        // Users approve OrderbookAVS to spend their tokens
        vm.startPrank(user1);
        token0.approve(address(orderbookAVS), type(uint256).max);
        token1.approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        token0.approve(address(orderbookAVS), type(uint256).max);
        token1.approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        token0.approve(address(orderbookAVS), type(uint256).max);
        token1.approve(address(orderbookAVS), type(uint256).max);
        vm.stopPrank();
        
        // Users deposit funds to OrderbookAVS
        vm.startPrank(user1);
        orderbookAVS.depositFunds(address(token0), 500e18);
        orderbookAVS.depositFunds(address(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        orderbookAVS.depositFunds(address(token0), 500e18);
        orderbookAVS.depositFunds(address(token1), 500e18);
        vm.stopPrank();
        
        vm.startPrank(user3);
        orderbookAVS.depositFunds(address(token0), 500e18);
        orderbookAVS.depositFunds(address(token1), 500e18);
        vm.stopPrank();
        
    }

    function testCompleteFill() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            address(token0), 
            address(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order ===");
        
        // Create CompleteFill task data
        OrderbookAVS.OrderInfo memory user2Order = OrderbookAVS.OrderInfo({
            user: user2,
            token0: address(token0),
            token1: address(token1),
            amount0: 100e18,
            amount1: 200e18,
            tick: -2000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });
        
        // Create a new best order (user3) that will replace user1's order after the fill
        OrderbookAVS.OrderInfo memory newBestOrder = OrderbookAVS.OrderInfo({
            user: user3,
            token0: address(token0),
            token1: address(token1),
            amount0: 50e18,
            amount1: 100e18,
            tick: -1500, // Better price than user1's -1000
            zeroForOne: true, // user3 selling token0 for token1
            orderId: 3
        });
        
        uint256 fillAmount0 = 100e18;
        uint256 fillAmount1 = 200e18;
        
        bytes memory completeTaskData = abi.encode(user2Order, fillAmount0, fillAmount1, newBestOrder);
        
        IAttestationCenter.TaskInfo memory completeTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(OrderbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, address(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, address(token1));
        uint256 user2Token0Before = orderbookAVS.getEscrowedBalance(user2, address(token0));
        uint256 user2Token1Before = orderbookAVS.getEscrowedBalance(user2, address(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        orderbookAVS.afterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = orderbookAVS.getEscrowedBalance(user1, address(token0));
        uint256 user1Token1After = orderbookAVS.getEscrowedBalance(user1, address(token1));
        uint256 user2Token0After = orderbookAVS.getEscrowedBalance(user2, address(token0));
        uint256 user2Token1After = orderbookAVS.getEscrowedBalance(user2, address(token1));
        
        console.log("=== AFTER COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // Verify the peer-to-peer swap
        // User1 should have lost 100e18 token0 and gained 200e18 token1
        assertEq(user1Token0After, user1Token0Before - 100e18, "User1 should have lost 100e18 token0");
        assertEq(user1Token1After, user1Token1Before + 200e18, "User1 should have gained 200e18 token1");
        
        // User2 should have gained 100e18 token0 and lost 200e18 token1
        assertEq(user2Token0After, user2Token0Before + 100e18, "User2 should have gained 100e18 token0");
        assertEq(user2Token1After, user2Token1Before - 200e18, "User2 should have lost 200e18 token1");
        
        // Verify the new best order was set
        console.log("=== NEW BEST ORDER VERIFICATION ===");
        address newBestOrderUser = orderbookAVS.bestOrderUsers(address(token0), address(token1));
        int24 newBestOrderTick = orderbookAVS.bestOrderTicks(address(token0), address(token1));
        bool newBestOrderDirection = orderbookAVS.bestOrderDirections(address(token0), address(token1));
        
        console.log("New best order user:", newBestOrderUser);
        console.log("New best order tick:", newBestOrderTick);
        console.log("New best order direction (zeroForOne):", newBestOrderDirection);
        
        assertEq(newBestOrderUser, user3, "New best order user should be user3");
        assertEq(newBestOrderTick, -1500, "New best order tick should be -1500");
        assertTrue(newBestOrderDirection, "New best order should be zeroForOne (selling token0 for token1)");
    }
    
    function testCompleteFillWithEmptyNewBestOrder() public {
        // STEP 1: User1 wants to sell 100e18 token0 for 200e18 token1
        // This triggers UpdateBestPrice to record the order as the best order
        console.log("=== STEP 1: UpdateBestPrice - User1 places order ===");
        
        // Create UpdateBestPrice task data
        bytes memory updateTaskData = abi.encode(
            address(token0), 
            address(token1), 
            -1000, // tick
            true,  // zeroForOne (selling token0 for token1)
            100e18, // amount
            user1  // user who placed the order
        );
        
        IAttestationCenter.TaskInfo memory updateTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof1",
            data: abi.encode(OrderbookAVS.TaskType.UpdateBestPrice, updateTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 1
        });
        
        // Process the UpdateBestPrice task
        orderbookAVS.afterTaskSubmission(updateTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        console.log("User1's order recorded as best price");
        
        // STEP 2: User2 wants to sell 200e18 token1 for 100e18 token0
        // This triggers CompleteFill to match with the best order, but NO new best order
        console.log("=== STEP 2: CompleteFill - User2 matches with best order (no new best order) ===");
        
        // Create CompleteFill task data with empty newBestOrder
        OrderbookAVS.OrderInfo memory user2Order = OrderbookAVS.OrderInfo({
            user: user2,
            token0: address(token0),
            token1: address(token1),
            amount0: 100e18,
            amount1: 200e18,
            tick: -2000,
            zeroForOne: false, // user2 selling token1 for token0
            orderId: 2
        });
        
        // Empty newBestOrder (all zeros)
        OrderbookAVS.OrderInfo memory emptyNewBestOrder = OrderbookAVS.OrderInfo({
            user: address(0), // Empty user address
            token0: address(0),
            token1: address(0),
            amount0: 0,
            amount1: 0,
            tick: 0,
            zeroForOne: false,
            orderId: 0
        });
        
        uint256 fillAmount0 = 100e18;
        uint256 fillAmount1 = 200e18;
        
        bytes memory completeTaskData = abi.encode(user2Order, fillAmount0, fillAmount1, emptyNewBestOrder);
        
        IAttestationCenter.TaskInfo memory completeTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "proof2",
            data: abi.encode(OrderbookAVS.TaskType.CompleteFill, completeTaskData),
            taskPerformer: address(this),
            taskDefinitionId: 2
        });
        
        // Record balances before the complete fill
        uint256 user1Token0Before = orderbookAVS.getEscrowedBalance(user1, address(token0));
        uint256 user1Token1Before = orderbookAVS.getEscrowedBalance(user1, address(token1));
        uint256 user2Token0Before = orderbookAVS.getEscrowedBalance(user2, address(token0));
        uint256 user2Token1Before = orderbookAVS.getEscrowedBalance(user2, address(token1));
        
        console.log("=== BEFORE COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0Before);
        console.log("User1 Token1:", user1Token1Before);
        console.log("User2 Token0:", user2Token0Before);
        console.log("User2 Token1:", user2Token1Before);
        
        // Process the CompleteFill task
        orderbookAVS.afterTaskSubmission(completeTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        
        // Record balances after
        uint256 user1Token0After = orderbookAVS.getEscrowedBalance(user1, address(token0));
        uint256 user1Token1After = orderbookAVS.getEscrowedBalance(user1, address(token1));
        uint256 user2Token0After = orderbookAVS.getEscrowedBalance(user2, address(token0));
        uint256 user2Token1After = orderbookAVS.getEscrowedBalance(user2, address(token1));
        
        console.log("=== AFTER COMPLETE FILL ===");
        console.log("User1 Token0:", user1Token0After);
        console.log("User1 Token1:", user1Token1After);
        console.log("User2 Token0:", user2Token0After);
        console.log("User2 Token1:", user2Token1After);
        
        // Verify the peer-to-peer swap
        // User1 should have lost 100e18 token0 and gained 200e18 token1
        assertEq(user1Token0After, user1Token0Before - 100e18, "User1 should have lost 100e18 token0");
        assertEq(user1Token1After, user1Token1Before + 200e18, "User1 should have gained 200e18 token1");
        
        // User2 should have gained 100e18 token0 and lost 200e18 token1
        assertEq(user2Token0After, user2Token0Before + 100e18, "User2 should have gained 100e18 token0");
        assertEq(user2Token1After, user2Token1Before - 200e18, "User2 should have lost 200e18 token1");
        
        // Verify that the best order was cleared (no new best order)
        console.log("=== BEST ORDER CLEARED VERIFICATION ===");
        address bestOrderUser = orderbookAVS.bestOrderUsers(address(token0), address(token1));
        int24 bestOrderTick = orderbookAVS.bestOrderTicks(address(token0), address(token1));
        bool bestOrderDirection = orderbookAVS.bestOrderDirections(address(token0), address(token1));
        
        console.log("Best order user:", bestOrderUser);
        console.log("Best order tick:", bestOrderTick);
        console.log("Best order direction (zeroForOne):", bestOrderDirection);
        
        assertEq(bestOrderUser, address(0), "Best order user should be cleared (address(0))");
        assertEq(bestOrderTick, 0, "Best order tick should be cleared (0)");
        assertFalse(bestOrderDirection, "Best order direction should be cleared (false)");
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
