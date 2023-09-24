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

    function createPool(address _poolManager, address _hook, address _token0, address _token1) public {
        IPoolManager manager = IPoolManager(_poolManager);

        // no need
        // require(address(hook) == hookAddress, "CrossChainRouterHookTest: hook address mismatch");

        // Create the pool
        PoolKey memory poolKey = PoolKey(Currency.wrap(_token0), Currency.wrap(_token1), 3000, 60, IHooks(_hook));
        
        vm.startBroadcast();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);
        vm.stopBroadcast();
    }
}

contract DeployTestChainA is DeployHookBase {
    // configuration
    address constant usdc = 0x1c1521cf734CD13B02e8150951c3bF2B438be780;
    address constant usdt = 0xC0340c0831Aa40A0791cF8C3Ab4287EB0a9705d8;
    
    constructor() 
        DeployHookBase(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // deployerAddress
            0xd3b893cd083f07Fe371c1a87393576e7B01C52C6, // gateway
            0x721d8077771Ebf9B931733986d619aceea412a1C, // gasReceiver
            'TestChainB', // destinationChain
            50 // bridgeOutPercent
        )
    {}

    function run() external {
        deploy(_chainId());
    }

    function deploy(uint256 chainId) public {
        string memory chain = loadChainName(chainId);

        address poolManagerAddress = tryLoadDeployment(chain, "PoolManagerChainA");
        require(poolManagerAddress != address(0), "PoolManagerChainA not deployed");

        address hookAddress = tryLoadDeployment(chain, "CrossChainRouterHookChainA");
        require(hookAddress != address(0), "CrossChainRouterHookChainA not deployed");

        createPool(poolManagerAddress, hookAddress, usdc, usdt);

    }
}


contract DeployTestChainB is DeployHookBase {
    // configuration
    address constant usdc = 0x6f2E42BB4176e9A7352a8bF8886255Be9F3D2d13;
    address constant usdt = 0xA3f7BF5b0fa93176c260BBa57ceE85525De2BaF4;
    
    constructor() 
        DeployHookBase(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // deployerAddress
            0xbe18A1B61ceaF59aEB6A9bC81AB4FB87D56Ba167, // gateway
            0xd038A2EE73b64F30d65802Ad188F27921656f28F, // gasReceiver
            'TestChainA', // destinationChain
            50 // bridgeOutPercent
        )
    {}

    function run() external {
        deploy(_chainId());
    }

    function deploy(uint256 chainId) public {
        string memory chain = loadChainName(chainId);

        address poolManagerAddress = tryLoadDeployment(chain, "PoolManagerChainB");
        require(poolManagerAddress != address(0), "PoolManagerChainB not deployed");
        
        address hookAddress = tryLoadDeployment(chain, "CrossChainRouterHookChainB");
        require(hookAddress != address(0), "CrossChainRouterHookChainB not deployed");

        createPool(poolManagerAddress, hookAddress, usdc, usdt);
    }
}