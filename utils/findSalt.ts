import { getCreate2Address, keccak256, numberToHex } from "viem";
import fs from "fs";
import path from "path";

// ================== config ==================
const DEPLOYER_ADDRESS = process.env.DEPLOYER_ADDRESS as `0x${string}`;
const TARGET_SUFFIX = "99999";
const ARTIFACT_PATH = "./out/YSK.sol/YSK.json";
// ==============================================

async function findSaltForSuffix() {
	console.log("--- start finding salt ---");

	let initCode: any;
	try {
		const artifact = JSON.parse(fs.readFileSync(path.resolve(ARTIFACT_PATH), "utf-8"));
		initCode = artifact.bytecode.object;
		if (!initCode || !initCode.startsWith("0x")) {
			throw new Error("Bytecode is invalid in artifact file.");
		}
	} catch (e) {
		console.error(`❌ Error: Cannot read artifact file at ${ARTIFACT_PATH}.`);
		return;
	}

	const bytecodeHash = keccak256(initCode);
	const targetSuffixLower = TARGET_SUFFIX.toLowerCase();

	console.log(`Deployer: ${DEPLOYER_ADDRESS}`);
	console.log(`Target suffix: ${TARGET_SUFFIX}`);
	console.log(`Bytecode hash: ${bytecodeHash}`);
	console.log("-----------------------------------");

	let saltNonce = 0n;
	const startTime = Date.now();

	while (true) {
		const salt = numberToHex(saltNonce, { size: 32 });

		const computedAddress = getCreate2Address({
			from: DEPLOYER_ADDRESS,
			salt,
			bytecodeHash,
		});

		if (computedAddress.toLowerCase().endsWith(targetSuffixLower)) {
			const duration = (Date.now() - startTime) / 1000;
			console.log("\n✅ Found salt!");
			console.log(`   -> Time taken: ${duration.toFixed(2)} seconds`);
			console.log(`   -> Number of attempts: ${saltNonce.toLocaleString()}`);
			console.log(`   -> Salt (hex): ${salt}`);
			console.log(`   -> Deployed address: ${computedAddress}`);
			break;
		}

		if (saltNonce > 0n && saltNonce % 2000000n === 0n) {
			console.log(`   -> Tried ${saltNonce.toLocaleString()} salts...`);
		}

		saltNonce++;
	}
}

findSaltForSuffix();
