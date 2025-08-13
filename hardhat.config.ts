import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import type { HardhatUserConfig } from "hardhat/config";

const accounts = process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
  solidity: "0.8.28",
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
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  sourcify: {
    enabled: true,
  },
  gasReporter: {
    enabled: false,
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: true,
    coinmarketcap: "",
  },
  namedAccounts: {
    deployer: { default: 0 },
  },
  paths: {
    cache: 'cache/hardhat',
  },
};

export default config;
