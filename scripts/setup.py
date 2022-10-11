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
    SnowUsdtGenesisRewardPool,
    SnowDaiGenesisRewardPool,
    SnowCroGenesisRewardPool,
    SnowSnowUsdcLpGenesisRewardPool,
    SnowNodeBonusRewardPool,
    SnowSbondBonusRewardPool,
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
    time.time() + 180
)  # deploy now // sharetoken, oracle - 1day, share_token_reward(chef), node + 7 days, genesis_pool - 12 hr, treasury
boardroom_start_time = time.time() + 180
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


### setup all contract
peg_token = os.environ.get("PEG_TOKEN")
main_token = os.environ.get("MAIN_TOKEN")
treasury = os.environ.get("TREASURY")
oracle = os.environ.get("ORACLE")
main_token_oracle = os.environ.get("MAINTOKEN_ORACLE")
share_token_oracle = os.environ.get("SHARETOKEN_ORACLE")
datafeed_oracle = os.environ.get("DATAFEED_ORACLE")
bond_token = os.environ.get("BOND_TOKEN")
share_token = os.environ.get("SHARE_TOKEN")
boardroom = os.environ.get("BOARDROOM")
share_reward_pool = os.environ.get("SHARE_TOKEN_REWARD_POOL")
main_token_lp = os.environ.get("MAIN_TOKEN_LP")
share_token_lp = os.environ.get("SHARE_TOKEN_LP")
node_bonus_reward_pool = os.environ.get("NODE_BONUS_REWARD_POOL")
main_token_node = os.environ.get("MAIN_TOKEN_NODE")
share_token_node = os.environ.get("SHARE_TOKEN_NODE")
genesis_pool = os.environ.get("GENESIS_POOL")
# sbond_reward_pool = os.environ.get("SBOND_REWARD_POOL")
tax_office = os.environ.get("TAX_OFFICE")
wrapped_router = os.environ.get("WRAPPED_ROUTER")
# liquidity_fund = os.environ.get("LIQUIDITY_FUND")
snow_dao_rebate_treasury = os.environ.get("SNOW_DAO_REBATE_TREASURY")
glcr_dao_rebate_treasury = os.environ.get("GLCR_DAO_REBATE_TREASURY")
snow_dev_rebate_treasury = os.environ.get("SNOW_DEV_REBATE_TREASURY")
glcr_dev_rebate_treasury = os.environ.get("GLCR_DEV_REBATE_TREASURY")
zap = os.environ.get("ZAP")


def setup_main_token():
    main_token_contract = Contract(main_token)

    print("Maintoken setting taxoffice...")
    set_maintoken_taxoffice_tx = main_token_contract.setTaxOffice(
        tax_office,
        {"from": deployer_account},
    )
    set_maintoken_taxoffice_tx.wait(1)

    print("Distribute rewards...")
    set_distribute_reward_tx = main_token_contract.distributeReward(
        genesis_pool,
        dao_fund,
        {"from": deployer_account},
    )
    set_distribute_reward_tx.wait(1)

    print("Maintoken setting treasury as operator...")
    set_operator_tx = main_token_contract.transferOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)

    print("renounce ownership..")
    set_renounceOwnership_tx = main_token_contract.renounceOwnership(
        {"from": deployer_account}
    )
    set_renounceOwnership_tx.wait(1)


def set_taxoffice_maintoken():
    tax_office_contract = Contract(tax_office)
    print("Maintoken set static tax rate...")
    set_static_tax_rate_tx = tax_office_contract.setMainTokenStaticTaxRate(
        2500,
        {"from": deployer_account},
    )
    set_static_tax_rate_tx.wait(1)

    print("maintoken exclude Boardroom from tax to claim maintoken free...")
    set_boardroom_whitelist_type_tx = tax_office_contract.setMainTokenWhitelistType(
        boardroom,
        3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_boardroom_whitelist_type_tx.wait(1)

    print("Maintoken exclude maintokenLP from tax to make buying token tax free...")
    set_lp_whitelist_type_tx = tax_office_contract.setMainTokenWhitelistType(
        main_token_lp,
        1,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_lp_whitelist_type_tx.wait(1)

    print(
        "Maintoken exclude zap from tax to make zap maintoken properly taxed and pegtoken free..."
    )
    set_zap_whitelist_type_tx = tax_office_contract.setMainTokenWhitelistType(
        zap,
        1,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_zap_whitelist_type_tx.wait(1)

    # print(
    #     "Maintoken exclude Treasury from tax to minting and transfering maintoken to Boardroom free..."
    # )
    # set_treasury_whitelist_type_tx = tax_office_contract.setMainTokenWhitelistType(
    #     treasury,
    #     3,
    #     {"from": deployer_account},
    # )
    # set_treasury_whitelist_type_tx.wait(1)

    print(
        "Maintoken exclude TaxOffice transfering maintoken to and from TaxOffice free..."
    )
    set_tax_office_whitelist_type_tx = tax_office_contract.setMainTokenWhitelistType(
        tax_office,
        3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_tax_office_whitelist_type_tx.wait(1)

    print(
        "Maintoken exclude wrapped_router transfering maintoken to and from wrapped_router free..."
    )
    set_wrapped_router_whitelist_type_tx = (
        tax_office_contract.setMainTokenWhitelistType(
            wrapped_router,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_wrapped_router_whitelist_type_tx.wait(1)

    # print(
    #     "Maintoken exclude node_bonus transfering and claiming maintoken to & from node_bonus free..."
    # )
    # set_node_bonus_reward_pool_whitelist_type_tx = (
    #     tax_office_contract.setMainTokenWhitelistType(
    #         node_bonus_reward_pool,
    #         3,
    #         {"from": deployer_account},
    #     )
    # )
    # set_node_bonus_reward_pool_whitelist_type_tx.wait(1)

    # print(
    #     "Maintoken exclude sbond_bonus transfering and claiming maintoken to & from sbond_bonus free..."
    # )
    # set_sbond_reward_pool_whitelist_type_tx = (
    #     tax_office_contract.setMainTokenWhitelistType(
    #         sbond_reward_pool,
    #         3,
    #         {"from": deployer_account},
    #     )
    # )
    # set_sbond_reward_pool_whitelist_type_tx.wait(1)

    print("Maintoken exclude rebate_treasury claiming maintoken free...")
    set_rebate_treasury_whitelist_type_tx = (
        tax_office_contract.setMainTokenWhitelistType(
            snow_dao_rebate_treasury,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_rebate_treasury_whitelist_type_tx.wait(1)

    print("Maintoken exclude dev_rebate_treasury claiming maintoken free...")
    set_rebate_treasury_whitelist_type_tx = (
        tax_office_contract.setMainTokenWhitelistType(
            snow_dev_rebate_treasury,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_rebate_treasury_whitelist_type_tx.wait(1)


def set_taxoffice_sharetoken():
    tax_office_contract = Contract(tax_office)
    print("sharetoken set static tax rate...")
    set_static_tax_rate_tx = tax_office_contract.setShareTokenStaticTaxRate(
        2500,
        {"from": deployer_account},
    )
    set_static_tax_rate_tx.wait(1)

    print("sharetoken exclude Boardroom to deposit and withdraw sharetoken free...")
    set_boardroom_whitelist_type_tx = tax_office_contract.setShareTokenWhitelistType(
        boardroom,
        3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_boardroom_whitelist_type_tx.wait(1)

    print("sharetoken exclude sharetokenLP from tax to make buying token tax free...")
    set_lp_whitelist_type_tx = tax_office_contract.setShareTokenWhitelistType(
        share_token_lp,
        1,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_lp_whitelist_type_tx.wait(1)

    print(
        "sharetoken exclude zap from tax to make zap sharetoken properly taxed and pegtoken free..."
    )
    set_zap_whitelist_type_tx = tax_office_contract.setShareTokenWhitelistType(
        zap,
        1,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_zap_whitelist_type_tx.wait(1)

    # print(
    #     "sharetoken exclude Treasury from tax to minting and transfering sharetoken to Boardroom free..."
    # )
    # set_treasury_whitelist_type_tx = tax_office_contract.setShareTokenWhitelistType(
    #     treasury,
    #     3,
    #     {"from": deployer_account},
    # )
    # set_treasury_whitelist_type_tx.wait(1)

    print(
        "sharetoken exclude TaxOffice transfering sharetoken to and from TaxOffice free..."
    )
    set_tax_office_whitelist_type_tx = tax_office_contract.setShareTokenWhitelistType(
        tax_office,
        3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
        {"from": deployer_account},
    )
    set_tax_office_whitelist_type_tx.wait(1)

    print(
        "sharetoken exclude wrapped_router transfering sharetoken to and from wrapped_router free..."
    )
    set_wrapped_router_whitelist_type_tx = (
        tax_office_contract.setShareTokenWhitelistType(
            wrapped_router,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_wrapped_router_whitelist_type_tx.wait(1)

    print("sharetoken exclude rebate_treasury claiming sharetoken free...")
    set_rebate_treasury_whitelist_type_tx = (
        tax_office_contract.setShareTokenWhitelistType(
            glcr_dao_rebate_treasury,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_rebate_treasury_whitelist_type_tx.wait(1)

    print("sharetoken exclude dev_rebate_treasury claiming sharetoken free...")
    set_rebate_treasury_whitelist_type_tx = (
        tax_office_contract.setShareTokenWhitelistType(
            glcr_dev_rebate_treasury,
            3,  #    0 = NONE, 1 = SENDER, 2 = RECIPIENT, 3 = BOTH
            {"from": deployer_account},
        )
    )
    set_rebate_treasury_whitelist_type_tx.wait(1)


def setup_bond_token():
    bond_token_contract = Contract(bond_token)
    print("Bondtoken setting treasury as operator...")
    set_operator_tx = bond_token_contract.transferOperator(
        treasury,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)
    print("renounce ownership..")
    set_renounceOwnership_tx = bond_token_contract.renounceOwnership(
        {"from": deployer_account}
    )
    set_renounceOwnership_tx.wait(1)


def setup_share_token():
    share_token_contract = Contract(share_token)
    print("Sharetoken setting taxoffice...")
    set_sharetoken_taxoffice_tx = share_token_contract.setTaxOffice(
        tax_office,
        {"from": deployer_account},
    )
    set_sharetoken_taxoffice_tx.wait(1)

    print("mint farmingfund")
    mint_farming_fund_tx = share_token_contract.distributeReward(
        share_reward_pool,
        {"from": deployer_account},
    )
    mint_farming_fund_tx.wait(1)

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


def setup_treasury_oracle():
    oracle_contract = Contract(oracle)
    print("Updating Oracle...")
    update_tx = oracle_contract.update({"from": deployer_account})
    update_tx.wait(1)
    print("setting Treasury as Oracle operator...")
    transfer_operator_tx = oracle_contract.transferOperator(
        treasury, {"from": deployer_account}
    )
    transfer_operator_tx.wait(1)


def setup_MainToken_oracle():
    oracle_contract = Contract(main_token_oracle)
    print("Updating MainToken Oracle...")
    update_tx = oracle_contract.update({"from": deployer_account})
    update_tx.wait(1)
    print("setting TaxOffice as Oracle operator...")
    transfer_operator_tx = oracle_contract.transferOperator(
        tax_office, {"from": deployer_account}
    )
    transfer_operator_tx.wait(1)


def setup_ShareToken_oracle():
    oracle_contract = Contract(share_token_oracle)
    print("Updating ShareToken Oracle...")
    update_tx = oracle_contract.update({"from": deployer_account})
    update_tx.wait(1)
    # print("setting Treasury as Oracle operator...")
    # transfer_operator_tx = oracle_contract.transferOperator(
    #     treasury, {"from": deployer_account}
    # )
    # transfer_operator_tx.wait(1)


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
        tax_office,
        [genesis_pool],
        {"from": deployer_account},
    )
    intialized_tx.wait(1)
    set_extra_fund_tx = treasury_contract.setExtraFunds(
        dao_fund,
        800,
        dev_fund,
        800,
        snow_dao_rebate_treasury,
        2200,
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


def setup_genesis_pool():
    genesis_pool_contract = Contract(genesis_pool)
    wBTC = config["networks"][network.show_active()]["wbtc_token"]
    wETH = config["networks"][network.show_active()]["weth_token"]
    wCRO = config["networks"][network.show_active()]["wcro_token"]
    wDAI = config["networks"][network.show_active()]["dai_token"]
    wUSDT = config["networks"][network.show_active()]["usdt_token"]
    print("adding wBTC to genesis pool...")
    set_wBTC_genesis_pool_tx = genesis_pool_contract.add(
        1, wBTC, False, 0, {"from": deployer_account}
    )
    set_wBTC_genesis_pool_tx.wait(1)
    print("adding wETH to genesis pool...")
    set_wETH_genesis_pool_tx = genesis_pool_contract.add(
        1, wETH, False, 0, {"from": deployer_account}
    )
    set_wETH_genesis_pool_tx.wait(1)
    print("adding wCRO to genesis pool...")
    set_wCRO_genesis_pool_tx = genesis_pool_contract.add(
        1, wCRO, False, 0, {"from": deployer_account}
    )
    set_wCRO_genesis_pool_tx.wait(1)
    print("adding wDAI to genesis pool...")
    set_wDAI_genesis_pool_tx = genesis_pool_contract.add(
        1, wDAI, False, 0, {"from": deployer_account}
    )
    set_wDAI_genesis_pool_tx.wait(1)
    print("adding wUSDT to genesis pool...")
    set_wUSDT_genesis_pool_tx = genesis_pool_contract.add(
        1, wUSDT, False, 0, {"from": deployer_account}
    )
    set_wUSDT_genesis_pool_tx.wait(1)


def setup_share_reward_pool():
    share_reward_pool_contract = Contract(share_reward_pool)
    share_reward_add_maintoken_lp_tx = share_reward_pool_contract.add(
        60, main_token_lp, 0, 0, {"from": deployer_account}
    )
    share_reward_add_maintoken_lp_tx.wait(1)
    share_reward_add_sharetoken_lp_tx = share_reward_pool_contract.add(
        40, share_token_lp, 0, 0, {"from": deployer_account}
    )
    share_reward_add_sharetoken_lp_tx.wait(1)
    share_reward_add_bond_tx = share_reward_pool_contract.add(
        0, bond_token, 0, 0, {"from": deployer_account}
    )
    share_reward_add_bond_tx.wait(1)


# def setup_node_bonus_reward_pool():
#     node_bonus_reward_pool_contract = Contract(node_bonus_reward_pool)
#     node_bonus_reward_pool_set_node_tx = node_bonus_reward_pool_contract.setNode(
#         main_token_node, {"from": deployer_account}
#     )
#     node_bonus_reward_pool_set_node_tx.wait(1)
#     node_bonus_reward_pool_set_liqudity_fund_tx = (
#         node_bonus_reward_pool_contract.setTaxOffice(
#             tax_office, {"from": deployer_account}
#         )
#     )
#     node_bonus_reward_pool_set_liqudity_fund_tx.wait(1)


# def setup_sbond_bonus_reward_pool():
#     sbond_bonus_reward_pool_contract = Contract(sbond_reward_pool)
#     sbond_bonus_reward_pool_set_share_token_reward_pool_tx = (
#         sbond_bonus_reward_pool_contract.setGlcrRewardPool(
#             share_reward_pool, {"from": deployer_account}
#         )
#     )
#     sbond_bonus_reward_pool_set_share_token_reward_pool_tx.wait(1)
#     sbond_bonus_reward_pool_set_liqudity_fund_tx = (
#         sbond_bonus_reward_pool_contract.setTaxOffice(
#             tax_office, {"from": deployer_account}
#         )
#     )
#     sbond_bonus_reward_pool_set_liqudity_fund_tx.wait(1)


def setup_zap():
    zap_abi = get_abi("zap_abi.json")
    zap_contract = Contract.from_abi("zap", zap, zap_abi)
    zap_setIsFeeOnTransfer_tx = zap_contract.setIsFeeOnTransfer(
        main_token, {"from": deployer_account}
    )
    zap_setIsFeeOnTransfer_tx.wait(1)


def setup_dao_snow_rebate():
    snow_rebate_abi = get_abi("snow_rebate_abi.json")
    snow_rebate_contract = Contract.from_abi(
        "snow rebate", snow_dao_rebate_treasury, snow_rebate_abi
    )
    snow_rebate_setAsset_tx = snow_rebate_contract.setAsset(
        peg_token,  # USDC
        True,
        1100000,  # multiplyer
        datafeed_oracle,  # USDC oracle
        False,
        "0x0000000000000000000000000000000000000000",
        {"from": deployer_account},
    )
    snow_rebate_setAsset_tx.wait(1)


def setup_dao_glcr_rebate():
    glcr_rebate_abi = get_abi("snow_rebate_abi.json")
    glcr_rebate_contract = Contract.from_abi(
        "snow rebate", glcr_dao_rebate_treasury, glcr_rebate_abi
    )
    glcr_rebate_setAsset_tx = glcr_rebate_contract.setAsset(
        peg_token,  # USDC
        True,
        1100000,  # multiplyer
        datafeed_oracle,  # USDC oracle
        False,
        "0x0000000000000000000000000000000000000000",
        {"from": deployer_account},
    )
    glcr_rebate_setAsset_tx.wait(1)


def setup_dev_snow_rebate():
    snow_rebate_abi = get_abi("snow_rebate_abi.json")
    snow_rebate_contract = Contract.from_abi(
        "snow rebate", snow_dev_rebate_treasury, snow_rebate_abi
    )
    snow_rebate_setAsset_tx = snow_rebate_contract.setAsset(
        peg_token,  # USDC
        True,
        1100000,  # multiplyer
        datafeed_oracle,  # USDC oracle
        False,
        "0x0000000000000000000000000000000000000000",
        {"from": deployer_account},
    )
    snow_rebate_setAsset_tx.wait(1)


def setup_dev_glcr_rebate():
    glcr_rebate_abi = get_abi("snow_rebate_abi.json")
    glcr_rebate_contract = Contract.from_abi(
        "snow rebate", glcr_dev_rebate_treasury, glcr_rebate_abi
    )
    glcr_rebate_setAsset_tx = glcr_rebate_contract.setAsset(
        peg_token,  # USDC
        True,
        1100000,  # multiplyer
        datafeed_oracle,  # USDC oracle
        False,
        "0x0000000000000000000000000000000000000000",
        {"from": deployer_account},
    )
    glcr_rebate_setAsset_tx.wait(1)


def get_all_info():
    print(f"The active network is {network.show_active()}")
    print(f"PEG token is {peg_token}")
    print(f"MAIN token is {main_token}")
    print(f"BOND token is {bond_token}")
    print(f"SHARE token is {share_token}")
    print(f"BOARDROOM contract is {boardroom}")
    print(f"TREASURY contract is {treasury}")
    print(f"ORACLE contract is {oracle}")
    print(f"MainToken_ORACKE contract is {main_token_oracle}")
    print(f"ShareToken_ORACKE contract is {share_token_oracle}")
    print(f"DataFeed ORACLE contract is {datafeed_oracle}")
    print(f"MAIN TOKEN LIQUIDITY POOL contract is {main_token_lp}")
    print(f"SHARE TOKEN LIQUIDITY POOL contract is {share_token_lp}")
    print(f"SHARE TOKEN REWARD contract is {share_reward_pool}")
    # print(f"NODE BONUS REWARD POOL contract is {node_bonus_reward_pool}")
    print(f"MAIN TOKEN NODE contract is {main_token_node}")
    print(f"SHARE TOKEN NODE contract is {share_token_node}")
    print(f"GENESIS POOL contract is {genesis_pool}")
    # print(f"SBOND BONUS POOL contract is {sbond_reward_pool}")
    # print(f"LIQUIDITY FUND contract is {liquidity_fund}")
    print(f"ZAP contract is {zap}")
    print(f"TAX OFFICE contract is {tax_office}")
    print(f"WRAPPED ROUTER contract is {wrapped_router}")
    print(f"SNOW DAO REBATE TREASURY contract is {snow_dao_rebate_treasury}")
    print(f"GLCR DAO REBATE TREASURY contract is {glcr_dao_rebate_treasury}")
    print(f"SNOW DEV REBATE TREASURY contract is {snow_dev_rebate_treasury}")
    print(f"GLCR DEV REBATE TREASURY contract is {glcr_dev_rebate_treasury}")
    print(f"contract deployer account {deployer_account}")
    print(f"dao account {dao_fund}")
    print(f"devloper account {dev_fund}")
    print(f"airdrop account {airdrop_account}")


def main():
    setup_main_token()
    set_taxoffice_maintoken()
    setup_bond_token()
    setup_share_token()
    set_taxoffice_sharetoken()
    setup_boardroom()
    setup_treasury_oracle()
    setup_MainToken_oracle()
    setup_ShareToken_oracle()
    setup_treasury()
    setup_genesis_pool()
    setup_share_reward_pool()
    # setup_node_bonus_reward_pool()
    # setup_node_bonus_reward_pool()
    # setup_sbond_bonus_reward_pool()
    setup_zap()
    setup_dao_snow_rebate()
    setup_dao_glcr_rebate()
    setup_dev_snow_rebate()
    setup_dev_glcr_rebate()
    get_all_info()
