// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
 
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
 
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
 
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
 
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OrderbookAVS.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
 
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {console} from "forge-std/console.sol";
 
contract SwapbookV2 is BaseHook, ERC1155 {

	using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint256;
 
    error InvalidOrder();
    error NothingToClaim();
    error NotEnoughToClaim();

    // Events to track order execution
    event LimitOrderExecutedBeforeSwap();
    
    event LimitOrderExecutedAfterSwap();

    // OrderbookAVS integration
    OrderbookAVS public orderbookAVS;
 
    // PoolId => ZeroForOne / OneForZero => Best Tick
    mapping(
        PoolId _poolId => mapping(
            bool zeroForOne => int24 bestTick)) public bestTicks;
    
    // PoolId => Tick => ZeroForOne / OneForZero => Tokens to Sell
    mapping(
        PoolId _poolId => mapping(
            int24 tickToSellAt => mapping(
                bool zeroForOne => uint256 inputAmount))) public pendingOrders;

    mapping (uint256 orderId => uint claimSupply) public claimTokensSupply;

    mapping(uint256 orderId => uint256 outputClaimable)
        public claimableOutputTokens;

    mapping(PoolId poolId => int24 lastTick) public lastTicks;

	// Constructor
    constructor(
        IPoolManager _manager,
        string memory _uri
    ) BaseHook(_manager) ERC1155(_uri) {}

    // Set OrderbookAVS reference
    function setOrderbookAVS(address _orderbookAVS) external {
        orderbookAVS = OrderbookAVS(_orderbookAVS);
    }
 
	// BaseHook Functions
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }
 
    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal override returns (bytes4) {
        lastTicks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }
    
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Don't process if the swap was initiated by this hook to avoid recursion
        if (sender == address(this)) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        bool executed = tryExecutingOrdersSwap(key, params);
        if (executed) {
            // emit an event that shows the swap was executed before swap
            emit LimitOrderExecutedBeforeSwap();
        }

        // Let the swap proceed through the pool normally
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Don't process if the swap was initiated by this hook to avoid recursion
        if (sender == address(this)) return (this.afterSwap.selector, 0);

        bool executed = tryExecutingOrdersSwap(key, params);
        if (executed) {
            // emit an event that shows the swap was executed before swap
            emit LimitOrderExecutedAfterSwap();
        }

        return (this.afterSwap.selector, 0);
    }

    function getLowerUsableTick(
        int24 tick,
        int24 tickSpacing
    ) public pure returns (int24) {
        // E.g. tickSpacing = 60, tick = -100
        // closest usable tick rounded-down will be -120
    
        // intervals = -100/60 = -1 (integer division)
        int24 intervals = tick / tickSpacing;
    
        // since tick < 0, we round `intervals` down to -2
        // if tick > 0, `intervals` is fine as it is
        if (tick < 0 && tick % tickSpacing != 0) intervals--; // round towards negative infinity
    
        // actual usable tick, then, is intervals * tickSpacing
        // i.e. -2 * 60 = -120
        return intervals * tickSpacing;
    }

    function getHigherUsableTick(
        int24 tick,
        int24 tickSpacing
    ) public pure returns (int24) {
        // E.g. tickSpacing = 60, tick = 100
        // closest usable tick rounded-up will be 120
    
        // intervals = 100/60 = 1 (integer division)
        int24 intervals = tick / tickSpacing;
    
        // if tick is not already a multiple of tickSpacing, round up
        if (tick % tickSpacing != 0) intervals++; // round towards positive infinity
    
        // actual usable tick, then, is intervals * tickSpacing
        // i.e. 2 * 60 = 120
        return intervals * tickSpacing;
    }

    function getOrderId(
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(key.toId(), tick, zeroForOne)));
    }

    function placeOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmount,
        bool useHigherTick
    ) public returns (int24) {
        // Get usable tick based on user preference
        int24 tick = useHigherTick 
            ? getHigherUsableTick(tickToSellAt, key.tickSpacing)
            : getLowerUsableTick(tickToSellAt, key.tickSpacing);
        // Create a pending order
        pendingOrders[key.toId()][tick][zeroForOne] += inputAmount;
        
        // Update best tick for this direction
        int24 currentBestTick = bestTicks[key.toId()][zeroForOne];
        if (currentBestTick == 0 || // No previous order
            (zeroForOne && tick > currentBestTick) || // For zeroForOne, higher tick = better price
            (!zeroForOne && tick < currentBestTick)) { // For oneForZero, lower tick = better price
            bestTicks[key.toId()][zeroForOne] = tick;
        }
    
        // Mint claim tokens to user equal to their `inputAmount`
        uint256 orderId = getOrderId(key, tick, zeroForOne);
        claimTokensSupply[orderId] += inputAmount;
        _mint(msg.sender, orderId, inputAmount, "");
    
        // Depending on direction of swap, we select the proper input token
        // and request a transfer of those tokens to the hook contract
        address sellToken = zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount);
    
        // Return the tick at which the order was actually placed
        return tick;
    }
    
    function placeOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmount
    ) external returns (int24) {
        return placeOrder(key, tickToSellAt, zeroForOne, inputAmount, false); // Defaults to getHigherUsableTick
    }

    function cancelOrder(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 amountToCancel
    ) external {
        // Get lower actually usable tick for their order
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 orderId = getOrderId(key, tick, zeroForOne);
    
        // Check how many claim tokens they have for this position
        uint256 positionTokens = balanceOf(msg.sender, orderId);
        if (positionTokens < amountToCancel) revert NotEnoughToClaim();
    
        // Remove their `amountToCancel` worth of position from pending orders
        pendingOrders[key.toId()][tick][zeroForOne] -= amountToCancel;
        // Reduce claim token total supply and burn their share
        claimTokensSupply[orderId] -= amountToCancel;
        _burn(msg.sender, orderId, amountToCancel);
    
        // Send them their input token
        Currency token = zeroForOne ? key.currency0 : key.currency1;
        token.transfer(msg.sender, amountToCancel);
    }

    function redeem(
        PoolKey calldata key,
        int24 tickToSellAt,
        bool zeroForOne,
        uint256 inputAmountToClaimFor
    ) external {
        // Get lower actually usable tick for their order
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);
        uint256 orderId = getOrderId(key, tick, zeroForOne);

        // If no output tokens can be claimed yet i.e. order hasn't been filled
        // throw error
        if (claimableOutputTokens[orderId] == 0) revert NothingToClaim();

        // they must have claim tokens >= inputAmountToClaimFor
        uint256 claimTokens = balanceOf(msg.sender, orderId);
        if (claimTokens < inputAmountToClaimFor) revert NotEnoughToClaim();

        uint256 totalClaimableForPosition = claimableOutputTokens[orderId];
        uint256 totalInputAmountForPosition = claimTokensSupply[orderId];

        // outputAmount = (inputAmountToClaimFor * totalClaimableForPosition) / (totalInputAmountForPosition)
        uint256 outputAmount = inputAmountToClaimFor.mulDivDown(
            totalClaimableForPosition,
            totalInputAmountForPosition
        );

        // Reduce claimable output tokens amount
        // Reduce claim token total supply for position
        // Burn claim tokens
        claimableOutputTokens[orderId] -= outputAmount;
        claimTokensSupply[orderId] -= inputAmountToClaimFor;
        _burn(msg.sender, orderId, inputAmountToClaimFor);

        // Transfer output tokens
        Currency token = zeroForOne ? key.currency1 : key.currency0;
        token.transfer(msg.sender, outputAmount);
    }

    function swapAndSettleBalances(
        PoolKey calldata key,
        SwapParams memory params
    ) internal returns (BalanceDelta) {
        // Conduct the swap inside the Pool Manager
        BalanceDelta delta = poolManager.swap(key, params, "");
    
        // If we just did a zeroForOne swap
        // We need to send Token 0 to PM, and receive Token 1 from PM
        if (params.zeroForOne) {
            // Negative Value => Money leaving user's wallet
            // Settle with PoolManager
            if (delta.amount0() < 0) {
                _settle(key.currency0, uint128(-delta.amount0()));
            }
    
            // Positive Value => Money coming into user's wallet
            // Take from PM
            if (delta.amount1() > 0) {
                _take(key.currency1, uint128(delta.amount1()));
            }
        } else {
            if (delta.amount1() < 0) {
                _settle(key.currency1, uint128(-delta.amount1()));
            }
    
            if (delta.amount0() > 0) {
                _take(key.currency0, uint128(delta.amount0()));
            }
        }
    
        return delta;
    }
    
    function _settle(Currency currency, uint128 amount) internal {
        // Transfer tokens to PM and let it know
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }
    
    function _take(Currency currency, uint128 amount) internal {
        // Take tokens out of PM to our hook contract
        poolManager.take(currency, address(this), amount);
    }

    function executeOrder(
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne,
        uint256 inputAmount
    ) internal {
        // Do the actual swap and settle all balances
        BalanceDelta delta = swapAndSettleBalances(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                // We provide a negative value here to signify an "exact input for output" swap
                amountSpecified: -int256(inputAmount),
                // No slippage limits (maximum slippage possible)
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // `inputAmount` has been deducted from this position
        pendingOrders[key.toId()][tick][zeroForOne] -= inputAmount;
        uint256 orderId = getOrderId(key, tick, zeroForOne);
        uint256 outputAmount = zeroForOne
            ? uint256(int256(delta.amount1()))
            : uint256(int256(delta.amount0()));

        // `outputAmount` worth of tokens now can be claimed/redeemed by position holders
        claimableOutputTokens[orderId] += outputAmount;

        // Callback to OrderbookAVS for order execution
        if (address(orderbookAVS) != address(0)) {
            address token0 = Currency.unwrap(key.currency0);
            address token1 = Currency.unwrap(key.currency1);
            address bestOrderUser = orderbookAVS.bestOrderUsers(token0, token1, zeroForOne);
            
            if (bestOrderUser != address(0)) {
                // Call the callback function in OrderbookAVS
                orderbookAVS.onOrderExecuted(
                    token0,
                    token1,
                    bestOrderUser,
                    tx.origin, // The actual user who initiated the swap
                    inputAmount,
                    outputAmount,
                    zeroForOne
                );
            }
        }

        // if the order is completely filled, clear the best tick
        if (pendingOrders[key.toId()][tick][zeroForOne] == 0) {
            bestTicks[key.toId()][zeroForOne] = 0;
        }

    }

    function checkForBetterPrice(
        PoolKey calldata key,
        SwapParams calldata params
    ) public view returns (bool) {
        // Get current pool price
        (, int24 currentTick, , ) = poolManager.getSlot0(key.toId());
        
        // Get our best price for the opposite direction
        // If user wants to swap zeroForOne (buy token0 with token1), 
        // we check if we have zeroForOne orders (sell token0 for token1) that can fulfill this
        // If user wants to swap oneForZero (buy token1 with token0),
        // we check if we have oneForZero orders (sell token1 for token0) that can fulfill this
        bool checkDirection = !params.zeroForOne;
        int24 bestTick = bestTicks[key.toId()][checkDirection];
        
        // Check if our best price is better than the pool price
        // For zeroForOne orders (selling token0 for token1):
        // - Higher tick = better price for the seller (more token1 per token0)
        // For oneForZero orders (selling token1 for token0):
        // - Lower tick = better price for the seller (more token0 per token1)
        if (checkDirection) {
            // For zeroForOne orders, higher tick = better price
            return bestTick <= currentTick;
        } else {
            // For oneForZero orders, lower tick = better price
            return bestTick > currentTick;
        }
    }

    // function executeSwapThroughOrderBook(
    //     PoolKey calldata key,
    //     SwapParams calldata params
    // ) internal {
    //     // Get the best order for the opposite direction as the swap
    //     bool executeDirection = !params.zeroForOne;
    //     int24 bestTick = bestTicks[key.toId()][executeDirection];

    //     uint256 availableAmount = pendingOrders[key.toId()][bestTick][executeDirection];
    //     if (availableAmount == 0) {
    //         return; // No amount available
    //     }
        
    //     // Calculate how much the user wants to swap
    //     // params.amountSpecified is negative for exact input swaps
    //     uint256 userSwapAmount = uint256(-params.amountSpecified);
        
    //     // Always execute the limit order if it has a better price
    //     // Execute the minimum of available amount and user's swap amount
    //     uint256 executeAmount = availableAmount < userSwapAmount ? availableAmount : userSwapAmount;
        
    //     executeOrder(key, bestTick, executeDirection, executeAmount);
    // }

    function tryExecutingOrdersSwap(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal returns (bool) {
        // Get current pool price
        (, int24 currentTick, , ) = poolManager.getSlot0(key.toId());
        
        // Check if we have a better price in our order book for the opposite direction
        bool checkDirection = !params.zeroForOne;
        int24 bestTick = bestTicks[key.toId()][checkDirection];

        if (checkDirection) {
            // For zeroForOne orders, higher tick = better price
            // Check if current tick >= best tick (price went up enough to execute the order)
            if (currentTick >= bestTick) {
                uint256 availableAmount = pendingOrders[key.toId()][bestTick][true];
                if (availableAmount > 0) {
                    executeOrder(key, bestTick, true, availableAmount);
                    return true;
                }
            }
        } else {
            // For oneForZero orders, lower tick = better price
            // Check if current tick <= best tick (price went down enough to execute the order)
            if (currentTick <= bestTick) {
                uint256 availableAmount = pendingOrders[key.toId()][bestTick][false];
                if (availableAmount > 0) {
                    executeOrder(key, bestTick, false, availableAmount);
                    return true;
                }
            }
        }

        return false;
    }

}