from brownie import *
from config import (
    BADGER_DEV_MULTISIG,
    WANT,
    LP_COMPONENT,
    REWARD_TOKEN,
    PROTECTED_TOKENS,
    FEES
)
from dotmap import DotMap


def main():
    return deploy()


def deploy():
    """
      Deploys, vault, controller and strats and wires them up for you to test
    """
    deployer = accounts[0]

    strategist = deployer
    keeper = deployer
    guardian = deployer

    governance = accounts.at(BADGER_DEV_MULTISIG, force=True)

    controller = Controller.deploy({"from": deployer})
    controller.initialize(
        BADGER_DEV_MULTISIG,
        strategist,
        keeper,
        BADGER_DEV_MULTISIG
    )

    sett = SettV3.deploy({"from": deployer})
    sett.initialize(
        WANT,
        controller,
        BADGER_DEV_MULTISIG,
        keeper,
        guardian,
        False,
        "prefix",
        "PREFIX"
    )

    sett.unpause({"from": governance})
    controller.setVault(WANT, sett)

    # TODO: Add guest list once we find compatible, tested, contract
    # guestList = VipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
    # guestList.initialize(sett, {"from": deployer})
    # guestList.setGuests([deployer], [True])
    # guestList.setUserDepositCap(100000000)
    # sett.setGuestList(guestList, {"from": governance})

    #  Start up Strategy
    strategy = MyStrategy.deploy({"from": deployer})
    strategy.initialize(
        BADGER_DEV_MULTISIG,
        strategist,
        controller,
        keeper,
        guardian,
        PROTECTED_TOKENS,
        FEES
    )

    # Tool that verifies bytecode (run independetly) <- Webapp for anyone to verify

    # Set up tokens
    want = interface.IERC20(WANT)

    rewardToken = interface.IERC20(REWARD_TOKEN)

    #  Wire up Controller to Strategy
    controller.approveStrategy(WANT, strategy, {"from": governance})
    controller.setStrategy(WANT, strategy, {"from": deployer})

    # Quickswap some tokens here
    router = interface.IUniswapRouterV2(
        "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff")

    WBTC = "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6"
    wbtc = interface.IERC20(WBTC)
    
    wbtc.approve("0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
                 999999999999999999999999999999, {"from": deployer})

    # Buy WBTC with path MATIC -> WETH -> WBTC
    router.swapExactETHForTokens(
        0,
        ["0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
            "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619", WBTC],
        deployer,
        9999999999999999,
        {"from": deployer, "value": 5000 * 10**18}
    )

    # CURVE_RENBTC_POOL
    pool = interface.ICurveStableSwapREN("0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67")
    wbtc.approve("0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67",
                 999999999999999999999999999999, {"from": deployer})

    # Add liquidity for wBTC-renBTC pool
    pool.add_liquidity(
        [wbtc.balanceOf(deployer), 0],
        0,
        True,
        {"from": deployer}
    )


    return DotMap(
        deployer=deployer,
        controller=controller,
        vault=sett,
        sett=sett,
        strategy=strategy,
        # guestList=guestList,
        want=want,
        rewardToken=rewardToken
    )
