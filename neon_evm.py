import multiprocessing as mp
import tqdm
from web3 import Web3
import time

new_url = "https://proxy.devnet.neonlabs.org/solana"
w3 = Web3(Web3.HTTPProvider(new_url))


nonce = w3.eth.get_transaction_count("0x4Eabf83aed18A3b5a2e84c60a4c290C6Cd9B5729") + 1
start_gas = int(
    w3.eth.gas_price
    * 1.5
    * 1.5
    * 1.1
    * 1.2
    * 1.1
    * 1.15
    * 1.15
    * 1.15
    * 1.15
    * 1.15
    * 1.1
    * 1.1
    * 1.1
)


def perform_transaction(i):
    tx = {
        "to": "0x4Eabf83aed18A3b5a2e84c60a4c290C6Cd9B5729",
        "value": 0,
        "data": "0x",
        "gas": 21000,
        "gasPrice": start_gas + 100 * (10 - i),
        "nonce": nonce + i,
        "chainId": 245022926,
    }

    signed_txn = w3.eth.account.sign_transaction(tx, private_key)
    w3.eth.send_raw_transaction(signed_txn.rawTransaction)


# The number of iterations in the loop
num_iterations = 1000
num_max_times = 150000000

# Assuming you have already defined `w3`, `private_key`, `start_gas`, and `nonce`.

# Create a pool of worker processes
num_processes = mp.cpu_count()  # Use the number of available CPU cores

for _ in range(num_max_times):
    try:
        # Use tqdm to create a progress bar for the loop
        with mp.Pool(processes=num_processes) as pool:
            for _ in tqdm.tqdm(
                pool.imap_unordered(perform_transaction, range(num_iterations)),
                total=num_iterations,
            ):
                pass

        nonce += num_iterations

        time.sleep(1)
        print("brrrrr")
    # ValueError from multiprocessing
    except ValueError as e:
        start_gas = int(start_gas * 1.1)
    except Exception as e:
        nonce = (
            w3.eth.get_transaction_count("0x4Eabf83aed18A3b5a2e84c60a4c290C6Cd9B5729")
            + 1
        )
        print(e, type(e), "error")
        time.sleep(4)
