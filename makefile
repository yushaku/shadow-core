install :
	@echo "Installing dependencies..."
	-forge install foundry-rs/forge-std
	-forge install transmissions11/solmate
	-forge install OpenZeppelin/openzeppelin-contracts
	-forge install OpenZeppelin/openzeppelin-contracts-upgradeable
	-forge install Uniswap/permit2
	@echo "Dependencies installed successfully!"
