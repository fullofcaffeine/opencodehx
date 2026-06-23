#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";

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
	assert.equal(fileNames.has("dist/resources/manifest.json"), true, "package includes runtime resource manifest");
	assert.equal(fileNames.has("dist/resources/smoke-resource.json"), true, "package includes copied runtime resource");
	assert.equal(fileNames.has("dist/resources/worker/parser-worker.mjs"), true, "package includes parser worker resource");
	assert.equal(fileNames.has("dist/resources/worker/tui-worker.mjs"), true, "package includes TUI worker resource");
	assert.equal(fileNames.has("src-gen/resources/manifest.json"), true, "package includes TypeScript-side resource manifest");
	assert.equal(fileNames.has("src-gen/index.ts"), true, "package includes generated TS source");
	for (const name of fileNames) {
		assert.equal(name.startsWith(".beads/"), false, `package should not include Beads metadata: ${name}`);
		assert.equal(name.startsWith("src/opencodehx/"), false, `package should not include Haxe source: ${name}`);
	}

	const prefix = path.join(tempRoot, "prefix");
	const tarball = path.join(tempRoot, packed.filename);
	expectOk(run("npm", ["install", "-g", "--prefix", prefix, tarball], { timeout: 180_000 }), "npm install -g");
	const globalRoot = expectOk(run("npm", ["root", "-g", "--prefix", prefix]), "npm root -g").stdout.trim();
	const installedRoot = path.join(globalRoot, packageJson.name);
	const manifest = JSON.parse(await readFile(path.join(installedRoot, "dist/resources/manifest.json"), "utf8"));
	assert.equal(manifest.version, 1, "installed manifest version");
	assert.equal(manifest.generatedBy, "scripts/build/copy-resources.mjs", "installed manifest generator");
	assert.equal(manifestEntry(manifest, "prompt/example.txt").kind, "text", "installed prompt manifest kind");
	assert.equal(manifestEntry(manifest, "smoke-resource.json").kind, "json", "installed json manifest kind");
	assert.equal(manifestEntry(manifest, "wasm/tree-sitter.wasm").kind, "wasm", "installed parser wasm manifest kind");
	assert.equal(manifestEntry(manifest, "worker/parser-worker.mjs").kind, "worker", "installed parser worker manifest kind");
	assert.equal(manifestEntry(manifest, "worker/tui-worker.mjs").kind, "worker", "installed tui worker manifest kind");
	const bin = path.join(prefix, "bin", "opencodehx");
	assert.equal(existsSync(bin), true, "global install exposes opencodehx bin");

	const version = expectOk(run(bin, ["--version"]), "installed version");
	assert.equal(version.stdout, `${packageJson.version}\n`);

	const help = expectOk(run(bin, ["--help"]), "installed help");
	assert.match(help.stdout, /providers\s+manage AI providers and credentials/);

	const runResult = expectOk(run(bin, ["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "package."]), "installed run");
	assert.equal(runResult.stdout, "Hello from the fake provider.\n");
	const projectDir = path.join(tempRoot, "workspace");
	mkdirSync(projectDir, { recursive: true });
	const runJson = expectOk(
		run(bin, [
			"run",
			"--format",
			"json",
			"--model",
			"openai/gpt-5.2",
			"--dir",
			projectDir,
			"Say",
			"hello",
			"from",
			"the",
			"installed",
			"workspace.",
		]),
		"installed run with dir",
	);
	assert.equal(assistantCwd(JSON.parse(runJson.stdout)), projectDir, "installed run assistant cwd");
	const mockJson = expectOk(
		run(bin, [
			"run",
			"--mock-ai-sdk",
			"--format",
			"json",
			"--dir",
			projectDir,
			"Say",
			"hello",
			"through",
			"the",
			"installed",
			"SDK.",
		]),
		"installed mock AI SDK run with dir",
	);
	const mockTranscript = JSON.parse(mockJson.stdout);
	assert.equal(mockTranscript.provider.id, "openai", "installed mock AI SDK provider");
	assert.equal(mockTranscript.events[0].type, "start", "installed mock AI SDK start event");
	assert.equal(assistantCwd(mockTranscript), projectDir, "installed mock AI SDK assistant cwd");

	const serveHelp = expectOk(run(bin, ["serve", "--help"]), "installed serve help");
	assert.match(serveHelp.stdout, /opencodehx serve/);
	assert.match(serveHelp.stdout, /--hostname <value>/);

	const serverEnv = {
		...process.env,
		XDG_DATA_HOME: path.join(tempRoot, "server-data"),
		XDG_CONFIG_HOME: path.join(tempRoot, "server-config"),
		OPENCODE_TEST_HOME: path.join(tempRoot, "server-home"),
	};
	const server = await startInstalledServer(bin, ["serve", "--hostname", "127.0.0.1", "--port", "0"], serverEnv);
	try {
		const health = await fetchJson(`${server.url}/health`);
		assert.equal(health.ok, true, "installed server health ok");
		assert.equal(health.service, "opencodehx", "installed server health service");
	} finally {
		await stopChild(server.child);
	}
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

function manifestEntry(manifest, resourcePath) {
	const entry = manifest.resources.find((item) => item.path === resourcePath);
	assert.ok(entry, `manifest includes ${resourcePath}`);
	assert.equal(entry.bytes > 0, true, `${resourcePath} has byte count`);
	assert.match(entry.sha256, /^[a-f0-9]{64}$/, `${resourcePath} has sha256`);
	return entry;
}

function assistantCwd(transcript) {
	return transcript.messages[1].info.path.cwd;
}

function startInstalledServer(bin, args, env) {
	return new Promise((resolve, reject) => {
		const child = spawn(bin, args, {
			cwd: root,
			env,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		let settled = false;
		const timeout = setTimeout(() => {
			if (settled) return;
			settled = true;
			child.kill("SIGTERM");
			reject(new Error(`installed serve did not become ready\nstdout:\n${stdout}\nstderr:\n${stderr}`));
		}, 30_000);
		child.stdout.setEncoding("utf8");
		child.stderr.setEncoding("utf8");
		child.stdout.on("data", (chunk) => {
			stdout += chunk;
			const match = stdout.match(/opencodehx server listening on (http:\/\/[^\s]+)/);
			if (!match || settled) return;
			settled = true;
			clearTimeout(timeout);
			resolve({ child, url: match[1] });
		});
		child.stderr.on("data", (chunk) => {
			stderr += chunk;
		});
		child.on("error", (error) => {
			if (settled) return;
			settled = true;
			clearTimeout(timeout);
			reject(error);
		});
		child.on("exit", (code, signal) => {
			if (settled) return;
			settled = true;
			clearTimeout(timeout);
			reject(new Error(`installed serve exited before ready: code=${code} signal=${signal}\nstdout:\n${stdout}\nstderr:\n${stderr}`));
		});
	});
}

async function fetchJson(url) {
	const deadline = Date.now() + 10_000;
	let lastError;
	while (Date.now() < deadline) {
		try {
			const response = await fetch(url);
			assert.equal(response.status, 200, `${url} status`);
			return await response.json();
		} catch (error) {
			lastError = error;
			await new Promise((resolve) => setTimeout(resolve, 100));
		}
	}
	throw lastError ?? new Error(`timed out fetching ${url}`);
}

function stopChild(child) {
	return new Promise((resolve, reject) => {
		const timeout = setTimeout(() => {
			child.kill("SIGKILL");
			reject(new Error("installed serve did not exit after SIGTERM"));
		}, 10_000);
		child.once("exit", () => {
			clearTimeout(timeout);
			resolve();
		});
		child.kill("SIGTERM");
	});
}

console.log("package-smoke:ok");
