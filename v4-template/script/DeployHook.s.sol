// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseScript.sol";
import "../src/CrossChainRouterHook.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

contract DeployHookBase is BaseScript {
    address deployerAddress;
    address gatewayAddress;
    address gasReceiverAddress;
    string destinationChain;
    uint256 bridgeOutPercent;

    uint160 public constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    bytes internal constant ZERO_BYTES = bytes("");

    constructor(address _deployerAddress, address _gateway, address _gasReceiverAddress, string memory _destinationChain, uint256 _bridgeOutPercent) BaseScript() {
        deployerAddress = _deployerAddress;
        gatewayAddress = _gateway;
        gasReceiverAddress = _gasReceiverAddress;
        destinationChain = _destinationChain;
        bridgeOutPercent = _bridgeOutPercent;
    }

    // return hook address
    function deployHookAndCreatePool(address _poolManager, address _token0, address _token1) public returns (address) {
        IPoolManager manager = IPoolManager(_poolManager);
        
        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, 0, type(CrossChainRouterHook).creationCode, abi.encode(address(manager), gatewayAddress, gasReceiverAddress, destinationChain, bridgeOutPercent));

        vm.startBroadcast();
        CrossChainRouterHook hook = new CrossChainRouterHook{salt: salt}(manager, gatewayAddress, gasReceiverAddress, destinationChain, bridgeOutPercent);
        vm.stopBroadcast();

        // Create the pool
        PoolKey memory poolKey = PoolKey(Currency.wrap(_token0), Currency.wrap(_token1), 3000, 60, IHooks(hook));
        
        vm.startBroadcast();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);
        vm.stopBroadcast();

        return address(hook);
    }
}

contract DeployTestChainA is DeployHookBase {
    // configuration
    address constant usdc = 0x1c1521cf734CD13B02e8150951c3bF2B438be780;
    address constant usdt = 0xC0340c0831Aa40A0791cF8C3Ab4287EB0a9705d8;
    
    constructor() 
        DeployHookBase(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // deployerAddress
            0x0aD6371dd7E9923d9968D63Eb8B9858c700abD9d, // gateway
            0x575D3d18666B28680255a202fB5d482D1949bB32, // gasReceiver
            'TestChainB', // destinationChain
            50 // bridgeOutPercent
        )
    {}

    function run() external {
        deploy(_chainId());
    }

    function deploy(uint256 chainId) public {
        string memory chain = loadChainName(chainId);

        if (tryLoadDeployment(chain, "PoolManagerChainA") == address(0)) {
            console.log("deploying PoolManagerChainA");
            vm.startBroadcast();
            PoolManager manager = new PoolManager(500000);
            vm.stopBroadcast();
            saveDeployment(
                chain,
                "PoolManager",
                "PoolManagerChainA",
                address(manager)
            );
        }

        address poolManagerAddress = tryLoadDeployment(chain, "PoolManagerChainA");
        require(poolManagerAddress != address(0), "PoolManagerChainA not deployed");

        if (tryLoadDeployment(chain, "CrossChainRouterHookChainA") == address(0)) {
            address deployedAddress = deployHookAndCreatePool(
                poolManagerAddress,
                usdc,
                usdt
            );

            saveDeployment(
                chain,
                "CrossChainRouterHook",
                "CrossChainRouterHookChainA",
                deployedAddress
            );
        }
    }
}


contract DeployTestChainB is DeployHookBase {
    // configuration
    address constant usdc = 0x6f2E42BB4176e9A7352a8bF8886255Be9F3D2d13;
    address constant usdt = 0xA3f7BF5b0fa93176c260BBa57ceE85525De2BaF4;
    
    constructor() 
        DeployHookBase(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // deployerAddress
            0x9e7F7d0E8b8F38e3CF2b3F7dd362ba2e9E82baa4, // gateway
            0x6D712CB50297b97b79dE784d10F487C00d7f8c2C, // gasReceiver
            'TestChainA', // destinationChain
            50 // bridgeOutPercent
        )
    {}

    function run() external {
        deploy(_chainId());
    }

    function deploy(uint256 chainId) public {
        string memory chain = loadChainName(chainId);

        if (tryLoadDeployment(chain, "PoolManagerChainB") == address(0)) {
            console.log("deploying PoolManagerChainB");
            vm.startBroadcast();
            PoolManager manager = new PoolManager(500000);
            vm.stopBroadcast();
            saveDeployment(
                chain,
                "PoolManager",
                "PoolManagerChainB",
                address(manager)
            );
        }

        address poolManagerAddress = tryLoadDeployment(chain, "PoolManagerChainB");
        require(poolManagerAddress != address(0), "PoolManagerChainB not deployed");

        if (tryLoadDeployment(chain, "CrossChainRouterHookChainB") == address(0)) {
            address deployedAddress = deployHookAndCreatePool(
                poolManagerAddress,
                usdc,
                usdt
            );

            saveDeployment(
                chain,
                "CrossChainRouterHook",
                "CrossChainRouterHookChainB",
                deployedAddress
            );
        }
    }
}