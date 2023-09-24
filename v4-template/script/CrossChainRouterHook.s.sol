// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import "../src/CrossChainRouterHook.sol";

contract CrossChainRouterHookScript is Script {

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function setUp() public {}

    function run() public returns (address) {
        vm.broadcast();
        IPoolManager manager = IPoolManager(0x4B8c70cF3e595D963cD4A33627d4Ba2718fD706F);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_MODIFY_POSITION_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, 1000, type(CrossChainRouterHook).creationCode, abi.encode(0x4B8c70cF3e595D963cD4A33627d4Ba2718fD706F, 0xe432150cce91c13a887f7D836923d5597adD8E31, 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6, "base", 30));

        // Deploy the hook using CREATE2
        vm.startBroadcast();

        CrossChainRouterHook hook = new CrossChainRouterHook{salt: salt}(manager, 0xe432150cce91c13a887f7D836923d5597adD8E31, 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6, "base", 30);
        require(address(hook) == hookAddress, "hook address mismatch");

        vm.stopBroadcast();

        return address(hook);
    }

}