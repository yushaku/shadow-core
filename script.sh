#!/bin/bash

# networks: bsc_testnet, bsc, base_testnet, base
NETWORK=bsc_testnet
ACCOUNT=yushaku

# deploy shadow token

# forge script deploy/ysk.s.sol:DeployYSK \
#   --rpc-url $NETWORK \
#   --account $ACCOUNT \
#   --broadcast \
#   --verify

# echo "Deploying deployer..."
# forge script script/deployer.s.sol:Deployer \
#   --rpc-url $NETWORK \
#   --account $ACCOUNT \
#   --broadcast \
#   --verify

# forge script script/DeployYSK.s.sol:DeployYSK \
#    --rpc-url $NETWORK \
#    --account $ACCOUNT \
#    --broadcast \
#    --verify -vvvv

# forge script script/DeployCore.s.sol:DeployScript \
#    --rpc-url $NETWORK \
#    --account $ACCOUNT \
#    --broadcast \
#    --verify -vvvv

forge script script/DeployTokens.s.sol:DeployScript \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify -vvv

# forge script script/DeployLegacy.s.sol:DeployScript \
#    --rpc-url $NETWORK \
#    --account $ACCOUNT \
#    --broadcast \
#    --verify -vvv

# forge script script/DeployCL.s.sol:DeployScript \
#    --rpc-url $NETWORK \
#    --account $ACCOUNT \
#    --broadcast \
#    --verify -vvv

# forge verify-contract \
# --rpc-url $NETWORK \
# 0xf8f6fc3E749eD34916339c609934D203fB95CC54 \
# contracts/YSK.sol:YSK