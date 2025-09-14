// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SwapbookAVS} from "../src/SwapbookAVS.sol";

contract SwapbookAVSTest is Test {
    SwapbookAVS public swapbookAVS;
    MockERC20 public token0;
    MockERC20 public token1;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public operator = address(0x4);

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);
        swapbookAVS = new SwapbookAVS();
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        vm.stopPrank();

        // Mint tokens to users
        token0.mint(user1, 1000e18);
        token0.mint(user2, 1000e18);
        token1.mint(user1, 1000e18);
        token1.mint(user2, 1000e18);

        // Users approve the OrderbookAVS contract
        vm.startPrank(user1);
        token0.approve(address(swapbookAVS), type(uint256).max);
        token1.approve(address(swapbookAVS), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token0.approve(address(swapbookAVS), type(uint256).max);
        token1.approve(address(swapbookAVS), type(uint256).max);
        vm.stopPrank();
    }

    function test_depositFunds() public {
        uint256 depositAmount = 100e18;
        
        // User1 deposits token0
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // Check balances
        assertEq(swapbookAVS.getEscrowedBalance(user1, address(token0)), depositAmount);
        assertEq(token0.balanceOf(user1), 900e18);
        assertEq(token0.balanceOf(address(swapbookAVS)), depositAmount);
    }

    function test_withdrawFunds() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;
        
        // User1 deposits first
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // User1 withdraws partially
        vm.startPrank(user1);
        swapbookAVS.withdrawFunds(address(token0), withdrawAmount);
        vm.stopPrank();

        // Check balances
        assertEq(swapbookAVS.getEscrowedBalance(user1, address(token0)), depositAmount - withdrawAmount);
        assertEq(token0.balanceOf(user1), 950e18);
        assertEq(token0.balanceOf(address(swapbookAVS)), depositAmount - withdrawAmount);
    }

    function test_transferFunds() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 30e18;
        
        // User1 deposits
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // Owner authorizes operator
        vm.startPrank(owner);
        swapbookAVS.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        // Operator transfers funds from user1 to user2
        vm.startPrank(operator);
        swapbookAVS.transferFunds(user1, user2, address(token0), transferAmount);
        vm.stopPrank();

        // Check balances
        assertEq(swapbookAVS.getEscrowedBalance(user1, address(token0)), depositAmount - transferAmount);
        assertEq(swapbookAVS.getEscrowedBalance(user2, address(token0)), transferAmount);
    }

    function test_unauthorizedTransfer() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 30e18;
        
        // User1 deposits
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // User2 tries to transfer user1's funds (should fail)
        vm.startPrank(user2);
        vm.expectRevert("Not authorized");
        swapbookAVS.transferFunds(user1, user2, address(token0), transferAmount);
        vm.stopPrank();
    }

    function test_insufficientFunds() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 150e18;
        
        // User1 deposits
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // User1 tries to withdraw more than deposited (should fail)
        vm.startPrank(user1);
        vm.expectRevert("Insufficient escrowed funds");
        swapbookAVS.withdrawFunds(address(token0), withdrawAmount);
        vm.stopPrank();
    }

    function test_multipleTokens() public {
        uint256 amount0 = 100e18;
        uint256 amount1 = 200e18;
        
        // User1 deposits both tokens
        vm.startPrank(user1);
        swapbookAVS.depositFunds(address(token0), amount0);
        swapbookAVS.depositFunds(address(token1), amount1);
        vm.stopPrank();

        // Check balances
        assertEq(swapbookAVS.getEscrowedBalance(user1, address(token0)), amount0);
        assertEq(swapbookAVS.getEscrowedBalance(user1, address(token1)), amount1);
        assertEq(token0.balanceOf(user1), 900e18);
        assertEq(token1.balanceOf(user1), 800e18);
    }

    function test_events() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;
        
        // Test deposit event
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit SwapbookAVS.FundsDeposited(user1, address(token0), depositAmount);
        swapbookAVS.depositFunds(address(token0), depositAmount);
        vm.stopPrank();

        // Test withdraw event
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit SwapbookAVS.FundsWithdrawn(user1, address(token0), withdrawAmount);
        swapbookAVS.withdrawFunds(address(token0), withdrawAmount);
        vm.stopPrank();
    }

}
