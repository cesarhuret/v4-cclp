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

        console.log("deployerAddress: ", deployerAddress);
        console.log("manager address: ", address(manager));
        console.log("gatewayAddress: ", gatewayAddress);
        console.log("gasReceiverAddress: ", gasReceiverAddress);
        console.log("destinationChain: ", destinationChain);
        console.log("bridgeOutPercent: ", bridgeOutPercent);
        (address hookAddress, bytes32 salt) = HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, 0, type(CrossChainRouterHook).creationCode, abi.encode(address(manager), gatewayAddress, gasReceiverAddress, destinationChain, bridgeOutPercent));

        vm.startBroadcast();
        CrossChainRouterHook hook = new CrossChainRouterHook{salt: salt}(manager, gatewayAddress, gasReceiverAddress, destinationChain, bridgeOutPercent);
        vm.stopBroadcast();

        // no need
        // require(address(hook) == hookAddress, "CrossChainRouterHookTest: hook address mismatch");

        // Create the pool
        PoolKey memory poolKey = PoolKey(Currency.wrap(_token0), Currency.wrap(_token1), 3000, 60, IHooks(hook));
        //poolId = poolKey.toId();
        
        vm.startBroadcast();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);
        vm.stopBroadcast();

        return address(hook);
    }
}

contract DeployTestChainA is DeployHookBase {
    // configuration
    address constant usdc = 0xc1EeD9232A0A44c2463ACB83698c162966FBc78d;
    address constant usdt = 0xfc073209b7936A771F77F63D42019a3a93311869;
    
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

        if (tryLoadDeployment(chain, "PoolManagerChainA") == address(0)) {
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
    address constant usdc = 0xF6a8aD553b265405526030c2102fda2bDcdDC177;
    address constant usdt = 0x09120eAED8e4cD86D85a616680151DAA653880F2;
    
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

        if (tryLoadDeployment(chain, "PoolManagerChainB") == address(0)) {
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
                usdt,
                usdc
                // swap order
                // usdc,
                // usdt
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