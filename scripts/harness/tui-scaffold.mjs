import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { localBunExecutable, repoRoot, tuiScaffoldPaths } from "./paths.mjs";

const root = repoRoot;
const snapshotPath = tuiScaffoldPaths.snapshot;
const generatedPath = tuiScaffoldPaths.generated;
const bunPath = localBunExecutable();
const preloadPath = tuiScaffoldPaths.sourcePreload;

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

rmSync(tuiScaffoldPaths.srcGenDir, { recursive: true, force: true });
rmSync(tuiScaffoldPaths.distDir, { recursive: true, force: true });
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
  console.error(`[tui-scaffold] Regenerate intentionally by updating the snapshot from ${path.relative(root, generatedPath)}`);
  process.exit(1);
}

run(bunPath, ["--preload", preloadPath, tuiScaffoldPaths.entryArg]);
