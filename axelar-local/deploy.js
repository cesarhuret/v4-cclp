const { ethers } = require("ethers")
const { Network } = require('@axelar-network/axelar-local-dev/dist/Network');
const { setJSON } = require('@axelar-network/axelar-local-dev/dist/utils');

const privKeys = ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"];

async function deployNetwork(name, chainId, providerUrl) {
    const chain = new Network();
    chain.name = name;
    chain.chainId = chainId;
    chain.tokens = {};
    chain.userWallets = [];
    chain.providerUrl = providerUrl;
    chain.provider = new ethers.providers.JsonRpcProvider(chain.providerUrl);
    
    const wallets = privKeys.map((x) => new ethers.Wallet(x, chain.provider));

    chain.lastRelayedBlock = await chain.provider.getBlockNumber();
    chain.lastExpressedBlock = chain.lastRelayedBlock;

    // for testing, we use the same wallet for all roles
    chain.ownerWallet = wallets[0];
    chain.operatorWallet = wallets[0];
    chain.relayerWallet = wallets[0];
    chain.adminWallets = [wallets[0]];
    chain.threshold = 1;
    
    await chain.deployConstAddressDeployer();
    await chain.deployCreate3Deployer();
    await chain.deployGateway();
    await chain.deployGasReceiver();

    const chainInfo = {
        ...chain.getInfo(), 
        providerUrl: chain.providerUrl,
        // tokens: Object.fromEntries(Object.entries(chain.tokens).map(([k, v]) => [k, v.address]))
        tokens: {}
    };

    setJSON(chainInfo, `./networkInfo-${chain.name}-new.json`);
    
    return chain;
}



deployNetwork("TestChainA", 696969, "http://18.196.63.236:8545/")
deployNetwork("TestChainB", 31337, "http://3.79.184.123:8545/")
