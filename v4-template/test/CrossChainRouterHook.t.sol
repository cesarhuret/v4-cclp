// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CrossChainRouterHook} from "../src/CrossChainRouterHook.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {HookTest} from "./utils/HookTest.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import "forge-std/console.sol";


contract CrossChainRouterHookTest is HookTest, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    CrossChainRouterHook hook;
    PoolKey poolKey;
    PoolId poolId;
    
    string constant destinationChain = 'TestChainB';
    uint256 constant bridgeOutPercent = 10;

    address constant gatewayAddress = 0xb58D8FDD0452DCDBA424BDC76cc719f9f64C862E;
    
    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_INITIALIZE_FLAG
        );

        address receiverAddress = address(this);

        (address hookAddress, bytes32 salt) = HookMiner.find(address(this), flags, 0, type(CrossChainRouterHook).creationCode, abi.encode(address(manager), gatewayAddress, receiverAddress, destinationChain, bridgeOutPercent));
        hook = new CrossChainRouterHook{salt: salt}(IPoolManager(address(manager)), gatewayAddress, receiverAddress, destinationChain, bridgeOutPercent);

        require(address(hook) == hookAddress, "CrossChainRouterHookTest: hook address mismatch");

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        // Mint tokens to this address
        token0.mint(address(this), 100 ether);
        token1.mint(address(this), 100 ether);

        // Infinite approval
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
    }

    function testAddLiquidity() public {
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        uint256 gatewayBalance0Before = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1Before = token1.balanceOf(gatewayAddress);

        // Provide liquidity to the pool
        hook.addLiquidity(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether));
        
        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        uint256 gatewayBalance0After = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1After = token1.balanceOf(gatewayAddress);

        console.log("user diff 0 ", balance0Before - balance0After);
        console.log("user diff 1 ", balance1Before - balance1After);

        console.log("gateway diff 0 ", gatewayBalance0After - gatewayBalance0Before);
        console.log("gateway diff 1 ", gatewayBalance1After - gatewayBalance1Before);
    }
}
