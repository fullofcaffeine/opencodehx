import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

function run(command, args) {
	const result = spawnSync(command, args, {
		cwd: root,
		stdio: "inherit",
		env: process.env,
	});
	if (result.error) throw result.error;
	if (result.status !== 0) {
		process.exit(result.status ?? 1);
	}
}

const generatedRoot = path.join(root, "test/generated");

rmSync(generatedRoot, { recursive: true, force: true });
run("haxe", ["hxml/opencodehx.tests.bun.genes-ts.hxml"]);
mkdirSync(path.join(generatedRoot, "unit"), { recursive: true });
writeFileSync(path.join(generatedRoot, "unit/format.generated.test.ts"), 'import "./index.js";\n');
run("tsc", ["-p", "tsconfig.test.json"]);
run("bun", ["test", "test/generated/unit/format.generated.test.ts"]);
