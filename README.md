# Cross-chain liquidity provision with Uniswap V4 hook and Axelar 

## Setup
- Spin up two local chains with Transient Storage support using `anvil`.
- Run `node axelar-local/deploy.js` to deploy Axelar contracts on both chains.
- Run `node axelar-local/serve.js` to deploy ERC20 tokens via `AxelarGateway`, and starts the relayer
- `forge script script/DeployHook.s.sol:DeployTestChainA  --rpc-url TestChainA --via-ir --code-size-limit 30000 --broadcast` to deploy and initialize the hook on chain A
- `forge script script/DeployHook.s.sol:DeployTestChainB  --rpc-url TestChainB --via-ir --code-size-limit 30000 --broadcast` to deploy and initialize the hook on chain B

## Unit tests
Run `forge test` inside `v4-template` directory

`testAddLiquidity`: Test adding liquidity from the source chain. Validate that a portion of tokens are transfered to the bridge

`testBridgeExecuteAndRangeBelow`: Test receiving bridged liquidity on the destination chain when the range is below the current price. Validate the receiving callback works and balance changes are correct.

`testBridgeExecuteAndRangeAbove`: Test receiving bridged liquidity on the destination chain when the range is above the current price. Validate the receiving callback works and balance changes are correct.

`testBridgeExecuteAndInRange`: Test receiving bridged liquidity on the destination chain when current price is in range. Validate the receiving callback works and balance changes are correct.

## Contract addresses

### Chain A

RPC: http://18.196.63.236:8545

Chain ID: 696969

Hook: 0xa0a1885fdAb68182740403eDB58bAB14e4AF7670

Uniswap V4 Pool Manager: 0x8731d45ff9684d380302573cCFafd994Dfa7f7d3

Axelar gateway: 0xd3b893cd083f07Fe371c1a87393576e7B01C52C6

Axelar gas receiver: 0x721d8077771Ebf9B931733986d619aceea412a1C

### Chain B

RPC: http://3.79.184.123:8545

Chain ID: 31337

Hook: 0xA0dC077d2f58533ba871C137544aD77402a67E8d

Uniswap V4 Pool Manager: 0x75b0B516B47A27b1819D21B26203Abf314d42CCE

Axelar gateway: 0xbe18A1B61ceaF59aEB6A9bC81AB4FB87D56Ba167

Axelar gas receiver: 0xd038A2EE73b64F30d65802Ad188F27921656f28F

## Contract documentations

### Configuration Functions
`setDestinationInfo`: Sets the information regarding the destination chain, such as contract address, token addresses, and hook address. This must be configured before cross-chain liquidity provision

### Liquidity Operations
`addLiquidity(PoolKey, IPoolManager.ModifyPositionParams)`: Used by the user to add liquidity to a pool. Initiates a lock operation to handle callbacks to perform the action

### Hooks
`beforeInitialize`: Initializes token symbols after the pool is created.

`beforeModifyPosition`: Enforces that the caller must be the hook contract itself when adding liquidity

### Axelar Callback
`_executeWithToken`: Processes Axelar payload to handle token reception on the recipient chain and liquidity addition

### Internal Utility Functions
`_bridgeOut`: Handles the actual token transfer across chains.

`_takeDeltas`: Transfers liquidity removed back to the user.

`_settleDeltas`: Transfers liquidity added to the pool manager.
