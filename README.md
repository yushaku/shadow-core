# shadow-core

Core smart contract repository for Shadow Exchange

## Documentation & Resources

- [Contract Addresses](https://docs.shadow.so/pages/contract-addresses)
- [Security Audits](https://docs.shadow.so/pages/audits)
- [Documentation](https://docs.shadow.so/)
- [License (BUSL-1.1)](https://docs.shadow.so/pages/BUSL)

## Architecture

![Architecture](https://github.com/user-attachments/assets/c3871a65-7d2e-4b00-97dc-a2bc42477dc7)

Shadow is built on Ramses V3 Core, which is based on Uniswap V3, with several enhancements. These improvements include [dynamic system and protocol fee mechanisms](/pages/x-33#fees), [FeeShare™](/pages/x-33#fee-share), and [x(3,3)](/pages/x-33). Ramses V3 Core also introduces a new accounting system to track how much active liquidity each concentrated liquidity position provides. 

## Security

The protocol has undergone multiple security reviews:

- Spearbit Audit [Report](https://cantina.xyz/portfolio/98695d75-ee7d-4e1c-aa96-6379f73c5b2c)
- Consensys Diligence Audit [Report](https://diligence.consensys.io/audits/2024/08/ramses-v3)
- Code4rena Contest [Report](https://code4rena.com/reports/2024-10-ramses-exchange)
- Additional specialized testing by 100Proof, Zenith Mitigation, and yAudit

## Protected Contracts

The following contracts are protected under BUSL-1.1 license:
- Voter.sol
- GaugeV3.sol  
- FeeDistributor.sol
