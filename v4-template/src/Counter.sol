// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import "forge-std/console.sol";


import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
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
import "@openzeppelin/contracts/utils/Strings.sol";

contract Counter is BaseHook, ILockCallback, AxelarExecutable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Strings for string;

    IAxelarGasService public immutable gasService;

    
    struct AxelarConfig {
        string destinationContract;
        string destinationChain;
        string symbol;
        uint256 amount;
    }


    constructor(IPoolManager _poolManager, address _gateway, address _gasReceiver) BaseHook(_poolManager) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasReceiver);
    }


    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }


    function beforeModifyPosition(address, PoolKey calldata key, IPoolManager.ModifyPositionParams calldata params, bytes calldata crosschainParams)
        external
        override
        returns (bytes4)
    {

        AxelarConfig memory cfg = abi.decode(crosschainParams, (AxelarConfig));
        // console.log(cfg.destinationChain);
        // console.log(cfg.symbol);
        // console.log(cfg.amount);

        address token0Address = Currency.unwrap(key.currency0);
        IERC20 token0 = IERC20(token0Address);
        
        address token1Address = Currency.unwrap(key.currency1);
        IERC20 token1 = IERC20(token1Address);

        bytes memory payload = abi.encode(params, key);

        // help needed with calculating what amount is being provided

        if(params.tickLower >= 0) {
            // we only transfer token0
            token0.transferFrom(msg.sender, address(this), cfg.amount);
            token0.approve(address(gateway), cfg.amount);

            gasService.payNativeGasForContractCallWithToken{ value: 1 wei }( // for the purpose of this hack we just hardcode the msg.value have it in the contract already
                address(this),
                cfg.destinationChain,
                cfg.destinationContract,
                payload,
                cfg.symbol,
                cfg.amount,
                msg.sender
            );
            gateway.callContractWithToken(cfg.destinationChain, cfg.destinationContract, payload, cfg.symbol, cfg.amount);


        } else if(params.tickUpper <= 0) {
            // we only transfer token1
            token1.transferFrom(msg.sender, address(this), cfg.amount);
            token1.approve(address(gateway), cfg.amount);

            gasService.payNativeGasForContractCallWithToken{ value: 1 wei }( // for the purpose of this hack we just hardcode the msg.value have it in the contract already
                address(this),
                cfg.destinationChain,
                cfg.destinationContract,
                payload,
                cfg.symbol,
                cfg.amount,
                msg.sender
            );
            gateway.callContractWithToken(cfg.destinationChain, cfg.destinationContract, payload, cfg.symbol, cfg.amount);

        } else {
            // we transfer both
            // we need to calculate what percentages of each is sent
            uint256 token0Weight = uint24(-params.tickLower) / 60;
            uint256 token1Weight = uint24(params.tickUpper) / 60;

            uint256 token0Amount = cfg.amount * token0Weight / 2;
            uint256 token1Amount = cfg.amount * token1Weight / 2;

            token0.transferFrom(msg.sender, address(this), token0Amount);
            token0.approve(address(gateway), token0Amount);

            gasService.payNativeGasForContractCallWithToken{ value: 1 wei }( // for the purpose of this hack we just hardcode the msg.value have it in the contract already
                address(this),
                cfg.destinationChain,
                cfg.destinationContract,
                payload,
                'USDC',
                token0Amount,
                msg.sender
            );
            gateway.callContractWithToken(cfg.destinationChain, cfg.destinationContract, payload, 'USDC', token0Amount);

            token1.transferFrom(msg.sender, address(this), token1Amount);
            token1.approve(address(gateway), token1Amount);

            gasService.payNativeGasForContractCallWithToken{ value: 1 wei }( // for the purpose of this hack we just hardcode the msg.value have it in the contract already
                address(this),
                cfg.destinationChain,
                cfg.destinationContract,
                payload,
                'USDC',
                cfg.amount,
                msg.sender
            );
            gateway.callContractWithToken(cfg.destinationChain, cfg.destinationContract, payload, 'USDC', token1Amount);
    
        }

        return BaseHook.beforeModifyPosition.selector;
    }

    function _executeWithToken(
        string calldata,
        string calldata,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        (IPoolManager.ModifyPositionParams memory params, PoolKey memory key) = abi.decode(payload, (IPoolManager.ModifyPositionParams, PoolKey));
        address tokenAddress = gateway.tokenAddresses(tokenSymbol);
        
    }

    function addLiquidity(AddLiquidityParams calldata params)
        external
        ensure(params.deadline)
        returns (uint128 liquidity)
    {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });

        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        PoolInfo storage pool = poolInfo[poolId];

        uint128 poolLiquidity = poolManager.getLiquidity(poolId);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            params.amount0Desired,
            params.amount1Desired
        );

        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }
        BalanceDelta addedDelta = modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: liquidity.toInt256()
            })
        );

        if (poolLiquidity == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            liquidity -= MINIMUM_LIQUIDITY;
            UniswapV4ERC20(pool.liquidityToken).mint(address(0), MINIMUM_LIQUIDITY);
        }

        UniswapV4ERC20(pool.liquidityToken).mint(params.to, liquidity);

        if (uint128(addedDelta.amount0()) < params.amount0Min || uint128(addedDelta.amount1()) < params.amount1Min) {
            revert TooMuchSlippage();
        }
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        public
        virtual
        ensure(params.deadline)
        returns (BalanceDelta delta)
    {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });

        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        UniswapV4ERC20 erc20 = UniswapV4ERC20(poolInfo[poolId].liquidityToken);

        delta = modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(params.liquidity.toInt256())
            })
        );

        erc20.burn(msg.sender, params.liquidity);
    }

    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        override
        returns (bytes4)
    {
        if (key.tickSpacing != 60) revert TickSpacingNotDefault();

        PoolId poolId = key.toId();

        string memory tokenSymbol = string(
            abi.encodePacked(
                "UniV4",
                "-",
                IERC20Metadata(Currency.unwrap(key.currency0)).symbol(),
                "-",
                IERC20Metadata(Currency.unwrap(key.currency1)).symbol(),
                "-",
                Strings.toString(uint256(key.fee))
            )
        );
        address poolToken = address(new UniswapV4ERC20(tokenSymbol, tokenSymbol));

        poolInfo[poolId] = PoolInfo({hasAccruedFees: false, liquidityToken: poolToken});

        return FullRange.beforeInitialize.selector;
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        if (sender != address(this)) revert SenderMustBeHook();

        return FullRange.beforeModifyPosition.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();

        if (!poolInfo[poolId].hasAccruedFees) {
            PoolInfo storage pool = poolInfo[poolId];
            pool.hasAccruedFees = true;
        }

        return IHooks.beforeSwap.selector;
    }

    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        IPoolManager.ModifyPositionParams memory newParams = IPoolManager.ModifyPositionParams(params.tickLower, params.tickUpper, params.LiquidityDelta);

        delta = abi.decode(poolManager.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
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
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(sender, address(poolManager), amount);
            }
            poolManager.settle(currency);
        }
    }

    function _takeDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        poolManager.take(key.currency0, sender, uint256(uint128(-delta.amount0())));
        poolManager.take(key.currency1, sender, uint256(uint128(-delta.amount1())));
    }

    function _removeLiquidity(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        PoolId poolId = key.toId();
        PoolInfo storage pool = poolInfo[poolId];

        if (pool.hasAccruedFees) {
            _rebalance(key);
        }

        uint256 liquidityToRemove = FullMath.mulDiv(
            uint256(-params.liquidityDelta),
            poolManager.getLiquidity(poolId),
            UniswapV4ERC20(pool.liquidityToken).totalSupply()
        );

        params.liquidityDelta = -(liquidityToRemove.toInt256());
        delta = poolManager.modifyPosition(key, params, ZERO_BYTES);
        pool.hasAccruedFees = false;
    }

    function lockAcquired(bytes calldata rawData)
        external
        override(ILockCallback, BaseHook)
        poolManagerOnly
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;

        if (data.params.liquidityDelta < 0) {
            delta = _removeLiquidity(data.key, data.params);
            _takeDeltas(data.sender, data.key, delta);
        } else {
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);
            _settleDeltas(data.sender, data.key, delta);
        }
        return abi.encode(delta);
    }

    function _rebalance(PoolKey memory key) public {
        PoolId poolId = key.toId();
        BalanceDelta balanceDelta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: -(poolManager.getLiquidity(poolId).toInt256())
            }),
            ZERO_BYTES
        );

        uint160 newSqrtPriceX96 = (
            FixedPointMathLib.sqrt(
                FullMath.mulDiv(uint128(-balanceDelta.amount1()), FixedPoint96.Q96, uint128(-balanceDelta.amount0()))
            ) * FixedPointMathLib.sqrt(FixedPoint96.Q96)
        ).toUint160();

        (uint160 sqrtPriceX96,,,,,) = poolManager.getSlot0(poolId);

        poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: newSqrtPriceX96 < sqrtPriceX96,
                amountSpecified: MAX_INT,
                sqrtPriceLimitX96: newSqrtPriceX96
            }),
            ZERO_BYTES
        );

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            newSqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            uint256(uint128(-balanceDelta.amount0())),
            uint256(uint128(-balanceDelta.amount1()))
        );

        BalanceDelta balanceDeltaAfter = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                liquidityDelta: liquidity.toInt256()
            }),
            ZERO_BYTES
        );

        // Donate any "dust" from the sqrtRatio change as fees
        uint128 donateAmount0 = uint128(-balanceDelta.amount0() - balanceDeltaAfter.amount0());
        uint128 donateAmount1 = uint128(-balanceDelta.amount1() - balanceDeltaAfter.amount1());

        poolManager.donate(key, donateAmount0, donateAmount1, ZERO_BYTES);
    }

}
