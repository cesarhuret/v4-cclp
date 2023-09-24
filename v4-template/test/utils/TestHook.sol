// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/CrossChainRouterHook.sol";

contract TestHook is CrossChainRouterHook {
    constructor(IPoolManager _poolManager, address _gateway, address _gasReceiver, string memory _destinationChain, uint256 _bridgeOutPercent) CrossChainRouterHook(_poolManager, _gateway, _gasReceiver, _destinationChain, _bridgeOutPercent) {
    }

    function executeWithTokenStub(
        address recipient,
        address token0,
        address token1,
        address hook,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        bool doAdd,
        bool isToken0,
        uint256 amount
    ) public {
        AxelarPayload memory axelarPayload = AxelarPayload({
            recipient: recipient,
            token0: token0,
            token1: token1,
            hookAddress: hook,
            fee: fee,
            tickSpacing: tickSpacing,
            tickLower: tickLower,
            tickUpper: tickUpper,
            doAdd: doAdd
        });
        bytes memory payload = abi.encode(axelarPayload);

        IERC20Metadata token = IERC20Metadata(isToken0 ? token0 : token1);
        string memory symbol = token.symbol();

        token.transferFrom(msg.sender, address(this), amount);

        _executeWithTokenInternal("", "", payload, symbol, amount);
    }
}