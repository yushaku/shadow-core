#!/bin/bash

# networks: bsc_testnet, bsc, base_testnet, base
NETWORK=bsc_testnet
ACCOUNT=yushaku

# deploy shadow token

forge script deploy/ysk.s.sol:DeployYSK \
  --rpc-url $NETWORK \
  --account $ACCOUNT \
  --broadcast \
  --verify

# forge verify-contract \
# --rpc-url $NETWORK \
# 0xf8f6fc3E749eD34916339c609934D203fB95CC54 \
# contracts/YSK.sol:YSK

# forge script deploy/permit2.s.sol:DeployPermit2Script \
# --rpc-url $NETWORK \
# --account $ACCOUNT \
# --broadcast \
# --verify

forge clone 0x74d416f40603a98da8c1592e0548e8b22f1b14f1 --chain 146 --etherscan-api-key sonic
