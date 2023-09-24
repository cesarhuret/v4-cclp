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
        vm.broadcast(vm.envUint("EVM_PRIVATE_KEY"));
        // IPoolManager manager = IPoolManager(0x4B8c70cF3e595D963cD4A33627d4Ba2718fD706F);

        // Deploy the hook using CREATE2

        // struct PoolKey {
        //     /// @notice The lower currency of the pool, sorted numerically
        //     Currency currency0;
        //     /// @notice The higher currency of the pool, sorted numerically
        //     Currency currency1;
        //     /// @notice The pool swap fee, capped at 1_000_000. The upper 4 bits determine if the hook sets any fees.
        //     uint24 fee;
        //     /// @notice Ticks that involve positions must be a multiple of tick spacing
        //     int24 tickSpacing;
        //     /// @notice The hooks of the pool
        //     IHooks hooks;
        // }

        CrossChainRouterHook hook = CrossChainRouterHook(0xa0DbebEB68c01554f75860A9Ed5e6C8734cfBb55); // from chain A

        address usdc = 0xc1EeD9232A0A44c2463ACB83698c162966FBc78d;
        address usdt = 0xfc073209b7936A771F77F63D42019a3a93311869;

        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc), Currency.wrap(usdt), 3000, 60, IHooks(hook));

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(0, 120, 100000000);

        // function setDestinationInfo(string memory _destinationContract, address _destinationToken0, address _destinationToken1, address _destinationHook) external {

        hook.setDestinationInfo("0xA03DDd7B67Ce614c9e3aBfc3ED5EC2F83a100373", 0x09120eAED8e4cD86D85a616680151DAA653880F2, 0xF6a8aD553b265405526030c2102fda2bDcdDC177, 0xA03DDd7B67Ce614c9e3aBfc3ED5EC2F83a100373);
        
        vm.startPrank(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        // IERC20(usdc).approve(address(hook), type(uint).max);


        BalanceDelta delta = hook.addLiquidity(poolKey, params);

        vm.stopPrank();

        console.log(uint256(uint128(int128(delta.amount1()))));

        // vm.stopBroadcast();
    }

}

curl http://18.196.63.236:8545/ \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"method":"eth_call","params":[{"from":null,"to":"0xa0DbebEB68c01554f75860A9Ed5e6C8734cfBb55","data":"0x14aa6df0000000000000000000000000000000000000000000000000000000000000008000000000000000000000000009120eaed8e4cd86d85a616680151daa653880f2000000000000000000000000f6a8ad553b265405526030c2102fda2bdcddc177000000000000000000000000a03ddd7b67ce614c9e3abfc3ed5ec2f83a100373000000000000000000000000000000000000000000000000000000000000002a30784130334444643742363743653631346339653361426663334544354543324638336131303033373300000000000000000000000000000000000000000000"}, "latest"],"id":1,"jsonrpc":"2.0"}'