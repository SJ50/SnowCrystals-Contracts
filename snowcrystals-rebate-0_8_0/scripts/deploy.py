from ctypes import addressof
from tracemalloc import start
from scripts.helpful_scripts import (
    get_account,
    get_abi,
    get_contract,
    NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS,
    append_new_line,
)
from brownie import config, network, Contract, web3, Zap, RebateTreasury

# from web3 import Web3
# from decimal import *

import datetime
import time
import os


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
usdc = os.environ.get("PEG_TOKEN")


def deploy_zap():
    if len(Zap) <= 0:
        print("deploying Zap...")
        zap = Zap.deploy(
            usdc,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    zap = Zap[-1]
    os.environ["ZAP"] = zap.address
    append_new_line(".env", "export ZAP=" + zap.address)
    return zap


maintoken = os.environ.get("MAIN_TOKEN")
oracle = os.environ.get("ORACLE")
treasury = os.environ.get("TREASURY")


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
    os.environ["REBATE_TREASURY"] = rebate_treasury.address
    append_new_line(".env", "export REBATE_TREASURY=" + rebate_treasury.address)
    return rebate_treasury


# def setup_zap():
#     zap = deploy_zap()
#     zap_contract = Contract(zap.address)
#     print("setting up zap...")
#     set_usdc_bridge_tx = zap_contract.setTokenBridgeForRouter(
#         usdc, mmf_router_address, maintoken, {"from": deployer_account}
#     )
#     set_usdc_bridge_tx.wait(1)
#     set_maintoken_bridge_tx = zap_contract.setTokenBridgeForRouter(
#         maintoken, mmf_router_address, usdc, {"from": deployer_account}
#     )
#     set_maintoken_bridge_tx.wait(1)

# snow=Contract(Snow[-1].address)
# musdc=Contract(MockUsdc[-1].address)
# import json
# router=open("./interfaces/mmf_router_abi.json")
# abi=json.load(router)
# router=Contract.from_abi("router","0x145677FC4d9b8F19B5D56d1820c48e0443049a30",abi)
# lp = open("./interfaces/lp_abi.json")
# abi=json.load(lp)
# slp=Contract.from_abi("slp","0x3fc5B92474b78061632Cc2BA590De53278cD2d5f",abi)
# snow.transfer(myaccount, 1 * 10**18, {"from": accounts[0]})
# snow.approve(zap, 2**256 - 1, {"from": accounts[0]})
# musdc.approve(zap, 2**256 - 1, {"from": accounts[0]})
# snow.setExcludeBothDirectionsFee(zap, True, {"from": accounts[0]})


# snow = "0x3194cBDC3dbcd3E11a07892e7bA5c3394048Cc87"
# musdc = "0x6951b5Bd815043E3F842c1b026b0Fa888Cc2DD85"
# lp = "0x3fc5B92474b78061632Cc2BA590De53278cD2d5f"
# router = "0x145677FC4d9b8F19B5D56d1820c48e0443049a30"
# myaccount = accounts.load("my")
# # Zap.deploy(musdc, {"from": accounts[0]})
# zap = Contract(Zap[-1].address)
# zap.approveTokenIfNeeded(snow, router, {"from": accounts[0]})
# zap.approveTokenIfNeeded(musdc, router, {"from": accounts[0]})
# zap.transfer(snow, 1 * 10**18, {"from": accounts[0]})
# zap.setTokenBridgeForRouter(snow, router, musdc, {"from": accounts[0]})
# zap.setTokenBridgeForRouter(musdc, router, snow, {"from": accounts[0]})
# zap.swappath(snow, musdc, router, {"from": accounts[0]})
# zap.swaptoken(musdc, 1000000000000000000 / 100, snow, zap, router, {"from": accounts[0]})

peg_token = os.environ.get("PEG_TOKEN")
main_token = os.environ.get("MAIN_TOKEN")
treasury = os.environ.get("TREASURY")
oracle = os.environ.get("ORACLE")
bond_token = os.environ.get("BOND_TOKEN")
share_token = os.environ.get("SHARE_TOKEN")
boardroom = os.environ.get("BOARDROOM")
share_reward_pool = os.environ.get("SHARE_TOKEN_REWARD_POOL")
main_token_lp = os.environ.get("MAIN_TOKEN_LP")
share_token_lp = os.environ.get("SHARE_TOKEN_LP")
bonus_reward_pool = os.environ.get("BONUS_REWARD_POOL")
main_token_node = os.environ.get("MAIN_TOKEN_NODE")
share_token_node = os.environ.get("SHARE_TOKEN_NODE")
usdc_genesis_pool = os.environ.get("USDC_GENESIS_POOL")
cro_genesis_pool = os.environ.get("CRO_GENESIS_POOL")
btc_genesis_pool = os.environ.get("BTC_GENESIS_POOL")
eth_genesis_pool = os.environ.get("ETH_GENESIS_POOL")
dai_genesis_pool = os.environ.get("DAI_GENESIS_POOL")
usdt_genesis_pool = os.environ.get("USDT_GENESIS_POOL")
snowusdclp_genesis_pool = os.environ.get("SNOWUSDC_GENESIS_POOL")
rebate_treasury = os.environ.get("REBATE_TREASURY")
zap = os.environ.get("ZAP")


def get_all_info():
    print(f"The active network is {network.show_active()}")
    print(f"peg token is {peg_token}")
    print(f"main token is {main_token}")
    print(f"bond token is {bond_token}")
    print(f"share token is {share_token}")
    print(f"boardroom contract is {boardroom}")
    print(f"treasury contract is {treasury}")
    print(f"oracle contract is {oracle}")
    print(f"main token Liquidity Pool contract is {main_token_lp}")
    print(f"Share token Liquidity Pool contract is {share_token_lp}")
    print(f"Share token reward contract is {share_reward_pool}")
    print(f"Bonus Reward Pool contract is {bonus_reward_pool}")
    print(f"Main token node contract is {main_token_node}")
    print(f"Share token node contract is {share_token_node}")
    print(f"SNOW-USDC-LP genesis pool contract is {snowusdclp_genesis_pool}")
    print(f"USDC genesis pool contract is {usdc_genesis_pool}")
    print(f"CRO genesis pool contract is {cro_genesis_pool}")
    print(f"USDT genesis pool contract is {usdt_genesis_pool}")
    print(f"DAI genesis pool contract is {dai_genesis_pool}")
    print(f"ETH genesis pool contract is {eth_genesis_pool}")
    print(f"BTC genesis pool contract is {btc_genesis_pool}")
    print(f"Zap contract is {zap}")
    print(f"rebate treasury contract is {rebate_treasury}")
    print(f"contract deployer account {deployer_account}")
    print(f"dao account {dao_fund}")
    print(f"devloper account {dev_fund}")
    print(f"airdrop account {airdrop_account}")


def main():
    deploy_zap()
    deploy_rebate_treasury()
    append_new_line(".env", "")
    # setup_zap()
    get_all_info()
