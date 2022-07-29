from ctypes import addressof
from tracemalloc import start
from scripts.helpful_scripts import (
    get_account,
    get_abi,
    get_contract,
    NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS,
)
from brownie import config, network, Contract, web3, Zap, RebateTreasury

# from web3 import Web3
# from decimal import *

import datetime
import time


KEPT_BALANCE = 100 * 10**18

mmf_router_address = "0x145677FC4d9b8F19B5D56d1820c48e0443049a30"
mmf_factory_address = "0xd590cC180601AEcD6eeADD9B7f2B7611519544f4"
# mmf_router_address = "0xc4e4DdB7a71fCF9Bb7356461Ca75124aA9910653"  ## cronos testnet
# mmf_factory_address = "0xBa5FBa5A47f7711C3bF4ca035224c95B3cE2E9C9"  ## cronos testnet
peg_token = "0xc21223249CA28397B4B6541dfFaEcC539BfF0c59"  # USDC

# deployer_account = get_account(id="snowcrystals-deployer")
deployer_account = get_account()
publish_source = config["networks"][network.show_active()]["varify"]

# use datetime to deploy at specific time.
# start_time = datetime.datetime(2022, 8, 1, 0, 0).timestamp()
start_time = (
    time.time() + 60
)  # deploy now // sharetoken, oracle - 1day, share_token_reward(chef), node + 7 days, genesis_pool - 12 hr, treasury
boardroom_start_time = time.time() + 60
oracle_period = 21600  # 6 hours
dao_fund = get_account(index=1)
dev_fund = get_account(index=2)
airdrop_account = get_account(index=3)
insurance_fund = get_account(index=3)
# dao_fund = get_account(id="snowcrystals-dao")
# dev_fund = get_account(id="snowcrystals-dev")
# airdrop_account = get_account(id="snowcrystals-airdrop")
# insurance_fund = get_account(id="snowcrystals-airdrop")


wcro = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23"


def deploy_zap():
    if len(Zap) <= 0:
        print("deploying Zap...")
        zap = Zap.deploy(
            wcro,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    zap = Zap[-1]
    return zap


maintoken = "0x3194cBDC3dbcd3E11a07892e7bA5c3394048Cc87"
oracle = "0x2c15A315610Bfa5248E4CbCbd693320e9D8E03Cc"
treasury = "0x7a3d735ee6873f17Dbdcab1d51B604928dc10d92"


def deploy_rebate_treasury():
    if len(RebateTreasury) <= 0:
        print("deploying RebateTreasury...")
        rebate_treasury = RebateTreasury.deploy(
            maintoken,
            oracle,
            treasury,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    rebate_treasury = RebateTreasury[-1]
    return rebate_treasury


usdc = "0x6951b5Bd815043E3F842c1b026b0Fa888Cc2DD85"


def setup_zap():
    zap = deploy_zap()
    zap_contract = Contract(zap.address)
    print("setting up zap...")
    set_usdc_bridge_tx = zap_contract.setTokenBridgeForRouter(
        usdc, mmf_router_address, maintoken, {"from": deployer_account}
    )
    set_usdc_bridge_tx.wait(1)
    set_maintoken_bridge_tx = zap_contract.setTokenBridgeForRouter(
        maintoken, mmf_router_address, usdc, {"from": deployer_account}
    )
    set_maintoken_bridge_tx.wait(1)


def get_all_info():
    print(f"The active network is {network.show_active()}")
    print(f"Zap contract is {deploy_zap()}")
    print(f"rebate treasury contract is {deploy_rebate_treasury()}")
    print(f"contract deployer account {deployer_account}")
    print(f"dao account {dao_fund}")
    print(f"devloper account {dev_fund}")
    print(f"airdrop account {airdrop_account}")


def main():
    deploy_zap()
    deploy_rebate_treasury()
    setup_zap()
    get_all_info()
