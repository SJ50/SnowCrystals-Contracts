from ctypes import addressof
from platform import node
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
    Snow,
    SBond,
    Glcr,
    Boardroom,
    Oracle,
    MainTokenOracle,
    ShareTokenOracle,
    DataFeedOracle,
    Treasury,
    ShareTokenRewardPool,
    MainTokenNode,
    ShareTokenNode,
    SnowGenesisRewardPool,
    SnowNodeBonusRewardPool,
    SnowSbondBonusRewardPool,
    TaxOfficeV3,
    WrappedRouter,
)

# from brownie.network.gas.strategies import GasNowStrategy

# from web3 import Web3
# from decimal import *

import datetime
import time
import os


KEPT_BALANCE = 100 * 10**18
# gas_strategy = GasNowStrategy("fast")


router_address = config["networks"][network.show_active()]["router_address"]
factory_address = config["networks"][network.show_active()]["factory_address"]
peg_token = config["networks"][network.show_active()]["usdc_token"]  # USDC
publish_source = config["networks"][network.show_active()]["varify"]

maintoken = Snow
maintoken_name = "snowcrystals.finance"
maintoken_symbol = "SNOW"
bondtoken = SBond
bondtoken_name = "snowcrystals.finance BOND"
bondtoken_symbol = "SBOND"
sharetoken = Glcr
sharetoken_name = "snowcrystals.finance SHARE"
sharetoken_symbol = "GLCR"
# use datetime to deploy at specific time.
# start_time = datetime.datetime(2022, 8, 1, 0, 0).timestamp()
sharetoken_start_time = int(
    datetime.datetime(2022, 10, 14, 0, 0).timestamp()
)  # to find endtime
sharetoken_reward_start_time = sharetoken_start_time  # time when sharetoken farm starts
genesis_pool_start_time = sharetoken_start_time  # genesis pool start time, should be <= sharetoken_reward_start_time
node_start_time = int(  # ? used in setup.py
    datetime.datetime(2022, 10, 14, 0, 0).timestamp()
    + datetime.timedelta(days=7).total_seconds()  # boardroom start after 2 day
)
# treasury_start_time = (  # ? used in setup.py
#     datetime.datetime(2022, 9, 14, 0, 0).timestamp()
#     + datetime.timedelta(days=2).total_seconds()  # boardroom start after 2 day
# )


oracle_start_time = int(  # all oracle can start now
    time.time() + 600
)  # deploy now // sharetoken, oracle - 1day, share_token_reward(chef), node + 7 days, genesis_pool - 12 hr, treasury
# boardroom_start_time = time.time() + 600
oracle_period = 21600  # 6 hours


if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
    deployer_account = get_account()
    dao_fund = get_account(index=1)
    dev_fund = get_account(index=2)
else:
    deployer_account = get_account(id="snowcrystals-deployer")
    dao_fund = get_account(id="snowcrystals-dao")
    dev_fund = get_account(id="snowcrystals-dev")


def get_peg_token():
    if network.show_active() in NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        os.environ["PEG_TOKEN"] = get_contract("usdc_token").address
        append_new_line(
            ".env", "export PEG_TOKEN=" + get_contract("usdc_token").address
        )
        return get_contract("usdc_token")
    else:
        usdc_abi = get_abi("usdc_abi.json")
        os.environ["PEG_TOKEN"] = Contract.from_abi("USDC", peg_token, usdc_abi).address
        append_new_line(
            ".env", "export PEG_TOKEN=" + get_contract("usdc_token").address
        )
        return Contract.from_abi("USDC", peg_token, usdc_abi)


def deploy_maintoken():
    if len(maintoken) <= 0:
        print("deploying maintoken!")
        main_token = maintoken.deploy(
            maintoken_name,
            maintoken_symbol,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export MAIN_TOKEN=" + main_token.address)
    main_token = maintoken[-1]
    os.environ["MAIN_TOKEN"] = main_token.address
    return main_token


def deploy_bondtoken():
    if len(bondtoken) <= 0:
        print("deploying bondtoken!")
        bond_token = bondtoken.deploy(
            bondtoken_name,
            bondtoken_symbol,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export BOND_TOKEN=" + bond_token.address)
    bond_token = bondtoken[-1]
    os.environ["BOND_TOKEN"] = bond_token.address
    return bond_token


def deploy_sharetoken():
    if len(sharetoken) <= 0:
        print("deploying sharetoken!")
        print("farm start time ", sharetoken_start_time)
        share_token = sharetoken.deploy(
            sharetoken_name,
            sharetoken_symbol,
            sharetoken_start_time,
            dao_fund,
            dev_fund,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export SHARE_TOKEN=" + share_token.address)
    share_token = sharetoken[-1]
    os.environ["SHARE_TOKEN"] = share_token.address
    return share_token


def deploy_boardroom():
    if len(Boardroom) <= 0:
        print("deploying boardroom!")
        boardroom_contract = Boardroom.deploy(
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export BOARDROOM=" + boardroom_contract.address)
    boardroom_contract = Boardroom[-1]
    os.environ["BOARDROOM"] = boardroom_contract.address
    return boardroom_contract


# def deploy_devfund():
#     dev_fund_


def create_pair(tokenA, tokenB):
    factory_abi = get_abi("factory_abi.json")
    factory = Contract.from_abi("factory", factory_address, factory_abi)

    get_pair_tx = factory.getPair(tokenA, tokenB, {"from": deployer_account})
    if get_pair_tx != "0x0000000000000000000000000000000000000000":
        return get_pair_tx

    print("creating pair!")
    create_pair_tx = factory.createPair(tokenA, tokenB, {"from": deployer_account})
    create_pair_tx.wait(1)
    return create_pair_tx


def create_liquidity_pool(
    tokenA=None,
    tokenB=None,
    amountADesired=None,
    amountBDesired=None,
    amountAMin=None,
    amountBMin=None,
    main_token_lp=None,
    share_token_lp=None,
):

    router_abi = get_abi("router_abi.json")
    router = Contract.from_abi("router", router_address, router_abi)
    if main_token_lp:
        tokenA = os.environ.get("PEG_TOKEN")
        tokenB = os.environ.get("MAIN_TOKEN")
        return create_pair(tokenA, tokenB)
    if share_token_lp:
        tokenA = os.environ.get("PEG_TOKEN")
        tokenB = os.environ.get("SHARE_TOKEN")
        return create_pair(tokenA, tokenB)

    print("approving tokenA...")
    tokenA_contract = Contract(tokenA)
    tx_approve_tokenA = tokenA_contract.approve(
        router.address, amountADesired, {"from": deployer_account}
    )
    tx_approve_tokenA.wait(1)
    print("approving tokenB...")
    tokenB_contract = Contract(tokenB)
    tx_approve_tokenB = tokenB_contract.approve(
        router.address, amountBDesired, {"from": deployer_account}
    )
    tx_approve_tokenB.wait(1)

    blockNumber = web3.eth.blockNumber
    block = web3.eth.getBlock(blockNumber)
    timestamp = block.timestamp + 300
    print("adding liquidity pool...")
    add_liquidity_tx = router.addLiquidity(
        tokenA,
        tokenB,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        deployer_account,
        timestamp + 300,
        {"from": deployer_account},
    )
    add_liquidity_tx.wait(1)
    return create_pair(tokenA, tokenB)


def deploy_main_token_lp():
    tokenA = os.environ.get("PEG_TOKEN")
    tokenB = os.environ.get("MAIN_TOKEN")
    amountADesired = 1 * 10**6
    amountBDesired = 1 * 10**18
    amountAMin = 0
    amountBMin = 0
    factory_abi = get_abi("factory_abi.json")
    factory = Contract.from_abi("factory", factory_address, factory_abi)
    get_pair_tx = factory.getPair(tokenA, tokenB, {"from": deployer_account})
    if get_pair_tx != "0x0000000000000000000000000000000000000000":
        return create_liquidity_pool(main_token_lp=True)

    create_liquidity_pool(
        tokenA=tokenA,
        tokenB=tokenB,
        amountADesired=amountADesired,
        amountBDesired=amountBDesired,
        amountAMin=amountAMin,
        amountBMin=amountBMin,
    )
    os.environ["MAIN_TOKEN_LP"] = create_liquidity_pool(main_token_lp=True)
    append_new_line(
        ".env", "export MAIN_TOKEN_LP=" + create_liquidity_pool(main_token_lp=True)
    )


def deploy_share_token_lp():
    tokenA = os.environ.get("PEG_TOKEN")
    tokenB = os.environ.get("SHARE_TOKEN")
    amountADesired = 1 * 10**6
    amountBDesired = 1 * 10**18 / 100
    amountAMin = 0
    amountBMin = 0
    factory_abi = get_abi("factory_abi.json")
    factory = Contract.from_abi("factory", factory_address, factory_abi)
    get_pair_tx = factory.getPair(tokenA, tokenB, {"from": deployer_account})
    if get_pair_tx != "0x0000000000000000000000000000000000000000":
        return create_liquidity_pool(share_token_lp=True)

    create_liquidity_pool(
        tokenA=tokenA,
        tokenB=tokenB,
        amountADesired=amountADesired,
        amountBDesired=amountBDesired,
        amountAMin=amountAMin,
        amountBMin=amountBMin,
    )
    os.environ["SHARE_TOKEN_LP"] = create_liquidity_pool(share_token_lp=True)
    append_new_line(
        ".env", "export SHARE_TOKEN_LP=" + create_liquidity_pool(share_token_lp=True)
    )


def deploy_treasury_oracle_contract():
    if len(Oracle) <= 0:
        main_token_lp = os.environ.get("MAIN_TOKEN_LP")
        main_token = os.environ.get("MAIN_TOKEN")
        print("deploying treasury oracle!")
        oracle = Oracle.deploy(
            main_token_lp,
            oracle_period,
            oracle_start_time,
            main_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export ORACLE=" + oracle.address)
    oracle = Oracle[-1]
    os.environ["ORACLE"] = oracle.address
    return oracle


def deploy_MainToken_oracle_contract():
    if len(MainTokenOracle) <= 0:
        main_token_lp = os.environ.get("MAIN_TOKEN_LP")
        main_token = os.environ.get("MAIN_TOKEN")
        print("deploying maintoken oracle!")
        main_token_oracle = MainTokenOracle.deploy(
            main_token_lp,
            oracle_period,
            oracle_start_time,
            main_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export MAINTOKEN_ORACLE=" + main_token_oracle.address)
    main_token_oracle = MainTokenOracle[-1]
    os.environ["MAINTOKEN_ORACLE"] = main_token_oracle.address
    return main_token_oracle


def deploy_ShareToken_oracle_contract():
    if len(ShareTokenOracle) <= 0:
        share_token_lp = os.environ.get("SHARE_TOKEN_LP")
        share_token = os.environ.get("SHARE_TOKEN")
        print("deploying sharetoken oracle!")
        share_token_oracle = ShareTokenOracle.deploy(
            share_token_lp,
            oracle_period,
            oracle_start_time,
            share_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export SHARETOKEN_ORACLE=" + share_token_oracle.address
        )
    share_token_oracle = ShareTokenOracle[-1]
    os.environ["SHARETOKEN_ORACLE"] = share_token_oracle.address
    return share_token_oracle


def deploy_DataFeed_oracle_contract():
    if len(DataFeedOracle) <= 0:
        datafeed = config["networks"][network.show_active()]["band_datafeed"]
        print("deploying datafeed oracle!")
        datafeed_oracle = DataFeedOracle.deploy(
            datafeed,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export DATAFEED_ORACLE=" + datafeed_oracle.address)
    datafeed_oracle = DataFeedOracle[-1]
    os.environ["DATAFEED_ORACLE"] = datafeed_oracle.address
    return datafeed_oracle


def deploy_treasury_contract():
    if len(Treasury) <= 0:
        print("deploying treasury!")
        treasury_contract = Treasury.deploy(
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export TREASURY=" + treasury_contract.address)
    treasury_contract = Treasury[-1]
    os.environ["TREASURY"] = treasury_contract.address
    return treasury_contract


def deploy_share_token_reward_pool():
    if len(ShareTokenRewardPool) <= 0:
        print("deploying SHARE reward pool!")
        share_token_reward_pool_contract = ShareTokenRewardPool.deploy(
            os.environ.get("SHARE_TOKEN"),
            dao_fund,
            sharetoken_reward_start_time,  # sharetoken farming start time
            os.environ.get("BOND_TOKEN"),
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export SHARE_TOKEN_REWARD_POOL="
            + share_token_reward_pool_contract.address,
        )
    share_token_reward_pool_contract = ShareTokenRewardPool[-1]
    os.environ["SHARE_TOKEN_REWARD_POOL"] = share_token_reward_pool_contract.address
    return share_token_reward_pool_contract


# def deploy_bonus_reward_pool():
#     if len(SnowNodeBonusRewardPool) <= 0:
#         print("deploying bonus reward pool!")
#         main_token = os.environ.get("MAIN_TOKEN")
#         pool_start_time = start_time
#         deposit_token = os.environ.get("MAIN_TOKEN_LP")
#         snow_bounus_pool_contract = SnowNodeBonusRewardPool.deploy(
#             main_token,
#             pool_start_time,
#             deposit_token,
#             {"from": deployer_account},
#             publish_source=publish_source,
#         )
#         append_new_line(
#             ".env",
#             "export NODE_BONUS_REWARD_POOL=" + snow_bounus_pool_contract.address,
#         )
#     snow_bounus_pool_contract = SnowNodeBonusRewardPool[-1]
#     os.environ["NODE_BONUS_REWARD_POOL"] = snow_bounus_pool_contract.address
#     return snow_bounus_pool_contract


def deploy_main_token_node():
    if len(MainTokenNode) <= 0:
        print("deploying Main node!")
        main_token_lp = os.environ.get("MAIN_TOKEN_LP")
        node_bonus_reward_pool = os.environ.get("NODE_BONUS_REWARD_POOL")
        main_token_node_contract = MainTokenNode.deploy(
            node_start_time,
            main_token_lp,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export MAIN_TOKEN_NODE=" + main_token_node_contract.address
        )
    main_token_node_contract = MainTokenNode[-1]
    os.environ["MAIN_TOKEN_NODE"] = main_token_node_contract.address
    return main_token_node_contract


def deploy_share_token_node():
    if len(ShareTokenNode) <= 0:
        print("deploying SHARE node!")
        share_token_lp = os.environ.get("SHARE_TOKEN_LP")
        share_token_node_contract = ShareTokenNode.deploy(
            node_start_time,
            share_token_lp,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export SHARE_TOKEN_NODE=" + share_token_node_contract.address
        )
    share_token_node_contract = ShareTokenNode[-1]
    os.environ["SHARE_TOKEN_NODE"] = share_token_node_contract.address
    return share_token_node_contract


def deploy_genesis_pool():
    if len(SnowGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 120
        deposit_token = os.environ.get("PEG_TOKEN")
        print("deploying snow genesis pool...")
        usdc_genesis_pool_contract = SnowGenesisRewardPool.deploy(
            main_token,
            genesis_pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export GENESIS_POOL=" + usdc_genesis_pool_contract.address
        )
    usdc_genesis_pool_contract = SnowGenesisRewardPool[-1]
    os.environ["GENESIS_POOL"] = usdc_genesis_pool_contract.address
    return usdc_genesis_pool_contract


# def deploy_sbond_reward_pool():
#     if len(SnowSbondBonusRewardPool) <= 0:
#         main_token = os.environ.get("MAIN_TOKEN")
#         deposit_fee = 0
#         pool_start_time = start_time
#         deposit_token = os.environ.get("BOND_TOKEN")
#         print("deploying snow sbond bonus reward pool...")
#         sbond_reward_pool_contract = SnowSbondBonusRewardPool.deploy(
#             main_token,
#             pool_start_time,
#             dao_fund,
#             deposit_fee,
#             deposit_token,
#             {"from": deployer_account},
#             publish_source=publish_source,
#         )
#         append_new_line(
#             ".env",
#             "export SBOND_REWARD_POOL=" + sbond_reward_pool_contract.address,
#         )
#     sbond_reward_pool_contract = SnowSbondBonusRewardPool[-1]
#     os.environ["SBOND_REWARD_POOL"] = sbond_reward_pool_contract.address
#     return sbond_reward_pool_contract


def deploy_tax_office():
    if len(TaxOfficeV3) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        share_token = os.environ.get("SHARE_TOKEN")
        main_token_oracle = os.environ.get("MAINTOKEN_ORACLE")
        peg_token = os.environ.get("PEG_TOKEN")
        print("deploying tax_office...")
        tax_office_contract = TaxOfficeV3.deploy(
            main_token,
            share_token,
            main_token_oracle,
            peg_token,
            router_address,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export TAX_OFFICE=" + tax_office_contract.address,
        )
    tax_office_contract = TaxOfficeV3[-1]
    os.environ["TAX_OFFICE"] = tax_office_contract.address
    return tax_office_contract


def deploy_wrapped_router():
    if len(WrappedRouter) <= 0:
        print("deploying wrapped router...")
        wrapped_router_contract = WrappedRouter.deploy(
            router_address,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export WRAPPED_ROUTER =" + wrapped_router_contract.address,
        )
    wrapped_router_contract = WrappedRouter[-1]
    os.environ["WRAPPED_ROUTER"] = wrapped_router_contract.address
    return wrapped_router_contract


# def deploy_liquidity_fund():
#     if len(LiquidityFund) <= 0:
#         main_token = os.environ.get("MAIN_TOKEN")
#         peg_token = os.environ.get("PEG_TOKEN")
#         sbond_bonus_reward_pool = os.environ.get("SBOND_REWARD_POOL")
#         node_bonus_reward_pool = os.environ.get("NODE_BONUS_REWARD_POOL")
#         treasury = os.environ.get("TREASURY")
#         liquidity_fund_contract = LiquidityFund.deploy(
#             dao_fund,
#             dev_fund,
#             peg_token,
#             main_token,
#             sbond_bonus_reward_pool,
#             node_bonus_reward_pool,
#             treasury,
#             router_address,
#             {"from": deployer_account},
#             publish_source=publish_source,
#         )
#         append_new_line(
#             ".env",
#             "export LIQUIDITY_FUND=" + liquidity_fund_contract.address,
#         )
#     liquidity_fund_contract = LiquidityFund[-1]
#     os.environ["LIQUIDITY_FUND"] = liquidity_fund_contract.address
#     return liquidity_fund_contract


def main():
    deploy_maintoken()
    deploy_bondtoken()
    deploy_sharetoken()
    get_peg_token()
    deploy_main_token_lp()
    deploy_share_token_lp()
    deploy_boardroom()
    deploy_treasury_contract()
    deploy_treasury_oracle_contract()
    deploy_MainToken_oracle_contract()
    deploy_ShareToken_oracle_contract()
    deploy_DataFeed_oracle_contract()
    deploy_share_token_reward_pool()
    # deploy_bonus_reward_pool()
    deploy_main_token_node()
    deploy_share_token_node()
    deploy_genesis_pool()
    # deploy_sbond_reward_pool()
    deploy_tax_office()
    deploy_wrapped_router()


# import json
# slp_abi=open("./interfaces/lp_abi.json")
# abi_lp=json.load(slp_abi)
# slp=Contract.from_abi("slp","0xE2A1207be9E08E212d0EFe0Fc628A4367361A065",abi_lp)
# token_abi=open("./interfaces/token_abi.json")
# abi_token=json.load(token_abi)
# musdc=Contract.from_abi("token","0x39D8fa99c9964D456b9fbD5e059e63442F314121",abi_token)
# router_abi=open("./interfaces/router_abi.json")
# abi_router=json.load(router_abi)
# router=Contract.from_abi("router","0xc4e4DdB7a71fCF9Bb7356461Ca75124aA9910653",abi_router)
# zap_abi=open("./interfaces/zap_abi.json")
# abi_zap=json.load(zap_abi)
# zap=Contract.from_abi("zap","0x4af16D0b8DB8a49AE3D83847b99f8c8DF710a319",abi_zap)
