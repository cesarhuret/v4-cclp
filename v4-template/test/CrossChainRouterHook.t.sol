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
import {TestHook} from "./utils/TestHook.sol";
import "forge-std/console.sol";


contract CrossChainRouterHookTest is HookTest, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    TestHook hook;
    PoolKey poolKey;
    PoolId poolId;
    
    string constant destinationChain = 'TestChainB';
    uint256 constant bridgeOutPercent = 10;

    address constant gatewayAddress = 0xb58D8FDD0452DCDBA424BDC76cc719f9f64C862E;

    address destinationToken0;
    address destinationToken1;
    
    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_INITIALIZE_FLAG
        );

        address receiverAddress = address(this);

        (address hookAddress, bytes32 salt) = HookMiner.find(address(this), flags, 0, type(TestHook).creationCode, abi.encode(address(manager), gatewayAddress, receiverAddress, destinationChain, bridgeOutPercent));
        hook = new TestHook{salt: salt}(IPoolManager(address(manager)), gatewayAddress, receiverAddress, destinationChain, bridgeOutPercent);

        require(address(hook) == hookAddress, "CrossChainRouterHookTest: hook address mismatch");

        hook.setDestinationInfo(destinationChain, address(token0), address(token1), hookAddress);

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

        assertEq(balance0After - balance0Before, 29953549559107809);
        assertEq(balance1After - balance1Before, 29953549559107809);

        assertEq(gatewayBalance0After - gatewayBalance0Before, 2995354955910780);
        assertEq(gatewayBalance1After - gatewayBalance1Before, 2995354955910780);
    }

    function testBridgeExecuteAndRangeBelow() public {
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        
        uint256 gatewayBalance0Before = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1Before = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0Before = token0.balanceOf(address(manager));
        uint256 managerBalance1Before = token1.balanceOf(address(manager));

        hook.executeWithTokenStub(
            address(this), //address recipient,
            address(token0),
            address(token1),
            address(hook),
            3000,
            60,
            -120, //int24 tickLower,
            -60, //int24 tickUpper,
            true, //bool doAdd,
            false, // isToken0,
            10 ether // amount
        );

        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        uint256 gatewayBalance0After = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1After = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0After = token0.balanceOf(address(manager));
        uint256 managerBalance1After = token1.balanceOf(address(manager));

        assertEq(managerBalance0After - managerBalance0Before, 0);
        assertEq(managerBalance1After - managerBalance1Before, 10 ether);
    }

    function testBridgeExecuteAndRangeAbove() public {
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        
        uint256 gatewayBalance0Before = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1Before = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0Before = token0.balanceOf(address(manager));
        uint256 managerBalance1Before = token1.balanceOf(address(manager));

        hook.executeWithTokenStub(
            address(this), //address recipient,
            address(token0),
            address(token1),
            address(hook),
            3000,
            60,
            120, //int24 tickLower,
            180, //int24 tickUpper,
            true, //bool doAdd,
            true, // isToken0,
            10 ether // amount
        );

        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        uint256 gatewayBalance0After = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1After = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0After = token0.balanceOf(address(manager));
        uint256 managerBalance1After = token1.balanceOf(address(manager));

        assertEq(managerBalance0After - managerBalance0Before, 10 ether);
        assertEq(managerBalance1After - managerBalance1Before, 0);
    }
    
    function testBridgeExecuteAndInRange() public {
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        
        uint256 gatewayBalance0Before = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1Before = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0Before = token0.balanceOf(address(manager));
        uint256 managerBalance1Before = token1.balanceOf(address(manager));

        hook.executeWithTokenStub(
            address(this), //address recipient,
            address(token0),
            address(token1),
            address(hook),
            3000,
            60,
            -60, //int24 tickLower,
            120, //int24 tickUpper,
            false, //bool doAdd,
            false, // isToken0,
            10 ether // amount
        );
        
        hook.executeWithTokenStub(
            address(this), //address recipient,
            address(token0),
            address(token1),
            address(hook),
            3000,
            60,
            -60, //int24 tickLower,
            120, //int24 tickUpper,
            true, //bool doAdd,
            true, // isToken0,
            10 ether // amount
        );

        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        uint256 gatewayBalance0After = token0.balanceOf(gatewayAddress);
        uint256 gatewayBalance1After = token1.balanceOf(gatewayAddress);

        uint256 managerBalance0After = token0.balanceOf(address(manager));
        uint256 managerBalance1After = token1.balanceOf(address(manager));

        assertEq(managerBalance0After - managerBalance0Before, 10000000000000000000);
        assertEq(managerBalance1After - managerBalance1Before, 5007499619400846838);
    }
}
