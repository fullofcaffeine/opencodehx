import { cpSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

const source = path.join(root, "fixtures/resources");
const target = path.join(root, "src-gen/resources");

rmSync(target, { recursive: true, force: true });
cpSync(source, target, { recursive: true });
