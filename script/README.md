# Deploy Conrtacts

Velodrome v2 deployment is a multi-step process. Unlike testing, we cannot impersonate governance to submit transactions and must wait on the necessary protocol actions to complete setup. This README goes through the necessary instructions to deploy the Velodrome v2 upgrade.

### Environment setup

1. Copy-pasta `.env.sample` into a new `.env` and set the environment variables.

2. store private key in keystore

Encrypting your Keys Using ERC2335

You will be asked for your `password`. You won't be able to deploy without your password.

To see all the configured wallets you can call the following: `cast wallet list`.

```sh
cast wallet import deployer_wallet --interactive

# output: `deployer_wallet` keystore was saved successfully.
#          Address: 0x9999999999999999999999999999999999999999
```

3. Run tests to ensure deployment state is configured correctly:

```sh
forge init
forge build
forge test
```

### Deployment

```sh
source .env

forge script script/DeployCore.s.sol:DeployCoreScript \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify -vvv

forge script script/DeployTokens.s.sol:DeployTokenScript \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify -vvv

forge script script/DeployLegacy.s.sol:DeployLegacy \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify -vvv

forge script script/DeployCL.s.sol:DeployCLScript \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify -vvv

forge script script/Setup.s.sol:SetupScript \
   --rpc-url $NETWORK \
   --account $ACCOUNT \
   --broadcast \
   --verify
```

### verify

- command above will verify the contracts when it is deployed
  but if error occurs, you can verify the contracts manually

```sh
source .env

forge verify-contract \
--rpc-url $NETWORK \
<contract_address> \
<contract_path>:<contract_name>
```
