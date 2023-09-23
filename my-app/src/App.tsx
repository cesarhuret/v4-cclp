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
import { ethers } from "ethers"

declare global {
  interface Window{
    ethereum?: any
  }
}
const chains = [
  ['Chain A', "http://18.196.63.236:8545/"],
  ['Chain B', "http://3.79.184.123:8545/"]
]

export const App = () => {

  const [lowerTick, setLowerTick] = React.useState(0)
  const [upperTick, setUpperTick] = React.useState(0)
  const [amount, setAmount] = React.useState(0)

  const [account, setAccount] = React.useState('')
  const [rpc, setRPC] = React.useState('')

  const [signer, setSigner] = React.useState<any>(null)

  React.useEffect(() => {
    const jsonRPC = new ethers.providers.JsonRpcProvider(rpc || 'http://18.196.63.236:8545/')
    const sign = new ethers.Wallet('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', jsonRPC);
    
    setSigner(sign);
    
    (async () => {
      console.log((await jsonRPC.getNetwork()).chainId)
      setAccount(await sign.getAddress())
    })();

  }, [rpc])

  const addLiquidity = async () => {

    console.log(lowerTick, upperTick, amount, rpc)

  
    console.log(await signer.signMessage('hello world'))

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
            Add Liquidity
          </Heading>
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
        </VStack>
      </Grid>
    </Box>
  </ChakraProvider>
)
  }
