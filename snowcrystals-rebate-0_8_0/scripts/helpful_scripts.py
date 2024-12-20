from brownie import network, accounts, config, Contract
import json


NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS = [
    "hardhat",
    "development",
    "ganache",
    "ganache-gui",
    "ganache-cli",
]
LOCAL_BLOCKCHAIN_ENVIRONMENTS = NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS + [
    "mainnet-fork",
    "binance-fork",
    "matic-fork",
    "bsc-main-fork",
    "ftm-main-fork",
    "polygon-main-fork",
    "xdai-main-fork",
    "avax-main-fork",
    "aurora-main-fork",
    "cronos-main-fork",
]


def append_new_line(file_name, text_to_append):
    """Append given text as a new line at the end of file"""
    # Open the file in append & read mode ('a+')
    with open(file_name, "a+") as file_object:
        # Move read cursor to the start of file.
        file_object.seek(0)
        # If file is not empty then append '\n'
        data = file_object.read(100)
        if len(data) > 0:
            file_object.write("\n")
        # Append text at the end of file
        file_object.write(text_to_append)


def get_account(index=None, id=None):
    if index:
        return accounts[index]
    if id:
        ## get account from brownie accounts
        return accounts.load(id)
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        ## get accounts from ganache fork or local ganache env
        return accounts[0]
    ## get account from brownie-config and env variable
    return accounts.add(config["wallets"]["ganache-gui"])


def get_abi(filename):
    with open("./interfaces/" + filename) as abi_file:
        abi = json.load(abi_file)
        return abi


contract_to_mock = {
    # "eth_usd_price_feed": MockV3Aggregator,
    # "dai_usd_price_feed": MockV3Aggregator,
    # "fau_token": MockDAI,
    # "weth_token": MockWETH,
    # "usdc_token": MockUsdc,
    # "btc_token": MockBtc,
}


def get_contract(contract_name):
    # """If you want to use this function, go to the brownie config and add a new entry for
    # the contract that you want to be able to 'get'. Then add an entry in the variable 'contract_to_mock'.
    # You'll see examples like the 'link_token'.
    #     This script will then either:
    #         - Get a address from the config
    #         - Or deploy a mock to use for a network that doesn't have it

    #     Args:
    #         contract_name (string): This is the name that is referred to in the
    #         brownie config and 'contract_to_mock' variable.

    #     Returns:
    #         brownie.network.contract.ProjectContract: The most recently deployed
    #         Contract of the type specificed by the dictionary. This could be either
    #         a mock or the 'real' contract on a live network.
    # """
    contract_type = contract_to_mock[contract_name]
    if network.show_active() in NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        if len(contract_type) <= 0:
            deploy_mocks()
        contract = contract_type[-1]
    else:
        try:
            contract_address = config["networks"][network.show_active()][contract_name]
            contract = Contract.from_abi(
                contract_type._name, contract_address, contract_type.abi
            )
        except KeyError:
            print(
                f"{network.show_active()} address not found, perhaps you should add it to the config or deploy mocks?"
            )
            print(
                f"brownie run scripts/deploy_mocks.py --network {network.show_active()}"
            )
    return contract


DECIMALS = 6
STARTING_PRICE = 2000
INITIAL_VALUE = STARTING_PRICE * 10**DECIMALS


def deploy_mocks(decimals=DECIMALS, initial_value=INITIAL_VALUE):
    """
    Use this script if you want to deploy mocks to a testnet
    """
    # print(f"The active network is {network.show_active()}")
    # print("Deploying Mocks...")
    account = get_account()

    # print("Deploying Mock Price Feed...")
    # mock_price_feed = MockV3Aggregator.deploy(
    #     decimals, initial_value, {"from": account}
    # )
    # print(f"Deployed to {mock_price_feed.address}")
    print("Deploying Mock USDC...")
    usdc_token = MockUsdc.deploy({"from": account})
    print(f"Mock USDC Deployed to {usdc_token.address}")

    # print("Deploying Mock WETH...")
    # weth_token = MockWETH.deploy({"from": account})
    # print(f"Deployed to {weth_token.address}")
    # print("Mocks Deployed!")
