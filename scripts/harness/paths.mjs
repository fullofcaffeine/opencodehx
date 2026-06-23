import path from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));

export function rootPath(...segments) {
	return path.join(repoRoot, ...segments);
}

export function rootPathFromPackageMember(member) {
	return rootPath(...member.split("/"));
}

export const packageMembers = Object.freeze({
	bin: "bin/opencodehx.mjs",
	tuiPreload: "bin/opencodehx-opentui-solid-preload.mjs",
	distIndex: "dist/index.js",
	runtimeResourceManifest: "dist/resources/manifest.json",
	runtimeSmokeResource: "dist/resources/smoke-resource.json",
	parserWorker: "dist/resources/worker/parser-worker.mjs",
	tuiWorker: "dist/resources/worker/tui-worker.mjs",
	tsResourceManifest: "src-gen/resources/manifest.json",
	tsIndex: "src-gen/index.ts",
	tuiIndex: "src-gen/tui/index.tsx",
	tuiScaffold: "src-gen/tui/opencodehx/tui/TuiScaffold.tsx",
});

export const packageForbiddenPrefixes = Object.freeze([".beads/", "src/opencodehx/"]);

export const resourcePaths = Object.freeze({
	sourceDir: rootPath("fixtures", "resources"),
	srcGenDir: rootPath("src-gen", "resources"),
	distDir: rootPath("dist", "resources"),
	manifest: "manifest.json",
	generator: "scripts/build/copy-resources.mjs",
	promptExample: "prompt/example.txt",
	smokeResource: "smoke-resource.json",
	treeSitterWasm: "wasm/tree-sitter.wasm",
	parserWorker: "worker/parser-worker.mjs",
	tuiWorker: "worker/tui-worker.mjs",
});

export const nodeModuleResources = Object.freeze({
	treeSitterWasm: rootPath("node_modules", "web-tree-sitter", "tree-sitter.wasm"),
	treeSitterBashWasm: rootPath("node_modules", "tree-sitter-bash", "tree-sitter-bash.wasm"),
	treeSitterPowershellWasm: rootPath("node_modules", "tree-sitter-powershell", "tree-sitter-powershell.wasm"),
});

export const tuiScaffoldPaths = Object.freeze({
	snapshot: rootPath("reference", "tui-scaffold.TuiScaffold.tsx"),
	generated: rootPathFromPackageMember(packageMembers.tuiScaffold),
	srcGenDir: rootPath("src-gen", "tui"),
	distDir: rootPath("dist-tui"),
	sourcePreload: rootPath("scripts", "harness", "opentui-solid-preload.mjs"),
	entryArg: `./${packageMembers.tuiIndex}`,
});

export const generatedModules = Object.freeze({
	eventBus: "dist/opencodehx/bus/EventBus.js",
	fileWatcherRuntime: "dist/opencodehx/file/FileWatcherRuntime.js",
	vcsRuntime: "dist/opencodehx/project/VcsRuntime.js",
	nodeProcess: "dist/opencodehx/host/node/NodeProcess.js",
	ptyService: "dist/opencodehx/pty/PtyService.js",
});

export const distIndexArgs = Object.freeze([packageMembers.distIndex]);

export function localBin(name) {
	const extension = process.platform === "win32" ? ".cmd" : "";
	return rootPath("node_modules", ".bin", `${name}${extension}`);
}

export function localBunExecutable() {
	return rootPath("node_modules", ".bin", process.platform === "win32" ? "bun.exe" : "bun");
}
