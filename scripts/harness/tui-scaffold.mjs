import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(new URL("../..", import.meta.url).pathname);
const snapshotPath = path.join(root, "reference", "tui-scaffold.TuiScaffold.tsx");
const generatedPath = path.join(root, "src-gen", "tui", "opencodehx", "tui", "TuiScaffold.tsx");
const bunPath = path.join(root, "node_modules", ".bin", process.platform === "win32" ? "bun.exe" : "bun");
const preloadPath = path.join(root, "scripts", "harness", "opentui-solid-preload.mjs");

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    env: process.env,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

rmSync(path.join(root, "src-gen", "tui"), { recursive: true, force: true });
rmSync(path.join(root, "dist-tui"), { recursive: true, force: true });
run("haxe", ["hxml/opencodehx.tui.genes-ts.hxml"]);
run("tsc", ["-p", "tsconfig.tui.json"]);

const generated = readFileSync(generatedPath, "utf8");
if (!existsSync(snapshotPath)) {
  mkdirSync(path.dirname(snapshotPath), { recursive: true });
  writeFileSync(snapshotPath, generated);
  console.error(`[tui-scaffold] Created missing snapshot: ${path.relative(root, snapshotPath)}`);
  process.exit(1);
}

const expected = readFileSync(snapshotPath, "utf8");
if (generated !== expected) {
  console.error("[tui-scaffold] Generated TSX differs from reference/tui-scaffold.TuiScaffold.tsx");
  console.error("[tui-scaffold] Regenerate intentionally by updating the snapshot from src-gen/tui/opencodehx/tui/TuiScaffold.tsx");
  process.exit(1);
}

run(bunPath, ["--preload", preloadPath, "./src-gen/tui/index.tsx"]);
