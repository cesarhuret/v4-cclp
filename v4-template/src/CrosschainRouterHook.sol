// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/contracts/libraries/SqrtPriceMath.sol";
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
    using SqrtPriceMath for uint160;
    using TickMath for int24;
    bytes internal constant ZERO_BYTES = bytes("");

    IAxelarGasService public immutable gasService;

    string public token0Symbol;
    string public token1Symbol;
    string public destinationChain;
    string public destinationContract;

    uint256 public bridgeOutPercent;

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
    }

    constructor(IPoolManager _poolManager, address _gateway, address _gasReceiver, string memory _destinationChain, uint256 _bridgeOutPercent) BaseHook(_poolManager) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
        destinationChain = _destinationChain;
        bridgeOutPercent = _bridgeOutPercent;
    }

    function setDestinationContract(string calldata _destinationContract) external {
        destinationContract = _destinationContract;
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

    function beforeModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        require(msg.sender == address(this), "Sender must be hook");

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
        PoolId poolId = key.toId();
        IPoolManager.ModifyPositionParams memory params = data.params;
        
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            // remove liquidity, no custom logic here
            delta = poolManager.modifyPosition(key, params, ZERO_BYTES);
            _takeDeltas(data.sender, data.key, delta);
        } else {
            // first, bridge out a portion
            uint128 liquidityToBridge = uint128(uint256(params.liquidityDelta) * bridgeOutPercent / 100);

            (uint160 currentSqrtPriceX96, int24 currentTick,,,,) = poolManager.getSlot0(poolId);

            if (currentTick < params.tickLower) {
                // only need to bridge out token0
                string memory _token0Symbol = token0Symbol;
                uint256 amount0 = params.tickLower.getSqrtRatioAtTick().getAmount0Delta(
                            params.tickUpper.getSqrtRatioAtTick(),
                            liquidityToBridge,
                            false
                        );
                _bridgeOut(data.key.currency0, _token0Symbol, amount0);
            } else if (currentTick < params.tickUpper) {
                // bridge out both
                string memory _token0Symbol = token0Symbol;
                string memory _token1Symbol = token1Symbol;
                uint256 amount0 = currentSqrtPriceX96.getAmount0Delta(
                            params.tickUpper.getSqrtRatioAtTick(),
                            liquidityToBridge,
                            false
                        );

                uint256 amount1 = params.tickLower.getSqrtRatioAtTick().getAmount1Delta(
                            currentSqrtPriceX96,
                            liquidityToBridge,
                            false
                        );
                
                // TODO: the recipient only adds LP in the second call
                _bridgeOut(data.key.currency0, _token0Symbol, amount0);
                _bridgeOut(data.key.currency1, _token1Symbol, amount1);
            } else {
                // bridge out token1
                string memory _token1Symbol = token1Symbol;
                uint256 amount1 = params.tickLower.getSqrtRatioAtTick().getAmount1Delta(
                            params.tickUpper.getSqrtRatioAtTick(),
                            liquidityToBridge,
                            false
                        );
                _bridgeOut(data.key.currency1, _token1Symbol, amount1);
            }

            // next, add liquidity to pool manager with the remaining liquidity
            params.liquidityDelta -= int256(uint256(liquidityToBridge));
            require(params.liquidityDelta > 0, "liquidityDelta must be positive");
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);

            _settleDeltas(data.sender, data.key, delta);
        }

        return abi.encode(delta);
    }
    
    function _bridgeOut(Currency currency, string memory symbol, uint256 amount) internal {
        if (amount == 0) return;
        require(!currency.isNative(), "ETH not supported");

        address tokenAddress = Currency.unwrap(currency);
        IERC20 token = IERC20(tokenAddress);

        // TODO: define the payload
        bytes memory payload = ZERO_BYTES;

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

    function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        _settleDelta(sender, key.currency0, uint128(delta.amount0()));
        _settleDelta(sender, key.currency1, uint128(delta.amount1()));
    }

    function _settleDelta(address sender, Currency currency, uint128 amount) internal {
        if (currency.isNative()) {
            poolManager.settle{value: amount}(currency);
        } else {
            if (sender == address(this)) {
                currency.transfer(address(poolManager), amount);
            } else {
                IERC20(Currency.unwrap(currency)).transferFrom(sender, address(poolManager), amount);
            }
            poolManager.settle(currency);
        }
    }
}
