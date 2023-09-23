// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import { AxelarExecutable } from '@axelar/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar/contracts/interfaces/IAxelarGasService.sol';
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {ILockCallback} from "@uniswap/v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CrosschainRouterHook is BaseHook, ILockCallback, AxelarExecutable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Strings for string;

    IAxelarGasService public immutable gasService;

    string public token0Symbol;
    string public token1Symbol;

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
    }

    constructor(IPoolManager _poolManager, address _gateway, address _gasReceiver) BaseHook(_poolManager) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: true,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        override
        returns (bytes4)
    {
        token0Symbol = IERC20Metadata(Currency.unwrap(key.currency0)).symbol();
        token1Symbol = IERC20Metadata(Currency.unwrap(key.currency1)).symbol();

        return CrosschainRouterHook.beforeInitialize.selector;
    }

    function addLiquidity(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        returns (BalanceDelta delta)
    {
        delta = abi.decode(poolManager.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function beforeModifyPosition(address, PoolKey calldata key, IPoolManager.ModifyPositionParams calldata params, bytes calldata crosschainParams)
        external
        override
        returns (bytes4)
    {
        if (sender != address(this)) revert SenderMustBeHook();

        return CrosschainRouterHook.beforeModifyPosition.selector;
    }
    
    function lockAcquired(bytes calldata rawData)
        external
        override(ILockCallback, BaseHook)
        poolManagerOnly
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        PoolKey memory key = data.key;
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            // remove liquidity, no custom logic here
            delta = poolManager.modifyPosition(key, params, ZERO_BYTES);
            _takeDeltas(data.sender, data.key, delta);
        } else {
            // first, bridge out a portion
            int256 liquidityToBridge = data.params.liquidityDelta / 2;

            (uint160 currentSqrtPriceX96, int24 currentTick,,,,) = poolManager.getSlot0(poolId);

            if (currentTick < params.tickLower) {
                // only need to bridge out token0
                uint256 amount0 = SqrtPriceMath.getAmount0Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower),
                            TickMath.getSqrtRatioAtTick(params.tickUpper),
                            liquidityToBridge
                        );
                _bridgeOut(data.key.currency0, token0Symbol, amount0);
            } else if (self.slot0.tick < params.tickUpper) {
                // bridge out both
                uint256 amount0 = SqrtPriceMath.getAmount0Delta(
                            currentSqrtPriceX96,
                            TickMath.getSqrtRatioAtTick(params.tickUpper),
                            liquidityToBridge
                        );

                uint256 amount1 = SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower),
                            currentSqrtPriceX96,
                            liquidityToBridge
                        );
                
                _bridgeOut(data.key.currency0, token0Symbol, amount0);
                _bridgeOut(data.key.currency1, token1Symbol, amount1);
            } else {
                // bridge out token1
                uint256 amount1 = SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower),
                            TickMath.getSqrtRatioAtTick(params.tickUpper),
                            liquidityToBridge
                        );
                _bridgeOut(data.key.currency1, token1Symbol, amount1);
            }

            // next, add liquidity to pool manager with the remaining liquidity
            params.liquidityDelta -= liquidityToBridge;
            require(params.liquidityDelta > 0, "liquidityDelta must be positive");
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);
        }

        return abi.encode(delta);
    }
    
    function _bridgeOut(Currency currency, string calldata symbol, uint256 amount) internal {
        if (amount == 0) return;
        require(!currency.isNative(), "ETH not supported");

        address tokenAddress = Currency.unwrap(currency);
        IERC20 token = IERC20(tokenAddress);

        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(gateway), amount);
        gasService.payNativeGasForContractCallWithToken{ value: 0 wei }( 
            address(this),
            destinationChain,
            destinationContract,
            payload,
            symbol,
            amount,
            msg.sender
        );

        gateway.callContractWithToken(destinationChain, destinationContract, payload, symbol, amount);
    }

    function _takeDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        poolManager.take(key.currency0, sender, uint256(uint128(-delta.amount0())));
        poolManager.take(key.currency1, sender, uint256(uint128(-delta.amount1())));
    }
}
