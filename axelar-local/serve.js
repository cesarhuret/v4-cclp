const { ethers } = require("ethers")
const { Network, networks, NetworkOptions, NetworkInfo, NetworkSetup } = require('@axelar-network/axelar-local-dev/dist/Network');
const { RelayData, RelayerMap, relay } = require('@axelar-network/axelar-local-dev/dist/relay');

const AxelarGasServiceFactory = require('@axelar-network/axelar-local-dev/dist/types/factories/@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService__factory').AxelarGasService__factory;

const {
    AxelarGateway,
    Auth,
    TokenDeployer,
    BurnableMintableCappedERC20,
    AxelarGasReceiverProxy,
    ConstAddressDeployer,
    Create3Deployer,
} = require('@axelar-network/axelar-local-dev/dist/contracts');
const chainAConfig = require('./networkInfo-TestChainA.json');
const chainBConfig = require('./networkInfo-TestChainB.json');

const server = require('@axelar-network/axelar-local-dev/dist/server').default;

// Number of milliseconds to periodically trigger the relay function and send all pending crosschain transactions to the destination chain
const relayInterval = 5000

function createWallet(privKey, provider) {
    return new ethers.Wallet(privKey, provider);
}

async function serveNetwork(config, port) {
    const chain = new Network();
    chain.name = config.name;
    chain.chainId = config.chainId;
    chain.provider = new ethers.providers.JsonRpcProvider(config.providerUrl);
    chain.userWallets = config.userKeys.map(createWallet, chain.provider);
    
    chain.lastRelayedBlock = await chain.provider.getBlockNumber();
    chain.lastExpressedBlock = chain.lastRelayedBlock;

    chain.ownerWallet = createWallet(config.ownerKey, chain.provider);
    chain.operatorWallet = createWallet(config.operatorKey, chain.provider);
    chain.relayerWallet = createWallet(config.relayerKey, chain.provider);
    chain.adminWallets = config.adminKeys.map(createWallet, chain.provider);
    chain.threshold = config.threshold;

    chain.constAddressDeployer = new ethers.Contract(config.constAddressDeployerAddress, ConstAddressDeployer.abi, chain.ownerWallet);
    chain.create3Deployer = new ethers.Contract(config.create3DeployerAddress, Create3Deployer.abi, chain.ownerWallet);
    chain.gateway = new ethers.Contract(config.gatewayAddress, AxelarGateway.abi, chain.ownerWallet);
    chain.gasService = AxelarGasServiceFactory.connect(config.gasReceiverAddress, chain.provider);

    chain.tokens = {
        "USDC": "USDC",
        "USDT": "USDT"
    };

    //await chain.deployToken("Fake USDT", "USDT", 6, 100000000000000, "0x09120eAED8e4cD86D85a616680151DAA653880F2", 'USDT');
    //console.log(await chain.gateway.tokenAddresses('USDT'))

    chain.server = server(chain).listen(port, () => {
        console.log(`Serving ${chain.name} on port ${port}`);
    });

    networks.push(chain);
    
    let relaying = false;

    setInterval(async () => {
        if (relaying) return;
        relaying = true;
        await relay().catch((e) => {
            console.log("Relay failed", JSON.stringify(e));
        });
        relaying = false;
    }, relayInterval);
}

// async function giveToken(ownerwallet, gatewayContract, tokenContract, targetAddress, amount) {
//     const symbol = await tokenContract.symbol();
//     await gatewayContract.mintToken(ethers.utils.defaultAbiCoder.encode(['string', 'address', 'uint256'], [symbol, targetAddress, amount]), "0x0000000000000000000000000000000000000000000000000000000000000000");
// }

serveNetwork(chainAConfig, 8500);
serveNetwork(chainBConfig, 8501);
