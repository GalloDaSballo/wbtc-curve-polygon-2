# Ideally, they have one file with the settings for the strat and deployment
# This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0xb65cef03b9b89f99517643226d76e286ee999e77"

# For the Polygon Mainnet
WANT = "0xf8a57c1d3b9629b77b6726a042ca48990A84Fb49" ## Curve.fi amWBTC/renBTC (btcCRV)
LP_COMPONENT = "0xffbACcE0CC7C19d46132f1258FC16CF6871D153c" ## this is pool & deposit token
REWARD_TOKEN = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270" ## WMATIC
# REWARD_TOKEN = "0x172370d5cd63279efa6d502dab29171933a610af" ## CRV

PROTECTED_TOKENS = [WANT, LP_COMPONENT, REWARD_TOKEN]

## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 75

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]