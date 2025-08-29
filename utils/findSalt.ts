import { getCreate2Address, encodeDeployData, keccak256, numberToHex, Address, zeroAddress } from "viem";
import fs from "fs";
import path from "path";

export const _getAddress = (key: string, network: string = "97") => {
	const rawData = fs.readFileSync(`./deploy-addresses/${network}.json`);
	const object = JSON.parse(rawData.toString());
	return object[key];
};

async function _getArtifact(conractPath: string) {
	try {
		const artifact = JSON.parse(fs.readFileSync(path.resolve(conractPath), "utf-8"));
		const initCode = artifact.bytecode.object;
		const abi = artifact.abi;

		if (!initCode || !initCode.startsWith("0x")) {
			throw new Error("Bytecode is invalid in artifact file.");
		}

		return {
			initCode,
			abi,
		};
	} catch (e) {
		throw new Error(`Error: Cannot read artifact file at ${conractPath}.`);
	}
}

async function _findSalt(data: { path: string; suffix: string; deployer: Address; params: any[] }) {
	console.log("--- start finding salt ---");
	console.log("data", data);
	const { initCode, abi } = await _getArtifact(data.path);

	const initCodeWithParams = encodeDeployData({
		abi: abi,
		bytecode: initCode,
		args: data.params,
	});

	const bytecodeHash = keccak256(initCodeWithParams);

	let saltNonce = 0n;
	while (true) {
		const salt = numberToHex(saltNonce, { size: 32 });

		const computedAddress = getCreate2Address({
			from: data.deployer,
			salt,
			bytecodeHash,
		});

		const name = path.basename(data.path, ".json");

		if (computedAddress.toLowerCase().endsWith(data.suffix)) {
			console.log(`-> Salt (hex): ${salt}`);
			console.log(`-> Deployed ${name}: ${computedAddress}`);

			return {
				salt,
				address: computedAddress,
			};
		}

		if (saltNonce > 0n && saltNonce % 2000000n === 0n) {
			console.log(`-> Tried ${saltNonce.toLocaleString()} salts...`);
		}

		saltNonce++;
	}
}

async function findSaltForSuffix() {
	const accessHub = _getAddress("AccessHub");
	const minter = _getAddress("Minter");
	const voter = _getAddress("Voter");
	const voteModule = _getAddress("VoteModule");
	const operator = "0xd23714A6662eA86271765acF906AECA80EF7d6Fa";
	const deployer = "0x9ffcce02ad14c18a8c4f688485967d6b4c261cd9";

	const ysk = {
		path: "./out/YSK.sol/YSK.json",
		suffix: "88888",
		deployer,
		params: [minter],
	}
	// -> Salt (hex): 0x000000000000000000000000000000000000000000000000000000000011cee8
	// -> ysk address: 0x2cE2C159a110b4E783a9681059d34afC20A88888
	const xysk = {
		path: "./out/XYSK.sol/XYSK.json",
		suffix: "66666",
		deployer,
		params: [
			zeroAddress,
			voter,
			operator,
			accessHub,
			voteModule,
			minter,
		],
	}
	// -> Salt (hex): 0x0000000000000000000000000000000000000000000000000000000000034e87
	// -> XYSK address: 0x21A8ea225CB58906B7c9e20781C96c1348F66666
	const x33 = {
		path: "./out/x33.sol/x33.json",
		suffix: "99999",
		deployer,
		params: [
			operator,
			accessHub,
			zeroAddress,
			voter,
			voteModule,
		],
		// -> Salt (hex): 0x0000000000000000000000000000000000000000000000000000000000024cb8
		// -> Deployed address: 0x5a53D228ce7677fabc7c4E88d837023aD4899999
	}

	const { address: yskAddress } = await _findSalt(ysk as any);

	xysk.params[0] = yskAddress;
	const { address: xyskAddress } = await _findSalt(xysk as any);

	x33.params[2] = xyskAddress;
	await _findSalt(x33 as any);
}

findSaltForSuffix();

