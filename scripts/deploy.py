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
    Treasury,
    ShareTokenRewardPool,
    MainTokenNode,
    ShareTokenNode,
    SnowBtcGenesisRewardPool,
    SnowEthGenesisRewardPool,
    SnowUsdcGenesisRewardPool,
    SnowUsdtGenesisRewardPool,
    SnowDaiGenesisRewardPool,
    SnowCroGenesisRewardPool,
    SnowSnowUsdcLpGenesisRewardPool,
    SnowNodeBonusRewardPool,
    SnowSbondBonusRewardPool,
    LiquidityFund,
)
from brownie.network.gas.strategies import GasNowStrategy

# from web3 import Web3
# from decimal import *

import datetime
import time
import os


KEPT_BALANCE = 100 * 10**18
gas_strategy = GasNowStrategy("fast")


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
start_time = (
    time.time() + 600
)  # deploy now // sharetoken, oracle - 1day, share_token_reward(chef), node + 7 days, genesis_pool - 12 hr, treasury
boardroom_start_time = time.time() + 600
oracle_period = 21600  # 6 hours


if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
    deployer_account = get_account()
    dao_fund = get_account(index=1)
    dev_fund = get_account(index=2)
    airdrop_account = get_account(index=3)
    insurance_fund = get_account(index=3)
else:
    deployer_account = get_account(id="snowcrystals-deployer")
    dao_fund = get_account(id="snowcrystals-dao")
    dev_fund = get_account(id="snowcrystals-dev")
    airdrop_account = get_account(id="snowcrystals-airdrop")
    insurance_fund = get_account(id="snowcrystals-airdrop")


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
            dao_fund,
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
        share_token = sharetoken.deploy(
            sharetoken_name,
            sharetoken_symbol,
            start_time,
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
        timestamp,
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


def deploy_oracle_contract():
    if len(Oracle) <= 0:
        main_token_lp = os.environ.get("MAIN_TOKEN_LP")
        main_token = os.environ.get("MAIN_TOKEN")
        print("deploying oracle!")
        main_token_oracle = Oracle.deploy(
            main_token_lp,
            oracle_period,
            start_time,
            main_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(".env", "export ORACLE=" + main_token_oracle.address)
    main_token_oracle = Oracle[-1]
    os.environ["ORACLE"] = main_token_oracle.address
    return main_token_oracle


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
            start_time,
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


def deploy_bonus_reward_pool():
    if len(SnowNodeBonusRewardPool) <= 0:
        print("deploying bonus reward pool!")
        main_token = os.environ.get("MAIN_TOKEN")
        pool_start_time = start_time
        deposit_token = os.environ.get("MAIN_TOKEN_LP")
        snow_bounus_pool_contract = SnowNodeBonusRewardPool.deploy(
            main_token,
            pool_start_time,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export NODE_BONUS_REWARD_POOL=" + snow_bounus_pool_contract.address,
        )
    snow_bounus_pool_contract = SnowNodeBonusRewardPool[-1]
    os.environ["NODE_BONUS_REWARD_POOL"] = snow_bounus_pool_contract.address
    return snow_bounus_pool_contract


def deploy_main_token_node():
    if len(MainTokenNode) <= 0:
        print("deploying Main node!")
        main_token_lp = os.environ.get("MAIN_TOKEN_LP")
        node_bonus_reward_pool = os.environ.get("NODE_BONUS_REWARD_POOL")
        main_token_node_contract = MainTokenNode.deploy(
            start_time,
            main_token_lp,
            node_bonus_reward_pool,
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
            start_time,
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


def deploy_usdc_genesis_pool():
    if len(SnowUsdcGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = os.environ.get("PEG_TOKEN")
        usdc_genesis_pool_contract = SnowUsdcGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export USDC_GENESIS_POOL=" + usdc_genesis_pool_contract.address
        )
    usdc_genesis_pool_contract = SnowUsdcGenesisRewardPool[-1]
    os.environ["USDC_GENESIS_POOL"] = usdc_genesis_pool_contract.address
    return usdc_genesis_pool_contract


def deploy_cro_genesis_pool():
    if len(SnowCroGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23"
        cro_genesis_pool_contract = SnowCroGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export CRO_GENESIS_POOL=" + cro_genesis_pool_contract.address
        )
    cro_genesis_pool_contract = SnowCroGenesisRewardPool[-1]
    os.environ["CRO_GENESIS_POOL"] = cro_genesis_pool_contract.address
    return cro_genesis_pool_contract


def deploy_btc_genesis_pool():
    if len(SnowBtcGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = "0x062E66477Faf219F25D27dCED647BF57C3107d52"
        btc_genesis_pool_contract = SnowBtcGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export BTC_GENESIS_POOL=" + btc_genesis_pool_contract.address
        )
    btc_genesis_pool_contract = SnowBtcGenesisRewardPool[-1]
    os.environ["BTC_GENESIS_POOL"] = btc_genesis_pool_contract.address
    return btc_genesis_pool_contract


def deploy_eth_genesis_pool():
    if len(SnowEthGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = "0xe44Fd7fCb2b1581822D0c862B68222998a0c299a"
        eth_genesis_pool_contract = SnowEthGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export ETH_GENESIS_POOL=" + eth_genesis_pool_contract.address
        )
    eth_genesis_pool_contract = SnowEthGenesisRewardPool[-1]
    os.environ["ETH_GENESIS_POOL"] = eth_genesis_pool_contract.address
    return eth_genesis_pool_contract


def deploy_dai_genesis_pool():
    if len(SnowDaiGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = "0xF2001B145b43032AAF5Ee2884e456CCd805F677D"
        dai_genesis_pool_contract = SnowDaiGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export DAI_GENESIS_POOL=" + dai_genesis_pool_contract.address
        )
    dai_genesis_pool_contract = SnowDaiGenesisRewardPool[-1]
    os.environ["DAI_GENESIS_POOL"] = dai_genesis_pool_contract.address
    return dai_genesis_pool_contract


def deploy_usdt_genesis_pool():
    if len(SnowUsdtGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = "0x66e428c3f67a68878562e79A0234c1F83c208770"
        usdt_genesis_pool_contract = SnowUsdtGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env", "export USDT_GENESIS_POOL=" + usdt_genesis_pool_contract.address
        )
    usdt_genesis_pool_contract = SnowUsdtGenesisRewardPool[-1]
    os.environ["USDT_GENESIS_POOL"] = usdt_genesis_pool_contract.address
    return usdt_genesis_pool_contract


def deploy_snowusdclp_genesis_pool():
    if len(SnowSnowUsdcLpGenesisRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 100
        pool_start_time = start_time
        deposit_token = os.environ.get("MAIN_TOKEN_LP")
        snowusdclp_genesis_pool_contract = SnowSnowUsdcLpGenesisRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export SNOWUSDC_GENESIS_POOL=" + snowusdclp_genesis_pool_contract.address,
        )
    snowusdclp_genesis_pool_contract = SnowSnowUsdcLpGenesisRewardPool[-1]
    os.environ["SNOWUSDC_GENESIS_POOL"] = snowusdclp_genesis_pool_contract.address
    return snowusdclp_genesis_pool_contract


def deploy_sbond_reward_pool():
    if len(SnowSbondBonusRewardPool) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        deposit_fee = 0
        pool_start_time = start_time
        deposit_token = os.environ.get("BOND_TOKEN")
        sbond_reward_pool_contract = SnowSbondBonusRewardPool.deploy(
            main_token,
            pool_start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export SBOND_REWARD_POOL=" + sbond_reward_pool_contract.address,
        )
    sbond_reward_pool_contract = SnowSbondBonusRewardPool[-1]
    os.environ["SBOND_REWARD_POOL"] = sbond_reward_pool_contract.address
    return sbond_reward_pool_contract


def deploy_liquidity_fund():
    if len(LiquidityFund) <= 0:
        main_token = os.environ.get("MAIN_TOKEN")
        peg_token = os.environ.get("PEG_TOKEN")
        sbond_bonus_reward_pool = os.environ.get("SBOND_REWARD_POOL")
        node_bonus_reward_pool = os.environ.get("NODE_BONUS_REWARD_POOL")
        treasury = os.environ.get("TREASURY")
        liquidity_fund_contract = LiquidityFund.deploy(
            dao_fund,
            dev_fund,
            peg_token,
            main_token,
            sbond_bonus_reward_pool,
            node_bonus_reward_pool,
            treasury,
            router_address,
            {"from": deployer_account},
            publish_source=publish_source,
        )
        append_new_line(
            ".env",
            "export LIQUIDITY_FUND=" + liquidity_fund_contract.address,
        )
    liquidity_fund_contract = LiquidityFund[-1]
    os.environ["LIQUIDITY_FUND"] = liquidity_fund_contract.address
    return liquidity_fund_contract


def main():
    deploy_maintoken()
    deploy_bondtoken()
    deploy_sharetoken()
    get_peg_token()
    deploy_main_token_lp()
    deploy_share_token_lp()
    deploy_boardroom()
    deploy_treasury_contract()
    deploy_oracle_contract()
    deploy_share_token_reward_pool()
    deploy_bonus_reward_pool()
    deploy_main_token_node()
    deploy_share_token_node()
    deploy_usdc_genesis_pool()
    deploy_cro_genesis_pool()
    deploy_usdt_genesis_pool()
    deploy_dai_genesis_pool()
    deploy_eth_genesis_pool()
    deploy_btc_genesis_pool()
    deploy_snowusdclp_genesis_pool()
    deploy_sbond_reward_pool()
    deploy_liquidity_fund()


# import json
# slp_abi=open("./interfaces/lp_abi.json")
# abi_lp=json.load(slp_abi)
# slp=Contract.from_abi("slp","0xAEB669993330A39fAeA5B188b22354894c9b65ee",abi_lp)
# token_abi=open("./interfaces/token_abi.json")
# abi_token=json.load(token_abi)
# musdc=Contract.from_abi("token","0x39D8fa99c9964D456b9fbD5e059e63442F314121",abi_token)
# router_abi=open("./interfaces/router_abi.json")
# abi_router=json.load(router_abi)
# router=Contract.from_abi("router","0xc4e4DdB7a71fCF9Bb7356461Ca75124aA9910653",abi_router)
# zap_abi=open("./interfaces/zap_abi.json")
# abi_zap=json.load(zap_abi)
# zap=Contract.from_abi("zap","0x4af16D0b8DB8a49AE3D83847b99f8c8DF710a319",abi_zap)
