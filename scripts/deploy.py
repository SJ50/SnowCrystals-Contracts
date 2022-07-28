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
    Wlrs,
    SBond,
    WBond,
    Glcr,
    WShare,
    Boardroom,
    BoardroomCopy,
    Oracle,
    Treasury,
    TreasuryCopy,
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


def get_peg_token():
    if network.show_active() in NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        return get_contract("usdc_token")
    else:
        usdc_abi = get_abi("usdc_abi.json")
        return Contract.from_abi("USDC", peg_token, usdc_abi)


def get_btc_token():
    if network.show_active() in NON_FORKED_LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        return get_contract("btc_token")
    else:
        usdc_abi = get_abi("usdc_abi.json")
        return Contract.from_abi("USDC", peg_token, usdc_abi)


def deploy_maintoken():
    if len(maintoken) <= 0:
        print("deploying maintoken!")
        main_token = maintoken.deploy(
            maintoken_name,
            maintoken_symbol,
            airdrop_account,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    main_token = maintoken[-1]
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
    bond_token = bondtoken[-1]
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
    share_token = sharetoken[-1]
    return share_token


def deploy_boardroom():
    if len(Boardroom) <= 0:
        print("deploying boardroom!")
        boardroom = Boardroom.deploy(
            {"from": deployer_account},
            publish_source=publish_source,
        )
    boardroom_contract = Boardroom[-1]
    return boardroom_contract


# def deploy_devfund():
#     dev_fund_


def create_pair(tokenA, tokenB):
    mmf_factory_abi = get_abi("mmf_factory_abi.json")
    mmf_factory = Contract.from_abi("mmf_factory", mmf_factory_address, mmf_factory_abi)

    get_pair_tx = mmf_factory.getPair(tokenA, tokenB, {"from": deployer_account})
    if get_pair_tx != "0x0000000000000000000000000000000000000000":
        return get_pair_tx

    print("creating pair!")
    create_pair_tx = mmf_factory.createPair(tokenA, tokenB, {"from": deployer_account})
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

    mmf_router_abi = get_abi("mmf_router_abi.json")
    mmf_router = Contract.from_abi("mmf_router", mmf_router_address, mmf_router_abi)
    if main_token_lp:
        tokenA = get_peg_token()
        tokenB = deploy_maintoken()
        return create_pair(tokenA, tokenB)
    if share_token_lp:
        tokenA = get_peg_token()
        tokenB = deploy_sharetoken()
        return create_pair(tokenA, tokenB)

    print("approving tokenA...")
    tx_approve_tokenA = tokenA.approve(
        mmf_router.address, amountADesired, {"from": deployer_account}
    )
    tx_approve_tokenA.wait(1)
    print("approving tokenB...")
    tx_approve_tokenB = tokenB.approve(
        mmf_router.address, amountBDesired, {"from": deployer_account}
    )
    tx_approve_tokenB.wait(1)

    blockNumber = web3.eth.blockNumber
    block = web3.eth.getBlock(blockNumber)
    timestamp = block.timestamp + 300
    print("adding liquidity pool...")
    add_liquidity_tx = mmf_router.addLiquidity(
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
    tokenA = get_peg_token()
    tokenB = deploy_maintoken()
    amountADesired = 1 * 10**6
    amountBDesired = 1 * 10**18 / 5
    amountAMin = 1 * 10**6
    amountBMin = 1 * 10**18 / 5
    create_liquidity_pool(
        tokenA=tokenA,
        tokenB=tokenB,
        amountADesired=amountADesired,
        amountBDesired=amountBDesired,
        amountAMin=amountAMin,
        amountBMin=amountBMin,
    )


def deploy_share_token_lp():
    tokenA = get_peg_token()
    tokenB = deploy_sharetoken()
    amountADesired = 1 * 10**6
    amountBDesired = 1 * 10**18 / 1000
    amountAMin = 1 * 10**18
    amountBMin = 1 * 10**18 / 1000
    create_liquidity_pool(
        tokenA=tokenA,
        tokenB=tokenB,
        amountADesired=amountADesired,
        amountBDesired=amountBDesired,
        amountAMin=amountAMin,
        amountBMin=amountBMin,
    )


def deploy_main_token_oracle_contract():
    if len(Oracle) <= 0:
        pair = create_liquidity_pool(main_token_lp=True)
        # pair = "0xB63E20a3f301bB6e9A00970b185Da72Ff3987718"
        print("deploying oracle!")
        main_token_oracle = Oracle.deploy(
            pair,
            oracle_period,
            start_time,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    main_token_oracle = Oracle[-1]
    return main_token_oracle


def deploy_treasury_contract():
    if len(Treasury) <= 0:
        print("deploying treasury!")
        treasury_contract = Treasury.deploy(
            {"from": deployer_account},
            publish_source=publish_source,
        )
    treasury_contract = Treasury[-1]
    return treasury_contract


def deploy_share_token_reward_pool():
    if len(ShareTokenRewardPool) <= 0:
        print("deploying SHARE reward pool!")
        share_token_reward_pool = ShareTokenRewardPool.deploy(
            deploy_sharetoken(),
            dao_fund,
            start_time,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    share_token_reward_pool_contract = ShareTokenRewardPool[-1]
    return share_token_reward_pool_contract


def deploy_main_token_node():
    if len(MainTokenNode) <= 0:
        print("deploying Main node!")
        main_token_pair = create_liquidity_pool(main_token_lp=True)
        main_token_node = MainTokenNode.deploy(
            start_time,
            main_token_pair,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    main_token_node_contract = MainTokenNode[-1]
    return main_token_node_contract


def deploy_share_token_node():
    if len(ShareTokenNode) <= 0:
        print("deploying SHARE node!")
        share_token_pair = create_liquidity_pool(share_token_lp=True)
        share_token_node = ShareTokenNode.deploy(
            start_time,
            share_token_pair,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    share_token_node_contract = ShareTokenNode[-1]
    return share_token_node_contract


def deploy_usdc_genesis_pool():
    if len(SnowUsdcGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = get_peg_token()
        usdc_genesis_pool = SnowUsdcGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    usdc_genesis_pool_contract = SnowUsdcGenesisRewardPool[-1]
    return usdc_genesis_pool_contract


def deploy_cro_genesis_pool():
    if len(SnowCroGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23"
        cro_genesis_pool = SnowCroGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    cro_genesis_pool_contract = SnowCroGenesisRewardPool[-1]
    return cro_genesis_pool_contract


def deploy_btc_genesis_pool():
    if len(SnowBtcGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = "0x062E66477Faf219F25D27dCED647BF57C3107d52"
        btc_genesis_pool = SnowBtcGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    btc_genesis_pool_contract = SnowBtcGenesisRewardPool[-1]
    return btc_genesis_pool_contract


def deploy_eth_genesis_pool():
    if len(SnowEthGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = "0xe44Fd7fCb2b1581822D0c862B68222998a0c299a"
        eth_genesis_pool = SnowEthGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    eth_genesis_pool_contract = SnowEthGenesisRewardPool[-1]
    return eth_genesis_pool_contract


def deploy_dai_genesis_pool():
    if len(SnowDaiGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = "0xF2001B145b43032AAF5Ee2884e456CCd805F677D"
        dai_genesis_pool = SnowDaiGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    dai_genesis_pool_contract = SnowDaiGenesisRewardPool[-1]
    return dai_genesis_pool_contract


def deploy_usdt_genesis_pool():
    if len(SnowUsdtGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = "0x66e428c3f67a68878562e79A0234c1F83c208770"
        usdt_genesis_pool = SnowUsdtGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    usdt_genesis_pool_contract = SnowUsdtGenesisRewardPool[-1]
    return usdt_genesis_pool_contract


def deploy_snowusdclp_genesis_pool():
    if len(SnowSnowUsdcLpGenesisRewardPool) <= 0:
        main_token = deploy_maintoken()
        pool_start_time = start_time
        deposit_fee = 100
        deposit_token = create_liquidity_pool(main_token_lp=True)
        snowusdclp_genesis_pool = SnowSnowUsdcLpGenesisRewardPool.deploy(
            main_token,
            start_time,
            dao_fund,
            deposit_fee,
            deposit_token,
            {"from": deployer_account},
            publish_source=publish_source,
        )
    snowusdclp_genesis_pool_contract = SnowSnowUsdcLpGenesisRewardPool[-1]
    return snowusdclp_genesis_pool_contract


### setup all contract


def setup_main_token():
    main_token = deploy_maintoken()
    main_token_contract = Contract(main_token.address)
    treasury_contract = deploy_treasury_contract()
    print("Maintoken setting treasury as operator...")
    set_operator_tx = main_token_contract.transferOperator(
        treasury_contract.address,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)
    print("Maintoken setting oracle...")
    oracle_contract = deploy_main_token_oracle_contract()
    set_oracle_tx = main_token_contract.setOracle(
        oracle_contract.address,
        {"from": deployer_account},
    )
    set_oracle_tx.wait(1)


def setup_bond_token():
    bond_token = deploy_bondtoken()
    bond_token_contract = Contract(bond_token.address)
    treasury_contract = deploy_treasury_contract()
    print("Bondtoken setting treasury as operator...")
    set_operator_tx = bond_token_contract.transferOperator(
        treasury_contract.address,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)


def setup_share_token():
    share_token = deploy_sharetoken()
    share_token_contract = Contract(share_token.address)
    treasury_contract = deploy_treasury_contract()
    print("Sharetoken setting treasury as operator...")
    set_operator_tx = share_token_contract.transferOperator(
        treasury_contract.address,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)


def setup_boardroom():
    main_token = deploy_maintoken()
    share_token = deploy_sharetoken()
    peg_token = deploy_maintoken()
    pay_token = get_peg_token()
    treasury = deploy_treasury_contract()
    boardroom = deploy_boardroom()
    share_token_contract = Contract(share_token.address)
    boardroom_contract = Contract(boardroom.address)
    print("Initializing boardroom...")
    boardroom_initialized_tx = boardroom_contract.initialize(
        main_token.address,
        share_token.address,
        treasury.address,
        {"from": deployer_account},
    )
    boardroom_initialized_tx.wait(1)
    # print("Setting Oracle...")
    # main_token_oracle = deploy_main_token_oracle_contract()
    # boardroom_token_config_tx = boardroom_contract.setPegTokenConfig(
    #     main_token.address,
    #     main_token_oracle.address,
    #     {"from": deployer_account},
    # )
    # boardroom_token_config_tx.wait(1)
    # print("adding peg tokens..")
    # boardroom_add_peg_token_tx = boardroom_contract.addPegToken(
    #     main_token.address,
    #     {"from": deployer_account},
    # )
    # boardroom_add_peg_token_tx.wait(1)
    print("Boardroom setting treasury as operator...")
    set_operator_tx = boardroom_contract.setOperator(
        treasury.address,
        {"from": deployer_account},
    )
    set_operator_tx.wait(1)
    approve_share_token_tx = share_token_contract.approve(
        boardroom.address, 10 * 10**18, {"from": dao_fund}
    )
    approve_share_token_tx.wait(1)
    stake_tx = boardroom_contract.stake(1 * 10**18, {"from": dao_fund})
    stake_tx.wait(1)


def setup_maintoken_oracle():
    main_token_oracle = deploy_main_token_oracle_contract()
    main_token_oracle_contract = Contract(main_token_oracle.address)
    print("Updating Oracle...")
    update_tx = main_token_oracle_contract.update({"from": deployer_account})
    update_tx.wait(1)


def setup_treasury():
    treasury = deploy_treasury_contract()
    main_token = deploy_maintoken()
    bond_token = deploy_bondtoken()
    share_token = deploy_sharetoken()
    main_token_oracle = deploy_main_token_oracle_contract()
    boardroom = deploy_boardroom()
    treasury_contract = Contract(treasury.address)
    print("Initializing treasury...")
    intialized_tx = treasury_contract.initialize(
        main_token.address,
        bond_token.address,
        share_token.address,
        main_token_oracle.address,
        boardroom.address,
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
    # allocate_seigniorage_tx = treasury_contract.allocateSeigniorage(
    #     {"from": deployer_account}
    # )
    # allocate_seigniorage_tx.wait(1)
    # set_boot_strap_tx = treasury_contract.setBootstrap(30, 400, {"from": deployer_account})
    # set_boot_strap_tx.wait(1)
    """
    (40,350) @ 24 epoch // @ 6 days
    (60,300) @ 40 epoch // @ 10 days
    (80,250) @ 56 epoch // @ 14 days
    (76,150) @ 64 epoch // @ 18 days
   
    """


def get_all_info():
    print(f"The active network is {network.show_active()}")
    print(f"peg token is {get_peg_token()}")
    print(f"main token is {deploy_maintoken()}")
    print(f"bond token is {deploy_bondtoken()}")
    print(f"share token is {deploy_sharetoken()}")
    print(f"boardroom contract is {deploy_boardroom()}")
    print(f"treasury contract is {deploy_treasury_contract()}")
    print(f"oracle contract is {deploy_main_token_oracle_contract()}")
    print(
        f"main token Liquidity Pool contract is {create_liquidity_pool(main_token_lp=True)}"
    )
    print(
        f"Share token Liquidity Pool contract is {create_liquidity_pool(share_token_lp=True)}"
    )
    print(f"Share token reward contract is {deploy_share_token_reward_pool()}")
    print(f"Main token node contract is {deploy_main_token_node()}")
    print(f"Share token node contract is {deploy_share_token_node()}")
    print(f"SNOW-USDC-LP genesis pool contract is {deploy_snowusdclp_genesis_pool()}")
    print(f"USDC genesis pool contract is {deploy_usdc_genesis_pool()}")
    print(f"CRO genesis pool contract is {deploy_cro_genesis_pool()}")
    print(f"USDT genesis pool contract is {deploy_usdt_genesis_pool()}")
    print(f"DAI genesis pool contract is {deploy_dai_genesis_pool()}")
    print(f"ETH genesis pool contract is {deploy_eth_genesis_pool()}")
    print(f"BTC genesis pool contract is {deploy_btc_genesis_pool()}")
    print(f"contract deployer account {deployer_account}")
    print(f"dao account {dao_fund}")
    print(f"devloper account {dev_fund}")
    print(f"airdrop account {airdrop_account}")


def main():
    # deploy_maintoken()
    # deploy_bondtoken()
    # deploy_sharetoken()
    # deploy_main_token_lp()
    # deploy_share_token_lp()
    # deploy_boardroom()
    # deploy_treasury_contract()
    # deploy_main_token_oracle_contract()
    deploy_share_token_reward_pool()
    deploy_main_token_node()
    deploy_share_token_node()
    deploy_usdc_genesis_pool()
    deploy_cro_genesis_pool()
    deploy_usdt_genesis_pool()
    deploy_dai_genesis_pool()
    deploy_eth_genesis_pool()
    deploy_btc_genesis_pool()
    deploy_snowusdclp_genesis_pool()
    setup_main_token()
    setup_maintoken_oracle()
    setup_bond_token()
    setup_share_token()
    setup_boardroom()
    setup_treasury()
    get_all_info()
