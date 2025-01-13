import { Contract, Wallet } from "ethers";
import {
    IClPool,
    IClPool__factory,
} from "./../../../typechain-types";

export default function poolAtAddress(
    address: string,
    wallet: Wallet
): IClPool {
    return new Contract(
        address,
        IClPool__factory.abi,
        wallet
    ) as IClPool;
}
