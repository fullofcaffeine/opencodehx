import { rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

for (const dir of ["src-gen", "dist"]) {
	rmSync(path.join(root, dir), { recursive: true, force: true });
}
