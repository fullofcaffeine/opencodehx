import { cpSync, mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

const source = path.join(root, "fixtures/resources");
const targets = [path.join(root, "src-gen/resources"), path.join(root, "dist/resources")];

for (const target of targets) {
  rmSync(target, { recursive: true, force: true });
  cpSync(source, target, { recursive: true });
  const wasm = path.join(target, "wasm");
  mkdirSync(wasm, { recursive: true });
  cpSync(path.join(root, "node_modules/web-tree-sitter/tree-sitter.wasm"), path.join(wasm, "tree-sitter.wasm"));
  cpSync(path.join(root, "node_modules/tree-sitter-bash/tree-sitter-bash.wasm"), path.join(wasm, "tree-sitter-bash.wasm"));
  cpSync(
    path.join(root, "node_modules/tree-sitter-powershell/tree-sitter-powershell.wasm"),
    path.join(wasm, "tree-sitter-powershell.wasm"),
  );
}
