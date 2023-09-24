import * as React from "react"
import {
  ChakraProvider,
  Box,
  Text,
  Link,
  VStack,
  Code,
  Grid,
  theme,
  Heading,
  Input,
  HStack,
  Button,
  Menu,
  MenuButton,
  MenuItem,
  MenuList,
  Select,
  Flex,
} from "@chakra-ui/react"
import { ColorModeSwitcher } from "./ColorModeSwitcher"
import { Logo } from "./Logo"
import { FaChevronDown } from "react-icons/fa"
import { Signer, ethers, providers } from "ethers"
import hookABI from "./HookABI.json";
import erc20ABI from "./erc20ABI.json";
import { sign } from "crypto"

declare global {
  interface Window{
    ethereum?: any
  }
}
const chains = {
  'chainA': {
    rpc: "http://18.196.63.236:8545/",
    hook: "0xa0DbebEB68c01554f75860A9Ed5e6C8734cfBb55",
  },
  'chainB': {
    rpc: "http://3.79.184.123:8545/",
    hook: "0xa0DbebEB68c01554f75860A9Ed5e6C8734cfBb55",
    usdc: ""
  }
}


export const App = () => {

  const [lowerTick, setLowerTick] = React.useState(0)
  const [upperTick, setUpperTick] = React.useState(0)
  const [amount, setAmount] = React.useState(0)

  const [account, setAccount] = React.useState('')
  const [rpc, setRPC] = React.useState('')

  const [signer, setSigner] = React.useState<any>(null);

  const [hook, setHook] = React.useState<ethers.Contract>();

  const [balances, setBalances] = React.useState<any[]>([]);

  React.useEffect(() => {
    const jsonRPC = new ethers.providers.JsonRpcProvider(rpc || 'http://18.196.63.236:8545/')
    const sign = new ethers.Wallet('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', jsonRPC);
    const chainB = new ethers.providers.JsonRpcProvider(rpc || 'http://3.79.184.123:8545/')

    const hookContract = new ethers.Contract("0xa0a1885fdAb68182740403eDB58bAB14e4AF7670", hookABI.abi, sign);
    
    setSigner(sign);
    
    (async () => {
      setHook(hookContract);
      setAccount(await sign.getAddress())
      fetchBalance(sign, new ethers.providers.JsonRpcProvider(rpc || 'http://3.79.184.123:8545/'))
    })();

  }, [rpc])

  const addLiquidity = async () => {

    console.log(lowerTick, upperTick, amount, rpc)

    if (hook) {
      const addLiquidity = await hook.addLiquidity([
        "0x1c1521cf734CD13B02e8150951c3bF2B438be780",
        "0xC0340c0831Aa40A0791cF8C3Ab4287EB0a9705d8",
        3000,
        60,
        "0xa0a1885fdAb68182740403eDB58bAB14e4AF7670"
      ], [
        lowerTick, 
        upperTick,
        amount,
      ])

      console.log(await addLiquidity.wait(1))
      
      fetchBalance(signer, new ethers.providers.JsonRpcProvider(rpc || 'http://3.79.184.123:8545/'))
    }
  }

  const fetchBalance = async (signer: Signer, chainB: any) => {

    const usdcA = new ethers.Contract("0x1c1521cf734CD13B02e8150951c3bF2B438be780", erc20ABI.abi, signer)
    const usdtA = new ethers.Contract("0xC0340c0831Aa40A0791cF8C3Ab4287EB0a9705d8", erc20ABI.abi, signer)

    const balanceUSDC = await usdcA.balanceOf(signer.getAddress())
    const balanceUSDT = await usdtA.balanceOf(signer.getAddress())

    const usdcB = new ethers.Contract("0x6f2E42BB4176e9A7352a8bF8886255Be9F3D2d13", erc20ABI.abi, chainB)
    const usdtB = new ethers.Contract("0xA3f7BF5b0fa93176c260BBa57ceE85525De2BaF4", erc20ABI.abi, chainB)

    const balanceUSDCB = await usdcB.balanceOf("0xA0dC077d2f58533ba871C137544aD77402a67E8d")
    const balanceUSDTB = await usdtB.balanceOf("0xA0dC077d2f58533ba871C137544aD77402a67E8d")

    setBalances([balanceUSDC.toNumber(), balanceUSDT.toNumber(), balanceUSDCB.toNumber(), balanceUSDTB.toNumber()])
  }

  return (
  <ChakraProvider theme={theme}>
    <Box textAlign="center" fontSize="xl">
      <Grid minH="100vh" p={3}>
        <Flex gap={5} justifySelf="flex-end">
          <Select maxW={'150px'} onChange={(e) => setRPC(e.target.value)}>
            <option value={"http://18.196.63.236:8545/"}>Chain A</option>
            <option value={"http://3.79.184.123:8545/"}>Chain B</option>
          </Select>
          {!signer ? <span>Select Chain</span> : <span>{account.substring(0, 5)}...{account.substring(account.length - 5)}</span>}
          <ColorModeSwitcher  />
        </Flex>
        <VStack spacing={8}>
          <Heading>
            Add Crosschain Liquidity
          </Heading>
          <Text>USDC/USDT Pool</Text>
          <Box borderRadius={'xl'} maxW={'400px'} borderWidth={'0.1em'} p={10}>
            <HStack spacing={5} pb={10}>
              <Input size={'lg'} type='number' placeholder="Lower Tick"
                onChange={(e) => {setLowerTick(parseFloat(e.target.value))}}
              />
              <Input size={'lg'} type='number' placeholder="Upper Tick"
                onChange={(e) => {setUpperTick(parseFloat(e.target.value))}}
              />
            </HStack>
            <Input size={'lg'} type='number' mb={10} placeholder="Amount" 
              onChange={(e) => {setAmount(parseFloat(e.target.value))}}
            />
            <Button size={'lg'} w={'full'} onClick={addLiquidity} variant={'outline'}>Add Liquidity</Button>
          </Box>
          <HStack gap={10}>
            <VStack>
              <Text>Your Balance on Chain A</Text>
              <Text>USDC: {balances[0]}</Text>
              <Text>USDT: {balances[1]}</Text>
            </VStack>
            <VStack>
              <Text>Your Balance on Chain B</Text>
              <Text>USDC: {balances[2]}</Text>
              <Text>USDT: {balances[3]}</Text>
            </VStack>
          </HStack>
        </VStack>
      </Grid>
    </Box>
  </ChakraProvider>
)
  }
