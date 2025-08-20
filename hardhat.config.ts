import type { HardhatUserConfig } from "hardhat/config";

const accounts = process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
	solidity: "0.8.26",
	networks: {
		hardhat: {
			allowUnlimitedContractSize: true,
		},
		bsc: {
			url: "https://bsc-dataseed.bnbchain.org",
			accounts,
		},
		bsc_testnet: {
			url: "https://bsc-testnet.bnbchain.org",
			accounts,
		},
		base: {
			url: "https://base.llamarpc.com",
			accounts,
		},
		base_testnet: {
			url: "https://base-goerli.llamarpc.com",
			accounts,
		},
	},
	paths: {
		cache: "cache/hardhat",
	},
};

export default config;
