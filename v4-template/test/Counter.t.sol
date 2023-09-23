// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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
import {Counter} from "../src/Counter.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import "forge-std/console.sol";


contract CounterTest is HookTest, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Counter counter;
    PoolKey poolKey;
    PoolId poolId;
    

    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_MODIFY_POSITION_FLAG
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(address(this), flags, 0, type(Counter).creationCode, abi.encode(address(manager), 0x59b670e9fA9D0A427751Af201D676719a970857b, 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f));
        counter = new Counter{salt: salt}(IPoolManager(address(manager)), 0x59b670e9fA9D0A427751Af201D676719a970857b, 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f);
        require(address(counter) == hookAddress, "CounterTest: hook address mismatch");

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(counter));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        console.log(address(this).balance);
        console.log(token0.balanceOf(address(this)));
        console.log(token1.balanceOf(address(this)));

        AxelarConfig memory cfg = AxelarConfig(
            'TestChainA',
            '0x204E16EB5815c91D06ADcd9fd6324C2d74307D84',
            'usdc',
            1
        );

        // Provide liquidity to the pool
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), abi.encode(cfg));
        // modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether));
        // modifyPositionRouter.modifyPosition(
        //     poolKey, IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether)
        // ); 
    }

    function testCounterHooks() public {
        // positions were created in setup()
        console.log(address(this).balance);

        console.log(token0.balanceOf(address(this)));
        console.log(token1.balanceOf(address(this)));

        AxelarConfig memory cfg = AxelarConfig(
            '0x000',
            '0x000',
            'USDC',
            50
        );

        BalanceDelta deltaBalance = modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, -60, 50 ether), abi.encode(cfg));
        // modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, -10 ether));

        // console.log(int256(deltaBalance));
        console.log(token0.balanceOf(address(this)));
        console.log(token1.balanceOf(address(this)));
    }
}
