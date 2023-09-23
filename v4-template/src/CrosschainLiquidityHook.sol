// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import { AxelarExecutable } from '@axelar/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar/contracts/interfaces/IAxelarGasService.sol';
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CrosschainLiquidityHook is BaseHook, AxelarExecutable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Strings for string;
    
    IAxelarGasService public immutable gasService;

    error WrongSymbol();

    struct AxelarConfig {
        string destinationContract;
        string destinationChain;
        string symbol;
        uint256 amount;
    }

    constructor(IPoolManager _poolManager, address _gateway, address _gasService) BaseHook(_poolManager) AxelarExecutable(_gateway) {
        gasService = IAxelarGasService(_gasService);
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

    function beforeModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata crosschainParams
    ) external override returns (bytes4 selector) {

        AxelarConfig memory cfg = abi.decode(crosschainParams, (AxelarConfig));

        // if(params.) {

        // }

        address token0Address = Currency.unwrap(key.currency0);
        IERC20 token0 = IERC20(token0Address);
        
        if(!Strings.equal(token0.symbol(), cfg.symbol)) {
            revert WrongSymbol();
        }

        token0.transferFrom(msg.sender, address(this), cfg.amount);
        token0.approve(address(gateway), cfg.amount);
        bytes memory payload = abi.encode(params, key);
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

        address token1Address = Currency.unwrap(key.currency1);
        IERC20 token1 = IERC20(token1Address);

        selector = BaseHook.beforeModifyPosition.selector;
    }

    function sendToMany(
        string memory destinationChain,
        string memory destinationAddress,
        address[] calldata destinationAddresses,
        string memory symbol,
        uint256 amount
    ) external payable {
        require(msg.value > 0, 'Gas payment is required');


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
}