import { rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

const profile = process.argv[2] ?? "all";
const directories = profile === "classic"
	? ["classic-dist"]
	: profile === "all"
		? ["src-gen", "dist", "classic-dist"]
		: (() => {
				throw new Error(`Unknown clean profile: ${profile}`);
			})();

for (const dir of directories) {
	rmSync(path.join(root, dir), { recursive: true, force: true });
}
