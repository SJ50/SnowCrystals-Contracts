from ctypes import addressof
from tracemalloc import start
from scripts.helpful_scripts import (
    get_account,
    get_abi,
    get_contract,
    NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS,
    LOCAL_BLOCKCHAIN_ENVIRONMENTS,
    append_new_line,
)
from brownie import (
    config,
    network,
    Contract,
    web3,
    Zap,
    GlcrRebateTreasury,
    SnowRebateTreasury,
    DevSnowRebateTreasury,
    DevGlcrRebateTreasury,
)

# from web3 import Web3
# from decimal import *

import datetime
import time
import os


KEPT_BALANCE = 100 * 10**18

router_address = config["networks"][network.show_active()]["router_address"]
factory_address = config["networks"][network.show_active()]["factory_address"]
peg_token = config["networks"][network.show_active()]["usdc_token"]  # USDC
publish_source = config["networks"][network.show_active()]["varify"]


if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
    deployer_account = get_account()
    dao_fund = get_account(index=1)
    dev_fund = get_account(index=2)
else:
    deployer_account = get_account(id="snowcrystals-deployer")
    dao_fund = config["networks"][network.show_active()]["snowcrystals-dao"]
    dev_fund = config["networks"][network.show_active()]["snowcrystals-dev"]

peg_token = os.environ.get("PEG_TOKEN")


def deploy_zap():
    if len(Zap) <= 0:
        print("deploying Zap...")
        zap = Zap.deploy(
            peg_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export ZAP=" + zap.address)
    zap = Zap[-1]
    os.environ["ZAP"] = zap.address
    return zap


maintoken = os.environ.get("MAIN_TOKEN")
oracle = os.environ.get("ORACLE")
treasury = os.environ.get("TREASURY")
sharetoken = os.environ.get("SHARE_TOKEN")
sharetoken_oracle = os.environ.get("SHARETOKEN_ORACLE")


def deploy_snow_rebate_treasury():
    if len(SnowRebateTreasury) <= 0:
        print("deploying Snow RebateTreasury...")
        snow_rebate_treasury = SnowRebateTreasury.deploy(
            maintoken,
            oracle,
            treasury,
            peg_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export SNOW_DAO_REBATE_TREASURY=" + snow_rebate_treasury.address
        )
    snow_rebate_treasury = SnowRebateTreasury[-1]
    os.environ["SNOW_DAO_REBATE_TREASURY"] = snow_rebate_treasury.address
    return snow_rebate_treasury


def deploy_glcr_rebate_treasury():
    if len(GlcrRebateTreasury) <= 0:
        print("deploying Glcr RebateTreasury...")
        glcr_rebate_treasury = GlcrRebateTreasury.deploy(
            sharetoken,
            sharetoken_oracle,
            treasury,
            peg_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export GLCR_DAO_REBATE_TREASURY=" + glcr_rebate_treasury.address
        )
    glcr_rebate_treasury = GlcrRebateTreasury[-1]
    os.environ["GLCR_DAO_REBATE_TREASURY"] = glcr_rebate_treasury.address
    return glcr_rebate_treasury


def deploy_dev_snow_rebate_treasury():
    if len(DevSnowRebateTreasury) <= 0:
        print("deploying Devloper Snow RebateTreasury...")
        snow_dev_rebate_treasury = DevSnowRebateTreasury.deploy(
            maintoken,
            oracle,
            treasury,
            peg_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export SNOW_DEV_REBATE_TREASURY=" + snow_dev_rebate_treasury.address,
        )
    snow_dev_rebate_treasury = DevSnowRebateTreasury[-1]
    os.environ["SNOW_DEV_REBATE_TREASURY"] = snow_dev_rebate_treasury.address
    return snow_dev_rebate_treasury


def deploy_dev_glcr_rebate_treasury():
    if len(DevGlcrRebateTreasury) <= 0:
        print("deploying Devloper Glcr RebateTreasury...")
        glcr_dev_rebate_treasury = DevGlcrRebateTreasury.deploy(
            sharetoken,
            sharetoken_oracle,
            treasury,
            peg_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export GLCR_DEV_REBATE_TREASURY=" + glcr_dev_rebate_treasury.address,
        )
    glcr_dev_rebate_treasury = DevGlcrRebateTreasury[-1]
    os.environ["GLCR_DEV_REBATE_TREASURY"] = glcr_dev_rebate_treasury.address
    return glcr_dev_rebate_treasury


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


def main():
    deploy_zap()
    deploy_snow_rebate_treasury()
    deploy_glcr_rebate_treasury()
    deploy_dev_snow_rebate_treasury()
    deploy_dev_glcr_rebate_treasury()
    append_new_line(".env", "")
