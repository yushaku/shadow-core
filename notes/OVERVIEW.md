# Top-Level Contracts

## folder

- folder `./contracts/CL` is the uniswap v3 code
- folder `./contracts/legacy` is the uniswap v2 + Solidly code

## Token Contracts

- `YSK.sol`:
  - Là `Emission Token` của protocol, dùng để incentive cho các `LP`
  - Có chức năng mint, burn, permit

- `xYSK.sol`:
  - Là `Staking Token`, dùng để stake YSK để được thưởng
  - User có thể vote để chuyển phần thưởng đến các `Pools` yêu thích của họ.
    Bằng cách staking, họ sẽ nhận được 100% protocol fees, incentive fee và tiền phạt từ việc users khác thoát lệnh.

![](https://docs.shadow.so/CL1.apng)

- `x33.sol`:
  - khi cầm `xYSK` thì user cần phải stake vào `VoteModule.sol` và hàng tuần phải tự vote vào `Gauge` để có thể nhận fees từ `Protocol`.
  - stake `xYSK` vào `x33` đơn giản hóa quy trình này bằng cách tự động hóa việc vote và claim reward.

## Manager Contracts

- `VoteModule.sol`:
  - phải stake `xYSK` vào `VoteModule` thì mới có `voting power`
