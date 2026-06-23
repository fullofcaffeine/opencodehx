import { createHash } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { nodeModuleResources, resourcePaths } from "../harness/paths.mjs";

const source = resourcePaths.sourceDir;
const targets = [resourcePaths.srcGenDir, resourcePaths.distDir];

for (const target of targets) {
  rmSync(target, { recursive: true, force: true });
  cpSync(source, target, { recursive: true });
  const wasm = path.join(target, "wasm");
  mkdirSync(wasm, { recursive: true });
  cpSync(nodeModuleResources.treeSitterWasm, path.join(wasm, "tree-sitter.wasm"));
  cpSync(nodeModuleResources.treeSitterBashWasm, path.join(wasm, "tree-sitter-bash.wasm"));
  cpSync(nodeModuleResources.treeSitterPowershellWasm, path.join(wasm, "tree-sitter-powershell.wasm"));
  writeManifest(target);
}

function writeManifest(target) {
  const resources = listFiles(target)
    .filter((resourcePath) => resourcePath !== "manifest.json")
    .map((resourcePath) => {
      const absolute = path.join(target, resourcePath);
      const bytes = readFileSync(absolute);
      return {
        path: resourcePath,
        kind: resourceKind(resourcePath),
        bytes: bytes.byteLength,
        sha256: createHash("sha256").update(bytes).digest("hex"),
      };
    });
  const manifest = {
    version: 1,
    generatedBy: resourcePaths.generator,
    resources,
  };
  writeFileSync(path.join(target, resourcePaths.manifest), `${JSON.stringify(manifest, null, 2)}\n`);
}

function listFiles(rootDir, relativeDir = "") {
  const dir = path.join(rootDir, relativeDir);
  const result = [];
  for (const name of readdirSync(dir).sort()) {
    const relative = relativeDir === "" ? name : `${relativeDir}/${name}`;
    const absolute = path.join(rootDir, relative);
    if (statSync(absolute).isDirectory()) {
      result.push(...listFiles(rootDir, relative));
    } else {
      result.push(relative);
    }
  }
  return result;
}

function resourceKind(resourcePath) {
  if (resourcePath.startsWith("worker/")) return "worker";
  if (resourcePath.startsWith("prompt/")) return "text";
  const ext = path.extname(resourcePath);
  if (ext === ".json") return "json";
  if (ext === ".wasm") return "wasm";
  if (ext === ".txt" || ext === ".md") return "text";
  return "file";
}
