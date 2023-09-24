// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/contracts/libraries/SqrtPriceMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
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

contract CrossChainRouterHook is BaseHook, ILockCallback, AxelarExecutable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Strings for string;
    using SqrtPriceMath for uint160;
    using LiquidityAmounts for uint160;
    using TickMath for int24;
    bytes internal constant ZERO_BYTES = bytes("");

    IAxelarGasService public immutable gasService;

    string public token0Symbol;
    string public token1Symbol;
    string public destinationChain;
    string public destinationContract;
    address public destinationToken0;
    address public destinationToken1;
    address public destinationHook;

    uint256 public bridgeOutPercent;

    mapping(address => uint256) public pendingAmount0;
    mapping(address => uint256) public pendingAmount1;

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
    }

    struct AxelarPayload {
        address recipient;
        address token0;
        address token1;
        address hookAddress;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        bool doAdd;
    }

    constructor(IPoolManager _poolManager, address _gateway, address _gasReceiver, string memory _destinationChain, uint256 _bridgeOutPercent) BaseHook(_poolManager) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
        destinationChain = _destinationChain;
        bridgeOutPercent = _bridgeOutPercent;
    }

    function setDestinationInfo(string memory _destinationContract, address _destinationToken0, address _destinationToken1, address _destinationHook) external {
        destinationContract = _destinationContract;
        destinationToken0 = _destinationToken0;
        destinationToken1 = _destinationToken1;
        destinationHook = _destinationHook;
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

        return CrossChainRouterHook.beforeInitialize.selector;
    }

    function addLiquidity(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        returns (BalanceDelta delta)
    {
        delta = abi.decode(poolManager.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function beforeModifyPosition(address sender, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        require(sender == address(this), "Sender must be hook");

        return CrossChainRouterHook.beforeModifyPosition.selector;
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
        address sender = data.sender;
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

            AxelarPayload memory payload = AxelarPayload({
                recipient: sender,
                token0: destinationToken0,
                token1: destinationToken1,
                hookAddress: destinationHook,
                fee: key.fee,
                tickSpacing: key.tickSpacing,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                doAdd: true
            });

            if (currentTick < params.tickLower) {
                // only need to bridge out token0
                uint256 amount0 = params.tickLower.getSqrtRatioAtTick().getAmount0Delta(
                            params.tickUpper.getSqrtRatioAtTick(),
                            liquidityToBridge,
                            false
                        );
                _bridgeOut(sender, data.key.currency0, amount0, payload);
            } else if (currentTick < params.tickUpper) {
                // bridge out both
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
                
                // The recipient only adds LP in the second call
                payload.doAdd = false;
                _bridgeOut(sender, data.key.currency0, amount0, payload);
                payload.doAdd = true;
                _bridgeOut(sender, data.key.currency1, amount1, payload);
            } else {
                // bridge out token1
                uint256 amount1 = params.tickLower.getSqrtRatioAtTick().getAmount1Delta(
                            params.tickUpper.getSqrtRatioAtTick(),
                            liquidityToBridge,
                            false
                        );
                _bridgeOut(sender, data.key.currency1, amount1, payload);
            }

            // next, add liquidity to pool manager with the remaining liquidity
            params.liquidityDelta -= int256(uint256(liquidityToBridge));
            require(params.liquidityDelta > 0, "liquidityDelta must be positive");
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);

            _settleDeltas(data.sender, data.key, delta);
        }

        return abi.encode(delta);
    }
    
    function _bridgeOut(address sender, Currency currency, uint256 amount, AxelarPayload memory axelarPayload) internal {
        if (amount == 0) return;
        require(!currency.isNative(), "ETH not supported");
        require(bytes(destinationContract).length > 0, "destinationContract not set");

        address tokenAddress = Currency.unwrap(currency);
        IERC20 token = IERC20(tokenAddress);
        string memory symbol = IERC20Metadata(tokenAddress).symbol();

        bytes memory payload = abi.encode(axelarPayload);

        token.transferFrom(sender, address(this), amount);

        // for testing
        token.transfer(address(gateway), amount);
        
        // token.approve(address(gateway), amount);
        // gasService.payNativeGasForContractCallWithToken{ value: 0 wei }( 
        //     address(this),
        //     destinationChain,
        //     destinationContract,
        //     payload,
        //     symbol,
        //     amount,
        //     msg.sender // TODO
        // );

        // gateway.callContractWithToken(destinationChain, destinationContract, payload, symbol, amount);
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

    function _executeWithToken(
        string calldata,
        string calldata,
        bytes calldata encodedPayload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        
        AxelarPayload memory payload = abi.decode(encodedPayload, (AxelarPayload));
        
        address recipient = payload.recipient;

        // store in pending
        if (compareStrings(tokenSymbol, token0Symbol)) {
            pendingAmount0[recipient] += amount;
        } else if (compareStrings(tokenSymbol, token1Symbol)) {
            pendingAmount1[recipient] += amount;
        } else {
            revert("Invalid token symbol");
        }

        require(address(this) == payload.hookAddress, "Destination hook address does not match");

        if (payload.doAdd) {
            address token0 = payload.token0;
            address token1 = payload.token1;
            int24 tickLower = payload.tickLower;
            int24 tickUpper = payload.tickUpper;
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(payload.token0),
                currency1: Currency.wrap(payload.token1),
                fee: payload.fee,
                tickSpacing: payload.tickSpacing,
                hooks: IHooks(address(this))
            });

            PoolId poolId = key.toId();

            (uint160 currentSqrtPriceX96,,,,,) = poolManager.getSlot0(poolId);

            {
                uint160 lowerSqrtPriceX96 = tickLower.getSqrtRatioAtTick();
                uint160 upperSqrtPriceX96 = tickUpper.getSqrtRatioAtTick();

                // add liquidity with current pending amounts
                uint128 liquidity = currentSqrtPriceX96.getLiquidityForAmounts(
                    lowerSqrtPriceX96,
                    upperSqrtPriceX96,
                    pendingAmount0[recipient],
                    pendingAmount1[recipient]
                );


                IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams({
                    liquidityDelta: int256(uint256(liquidity)),
                    tickLower: tickLower,
                    tickUpper: tickUpper
                });

                BalanceDelta delta = poolManager.modifyPosition(key, params, ZERO_BYTES);

                // use tokens stored in this contract to settle
                _settleDeltas(address(this), key, delta);

                uint256 addedAmount0 = uint256(uint128(delta.amount0()));
                uint256 addedAmount1 = uint256(uint128(delta.amount1()));
                pendingAmount0[recipient] -= addedAmount0;
                pendingAmount1[recipient] -= addedAmount1;
            }

            // refund remaining tokens to recipient
            if (pendingAmount0[recipient] > 0) {
                IERC20(token0).transfer(recipient, pendingAmount0[recipient]);
                pendingAmount0[recipient] = 0;
            }

            if (pendingAmount1[recipient] > 0) {
                IERC20(token1).transfer(recipient, pendingAmount1[recipient]);
                pendingAmount1[recipient] = 0;
            }
        }
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
