#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

const OPT_IN_ENV = "OPENCODEHX_LIVE_PACKAGE_MANAGERS";
const TARGETS_ENV = "OPENCODEHX_LIVE_PACKAGE_MANAGERS_TARGETS";
const KEEP_ENV = "OPENCODEHX_LIVE_PACKAGE_MANAGERS_KEEP_TMP";
const PACKAGE = "is-number";
const OLD_VERSION = "6.0.0";
const NEW_VERSION = "7.0.0";
const ALL_TARGETS = ["npm", "pnpm", "bun", "brew", "choco", "scoop"];

if (process.env[OPT_IN_ENV] !== "1") {
	console.log(`[live-package-managers] skipped: set ${OPT_IN_ENV}=1 to run side-effecting package-manager checks`);
	process.exit(0);
}

const targets = parseTargets();
const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-live-pm-"));
const results = [];
let fatalError = null;

try {
	for (const target of targets) {
		switch (target) {
			case "npm":
				npmHarness(path.join(tempRoot, "npm"));
				break;
			case "pnpm":
				pnpmHarness(path.join(tempRoot, "pnpm"));
				break;
			case "bun":
				bunHarness(path.join(tempRoot, "bun"));
				break;
			case "brew":
				brewHarness();
				break;
			case "choco":
				chocoHarness();
				break;
			case "scoop":
				scoopHarness();
				break;
			default:
				throw new Error(`unknown package-manager target: ${target}`);
		}
	}
} catch (error) {
	fatalError = error;
} finally {
	if (process.env[KEEP_ENV] === "1") {
		console.log(`[live-package-managers] kept temp root: ${tempRoot}`);
	} else {
		rmSync(tempRoot, { recursive: true, force: true });
	}
}

for (const result of results) {
	console.log(`[live-package-managers] ${result.status}: ${result.target}${result.detail ? ` - ${result.detail}` : ""}`);
}

const failed = results.filter((result) => result.status === "failed");
if (fatalError != null) {
	console.error(`[live-package-managers] ERROR: ${fatalError.message}`);
}
if (failed.length > 0 || fatalError != null) {
	process.exitCode = 1;
}

function parseTargets() {
	const argTargets = process.argv.find((arg) => arg.startsWith("--targets="))?.slice("--targets=".length);
	const raw = argTargets ?? process.env[TARGETS_ENV] ?? "all";
	const parsed = raw === "all" ? ALL_TARGETS : raw.split(",").map((item) => item.trim()).filter(Boolean);
	for (const target of parsed) {
		if (!ALL_TARGETS.includes(target)) {
			throw new Error(`unknown target ${target}; expected one of ${ALL_TARGETS.join(", ")} or all`);
		}
	}
	return parsed;
}

function npmHarness(dir) {
	if (!hasCommand("npm", ["--version"])) {
		return skipped("npm", "npm command not found");
	}
	const prefix = path.join(dir, "prefix");
	const cache = path.join(dir, "cache");
	const env = sandboxEnv({ npm_config_cache: cache, NPM_CONFIG_CACHE: cache });
	runOk("npm", ["install", "-g", "--prefix", prefix, "--no-audit", "--no-fund", `${PACKAGE}@${OLD_VERSION}`], {
		env,
		timeout: 120_000,
		label: "npm install old package into temp prefix",
	});
	assert.equal(readPackageVersion(npmGlobalPackageRoot(prefix), PACKAGE), OLD_VERSION);
	runOk("npm", ["install", "-g", "--prefix", prefix, "--no-audit", "--no-fund", `${PACKAGE}@${NEW_VERSION}`], {
		env,
		timeout: 120_000,
		label: "npm upgrade package in temp prefix",
	});
	assert.equal(readPackageVersion(npmGlobalPackageRoot(prefix), PACKAGE), NEW_VERSION);
	runOk("npm", ["uninstall", "-g", "--prefix", prefix, PACKAGE], {
		env,
		timeout: 120_000,
		label: "npm uninstall package from temp prefix",
	});
	assert.equal(existsSync(path.join(npmGlobalPackageRoot(prefix), PACKAGE)), false);
	ok("npm", "install/upgrade/uninstall completed in temp prefix");
}

function pnpmHarness(dir) {
	if (!hasCommand("pnpm", ["--version"])) {
		return skipped("pnpm", "pnpm command not found");
	}
	const project = initProject(path.join(dir, "project"));
	const store = path.join(dir, "store");
	const env = sandboxEnv({ PNPM_HOME: path.join(dir, "home") });
	runOk("pnpm", ["add", "--ignore-scripts", "--store-dir", store, `${PACKAGE}@${OLD_VERSION}`], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "pnpm add old package in temp project",
	});
	assert.equal(readPackageVersion(path.join(project, "node_modules"), PACKAGE), OLD_VERSION);
	runOk("pnpm", ["add", "--ignore-scripts", "--store-dir", store, `${PACKAGE}@${NEW_VERSION}`], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "pnpm upgrade package in temp project",
	});
	assert.equal(readPackageVersion(path.join(project, "node_modules"), PACKAGE), NEW_VERSION);
	runOk("pnpm", ["remove", "--store-dir", store, PACKAGE], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "pnpm remove package from temp project",
	});
	assert.equal(existsSync(path.join(project, "node_modules", PACKAGE)), false);
	ok("pnpm", "add/upgrade/remove completed in temp project");
}

function bunHarness(dir) {
	const bun = localOrGlobalCommand("bun");
	if (!bun) {
		return skipped("bun", "bun command not found");
	}
	const project = initProject(path.join(dir, "project"));
	const cache = path.join(dir, "cache");
	const env = sandboxEnv({ BUN_INSTALL_CACHE_DIR: cache });
	runOk(bun, ["add", `${PACKAGE}@${OLD_VERSION}`], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "bun add old package in temp project",
	});
	assert.equal(readPackageVersion(path.join(project, "node_modules"), PACKAGE), OLD_VERSION);
	runOk(bun, ["add", `${PACKAGE}@${NEW_VERSION}`], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "bun upgrade package in temp project",
	});
	assert.equal(readPackageVersion(path.join(project, "node_modules"), PACKAGE), NEW_VERSION);
	runOk(bun, ["remove", PACKAGE], {
		cwd: project,
		env,
		timeout: 120_000,
		label: "bun remove package from temp project",
	});
	assert.equal(existsSync(path.join(project, "node_modules", PACKAGE)), false);
	ok("bun", "add/upgrade/remove completed in temp project");
}

function brewHarness() {
	if (!hasCommand("brew", ["--version"])) {
		return skipped("brew", "brew command not found");
	}
	const install = run("brew", ["install", "--dry-run", "opencode"], { timeout: 120_000 });
	if (install.status !== 0) {
		return skipped("brew", `install --dry-run unavailable: ${oneLine(install.stderr || install.stdout)}`);
	}
	const upgrade = run("brew", ["upgrade", "--dry-run", "opencode"], { timeout: 120_000 });
	const uninstall = run("brew", ["uninstall", "--dry-run", "opencode"], { timeout: 120_000 });
	const skippedSteps = [];
	if (upgrade.status !== 0)
		skippedSteps.push(`upgrade dry-run: ${oneLine(upgrade.stderr || upgrade.stdout)}`);
	if (uninstall.status !== 0)
		skippedSteps.push(`uninstall dry-run: ${oneLine(uninstall.stderr || uninstall.stdout)}`);
	ok("brew", skippedSteps.length === 0 ? "install/upgrade/uninstall dry-runs completed" : `install dry-run completed; ${skippedSteps.join("; ")}`);
}

function chocoHarness() {
	if (process.platform !== "win32") {
		return skipped("choco", "Chocolatey is Windows-only");
	}
	if (!hasCommand("choco", ["--version"])) {
		return skipped("choco", "choco command not found");
	}
	runOk("choco", ["install", "opencode", `--version=${OLD_VERSION}`, "-y", "--noop"], {
		timeout: 120_000,
		label: "choco install noop",
	});
	runOk("choco", ["upgrade", "opencode", `--version=${NEW_VERSION}`, "-y", "--noop"], {
		timeout: 120_000,
		label: "choco upgrade noop",
	});
	runOk("choco", ["uninstall", "opencode", "-y", "-r", "--noop"], {
		timeout: 120_000,
		label: "choco uninstall noop",
	});
	ok("choco", "install/upgrade/uninstall --noop completed");
}

function scoopHarness() {
	if (process.platform !== "win32") {
		return skipped("scoop", "Scoop is Windows-only");
	}
	if (!hasCommand("scoop", ["--version"])) {
		return skipped("scoop", "scoop command not found");
	}
	const info = run("scoop", ["info", "opencode"], { timeout: 60_000 });
	if (info.status !== 0) {
		return skipped("scoop", `read-only opencode probe failed: ${oneLine(info.stderr || info.stdout)}`);
	}
	skipped("scoop", "read-only probe passed; Scoop has no repo-approved disposable or dry-run install/remove path yet");
}

function npmGlobalPackageRoot(prefix) {
	return runOk("npm", ["root", "-g", "--prefix", prefix], { label: "npm root -g for temp prefix" }).stdout.trim();
}

function initProject(dir) {
	rmSync(dir, { recursive: true, force: true });
	writeFileSync(path.join(ensureDir(dir), "package.json"), `${JSON.stringify({ private: true }, null, 2)}\n`);
	return dir;
}

function ensureDir(dir) {
	rmSync(dir, { recursive: true, force: true });
	mkdirSync(dir, { recursive: true });
	return dir;
}

function readPackageVersion(parent, name) {
	const manifest = JSON.parse(readFileSync(path.join(parent, name, "package.json"), "utf8"));
	return manifest.version;
}

function sandboxEnv(extra = {}) {
	const home = path.join(tempRoot, "home");
	return {
		...process.env,
		HOME: home,
		USERPROFILE: home,
		npm_config_audit: "false",
		npm_config_fund: "false",
		npm_config_update_notifier: "false",
		...extra,
	};
}

function localOrGlobalCommand(name) {
	const local = path.join(root, "node_modules", ".bin", process.platform === "win32" ? `${name}.cmd` : name);
	if (existsSync(local))
		return local;
	return hasCommand(name, ["--version"]) ? name : null;
}

function hasCommand(command, args) {
	const result = run(command, args, { timeout: 30_000 });
	return !result.error && result.status === 0;
}

function runOk(command, args, options = {}) {
	const result = run(command, args, options);
	if (result.status !== 0 || result.error) {
		results.push({
			target: commandLabel(command),
			status: "failed",
			detail: `${options.label ?? `${command} ${args.join(" ")}`} failed: ${result.error?.message ?? oneLine(result.stderr || result.stdout)}`,
		});
		process.exitCode = 1;
		throw new Error(`${options.label ?? command} failed`);
	}
	return result;
}

function run(command, args, options = {}) {
	return spawnSync(command, args, {
		cwd: options.cwd ?? root,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: options.timeout ?? 60_000,
		shell: process.platform === "win32",
	});
}

function ok(target, detail) {
	results.push({ target, status: "ok", detail });
}

function skipped(target, detail) {
	results.push({ target, status: "skipped", detail });
}

function commandLabel(command) {
	return path.basename(command).replace(/\.cmd$/i, "");
}

function oneLine(text) {
	return text.trim().replace(/\s+/g, " ").slice(0, 240);
}
