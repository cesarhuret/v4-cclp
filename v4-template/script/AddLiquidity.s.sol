// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "../src/CrossChainRouterHook.sol";

contract AddLiquidityScript is Script {

    function setUp() public {}

    function run() public {

        CrossChainRouterHook hook = CrossChainRouterHook(0xa0a1885fdAb68182740403eDB58bAB14e4AF7670); // from chain A

        address usdc_a = 0x1c1521cf734CD13B02e8150951c3bF2B438be780;
        address usdt_a = 0xC0340c0831Aa40A0791cF8C3Ab4287EB0a9705d8;
        address usdc_b = 0x6f2E42BB4176e9A7352a8bF8886255Be9F3D2d13;
        address usdt_b = 0xA3f7BF5b0fa93176c260BBa57ceE85525De2BaF4;

        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc_a), Currency.wrap(usdt_a), 3000, 60, IHooks(hook));

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(60, 120, 100000000);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // we're on chain A. foreign hook is on chain B
        // hook.setDestinationInfo("0xA0dC077d2f58533ba871C137544aD77402a67E8d", usdc_b, usdt_b, 0xA0dC077d2f58533ba871C137544aD77402a67E8d);

        // IERC20(usdc_a).approve(address(hook), type(uint).max);
        // IERC20(usdt_a).approve(address(hook), type(uint).max);

        BalanceDelta delta = hook.addLiquidity(poolKey, params);

        vm.stopBroadcast();

    }

}

// curl http://18.196.63.236:8545/ \
//   -X POST \
//   -H "Content-Type: application/json" \
//   --data '{"method":"eth_call","params":[{"from":null,"to":"0xa0DbebEB68c01554f75860A9Ed5e6C8734cfBb55","data":"0x14aa6df0000000000000000000000000000000000000000000000000000000000000008000000000000000000000000009120eaed8e4cd86d85a616680151daa653880f2000000000000000000000000f6a8ad553b265405526030c2102fda2bdcddc177000000000000000000000000a03ddd7b67ce614c9e3abfc3ed5ec2f83a100373000000000000000000000000000000000000000000000000000000000000002a30784130334444643742363743653631346339653361426663334544354543324638336131303033373300000000000000000000000000000000000000000000"}, "latest"],"id":1,"jsonrpc":"2.0"}'