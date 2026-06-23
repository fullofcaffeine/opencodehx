#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");
const packageJson = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));

function run(command, args, options = {}) {
	const result = spawnSync(command, args, {
		cwd: options.cwd ?? root,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: options.timeout ?? 60_000,
	});
	if (result.error) throw result.error;
	return result;
}

function expectOk(result, label) {
	assert.equal(result.status, 0, `${label} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
	return result;
}

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-package-"));
try {
	const pack = expectOk(run("npm", ["pack", "--pack-destination", tempRoot, "--json"], { timeout: 120_000 }), "npm pack");
	const packed = JSON.parse(pack.stdout)[0];
	const fileNames = new Set(packed.files.map((file) => file.path));
	assert.equal(packed.name, packageJson.name);
	assert.equal(packed.version, packageJson.version);
	assert.equal(fileNames.has("bin/opencodehx.mjs"), true, "package includes bin shim");
	assert.equal(fileNames.has("dist/index.js"), true, "package includes generated JS entrypoint");
	assert.equal(fileNames.has("dist/resources/smoke-resource.json"), true, "package includes copied runtime resource");
	assert.equal(fileNames.has("src-gen/index.ts"), true, "package includes generated TS source");
	for (const name of fileNames) {
		assert.equal(name.startsWith(".beads/"), false, `package should not include Beads metadata: ${name}`);
		assert.equal(name.startsWith("src/opencodehx/"), false, `package should not include Haxe source: ${name}`);
	}

	const prefix = path.join(tempRoot, "prefix");
	const tarball = path.join(tempRoot, packed.filename);
	expectOk(run("npm", ["install", "-g", "--prefix", prefix, tarball], { timeout: 180_000 }), "npm install -g");
	const bin = path.join(prefix, "bin", "opencodehx");
	assert.equal(existsSync(bin), true, "global install exposes opencodehx bin");

	const version = expectOk(run(bin, ["--version"]), "installed version");
	assert.equal(version.stdout, `${packageJson.version}\n`);

	const help = expectOk(run(bin, ["--help"]), "installed help");
	assert.match(help.stdout, /providers\s+manage AI providers and credentials/);

	const runResult = expectOk(run(bin, ["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "package."]), "installed run");
	assert.equal(runResult.stdout, "Hello from the fake provider.\n");

	const serveHelp = expectOk(run(bin, ["serve", "--help"]), "installed serve help");
	assert.match(serveHelp.stdout, /opencodehx serve/);
	assert.match(serveHelp.stdout, /--hostname <value>/);
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

console.log("package-smoke:ok");
