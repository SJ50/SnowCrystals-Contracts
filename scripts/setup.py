from ctypes import addressof
from tracemalloc import start
from scripts.helpful_scripts import (
    get_account,
    get_abi,
    get_contract,
    NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS,
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
)

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


### setup all contract
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


def setup_main_token():
    main_token_contract = Contract(main_token)
    print("Maintoken setting treasury as operator...")
    set_operator_tx = main_token_contract.transferOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)
    print("Maintoken setting oracle...")
    set_oracle_tx = main_token_contract.setOracle(
        oracle,
        {"from": deployer_account},
    )
    set_oracle_tx.wait(1)
    print("Maintoken exclude maintokenLP from tax to make buying token tax free...")
    set_lp_exclude_from_free_tx = main_token_contract.setExcludeFromFee(
        main_token_lp,
        True,
        {"from": deployer_account},
    )
    set_lp_exclude_from_free_tx.wait(1)
    for X in range(8):
        print(f"Maintoken set burntier rates for index {X}")
        set_burn_tier_twap = main_token_contract.setBurnTiersRate(
            X,
            1200,
            {"from": deployer_account},
        )
        set_burn_tier_twap.wait(1)
    for X in range(8, 10):
        print(f"Maintoken set burntier rates for index {X}")
        set_burn_tier_twap = main_token_contract.setBurnTiersRate(
            X,
            400,
            {"from": deployer_account},
        )
        set_burn_tier_twap.wait(1)
    for X in range(10, 14):
        print(f"Maintoken set burntier rates for index {X}")
        set_burn_tier_twap = main_token_contract.setBurnTiersRate(
            X,
            400,
            {"from": deployer_account},
        )
        set_burn_tier_twap.wait(1)
    print("Maintoken set tax rate...")
    set_tax_rate_tx = main_token_contract.setTaxRate(
        400,
        {"from": deployer_account},
    )
    set_tax_rate_tx.wait(1)

    # for X in range(8):
    #     print(f"Maintoken set burntier rates for index {X}")
    #     set_tax_tier_rate = main_token_contract.setTaxTiersRate(
    #         X,
    #         400,
    #         {"from": deployer_account},
    #     )
    #     set_tax_tier_rate.wait(1)
    # for X in range(8, 10):
    #     print(f"Maintoken set burntier rates for index {X}")
    #     set_tax_tier_rate = main_token_contract.setTaxTiersRate(
    #         X,
    #         400,
    #         {"from": deployer_account},
    #     )
    #     set_tax_tier_rate.wait(1)
    # for X in range(10, 14):
    #     print(f"Maintoken set burntier rates for index {X}")
    #     set_tax_tier_rate = main_token_contract.setTaxTiersRate(
    #         X,
    #         100,
    #         {"from": deployer_account},
    #     )
    #     set_tax_tier_rate.wait(1)


def setup_bond_token():
    bond_token_contract = Contract(bond_token)
    print("Bondtoken setting treasury as operator...")
    set_operator_tx = bond_token_contract.transferOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)


def setup_share_token():
    share_token_contract = Contract(share_token)
    print("Sharetoken setting treasury as operator...")
    set_operator_tx = share_token_contract.transferOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)


def setup_boardroom():
    share_token_contract = Contract(share_token)
    boardroom_contract = Contract(boardroom)
    print("Initializing boardroom...")
    boardroom_initialized_tx = boardroom_contract.initialize(
        main_token,
        share_token,
        treasury,
        {"from": deployer_account},
    )
    boardroom_initialized_tx.wait(1)
    # print("Setting Oracle...")
    # main_token_oracle = deploy_main_token_oracle_contract()
    # boardroom_token_config_tx = boardroom_contract.setPegTokenConfig(
    #     main_token,
    #     oracle,
    #     {"from": deployer_account},
    # )
    # boardroom_token_config_tx.wait(1)
    # print("adding peg tokens..")
    # boardroom_add_peg_token_tx = boardroom_contract.addPegToken(
    #     main_token,
    #     {"from": deployer_account},
    # )
    # boardroom_add_peg_token_tx.wait(1)
    print("Boardroom setting treasury as operator...")
    set_operator_tx = boardroom_contract.setOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)
    approve_share_token_tx = share_token_contract.approve(
        boardroom, 10 * 10**18, {"from": dao_fund}
    )
    approve_share_token_tx.wait(1)
    stake_tx = boardroom_contract.stake(1 * 10**18, {"from": dao_fund})
    stake_tx.wait(1)


def setup_maintoken_oracle():
    oracle_contract = Contract(oracle)
    print("Updating Oracle...")
    update_tx = oracle_contract.update({"from": deployer_account})
    update_tx.wait(1)


def setup_treasury():
    treasury_contract = Contract(treasury)
    print("Initializing treasury...")
    intialized_tx = treasury_contract.initialize(
        main_token,
        bond_token,
        share_token,
        oracle,
        boardroom,
        start_time,
        {"from": deployer_account},
    )
    intialized_tx.wait(1)
    set_extra_fund_tx = treasury_contract.setExtraFunds(
        dao_fund,
        3000,
        dev_fund,
        500,
        {"from": deployer_account},
    )
    set_extra_fund_tx.wait(1)
    set_minting_factory_for_paying_debt_tx = (
        treasury_contract.setMintingFactorForPayingDebt(
            15000, {"from": deployer_account}
        )
    )
    set_minting_factory_for_paying_debt_tx.wait(1)
    # time.sleep(700)
    # allocate_seigniorage_tx = treasury.allocateSeigniorage(
    #     {"from": deployer_account}
    # )
    # allocate_seigniorage_tx.wait(1)
    # set_boot_strap_tx = treasury.setBootstrap(30, 400, {"from": deployer_account})
    # set_boot_strap_tx.wait(1)
    """
    (40,350) @ 24 epoch // @ 6 days
    (60,300) @ 40 epoch // @ 10 days
    (80,250) @ 56 epoch // @ 14 days
    (76,150) @ 64 epoch // @ 18 days
   
    """


def setup_share_reward_pool():
    share_reward_pool_contract = Contract(share_reward_pool)
    share_reward_add_maintoken_lp_tx = share_reward_pool_contract.add(
        30000, main_token_lp, 0, 0, {"from": deployer_account}
    )
    share_reward_add_maintoken_lp_tx.wait(1)
    share_reward_add_sharetoken_lp_tx = share_reward_pool_contract.add(
        20000, share_token_lp, 0, 0, {"from": deployer_account}
    )
    share_reward_add_sharetoken_lp_tx.wait(1)


def setup_bonus_reward_pool():
    bonus_reward_pool_contract = Contract(bonus_reward_pool)
    bonus_reward_pool_set_node_tx = bonus_reward_pool_contract.setNode(
        main_token_node, {"from": deployer_account}
    )
    bonus_reward_pool_set_node_tx.wait(1)


def main():
    setup_main_token()
    setup_maintoken_oracle()
    setup_bond_token()
    setup_share_token()
    setup_boardroom()
    setup_treasury()
    setup_share_reward_pool()
    setup_bonus_reward_pool()
    # get_all_info()
