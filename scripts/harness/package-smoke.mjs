#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { WebSocket } from "ws";
import { packageForbiddenPrefixes, packageMembers, repoRoot, resourcePaths } from "./paths.mjs";

const root = repoRoot;
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

function runAsync(command, args, options = {}) {
	return new Promise((resolve, reject) => {
		const child = spawn(command, args, {
			cwd: options.cwd ?? root,
			env: options.env ?? process.env,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		const timeout = setTimeout(() => {
			child.kill("SIGTERM");
			reject(new Error(`Timed out running ${command} ${args.join(" ")}`));
		}, options.timeout ?? 60_000);
		child.stdout.setEncoding("utf8");
		child.stderr.setEncoding("utf8");
		child.stdout.on("data", (chunk) => {
			stdout += chunk;
		});
		child.stderr.on("data", (chunk) => {
			stderr += chunk;
		});
		child.once("error", (error) => {
			clearTimeout(timeout);
			reject(error);
		});
		child.once("close", (status) => {
			clearTimeout(timeout);
			resolve({ status, stdout, stderr });
		});
	});
}

function expectOk(result, label) {
	assert.equal(result.status, 0, `${label} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
	return result;
}

async function expectOkAsync(resultPromise, label) {
	return expectOk(await resultPromise, label);
}

async function withLiveOpenAICompatibleServer(fn) {
	const observed = { auth: null, body: null, path: null };
	const server = createServer((req, res) => {
		observed.auth = req.headers.authorization ?? null;
		observed.path = req.url;
		let body = "";
		req.setEncoding("utf8");
		req.on("data", (chunk) => {
			body += chunk;
		});
		req.on("end", () => {
			observed.body = body ? JSON.parse(body) : null;
			if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
				res.writeHead(404);
				res.end();
				return;
			}
			res.writeHead(200, { "content-type": "text/event-stream" });
			res.end(
				[
					{
						id: "chatcmpl-installed-live",
						created: 1,
						model: "chat",
						choices: [{ delta: { role: "assistant", content: "Hello " } }],
					},
					{
						id: "chatcmpl-installed-live",
						created: 1,
						model: "chat",
						choices: [{ delta: { content: "from installed live." } }],
					},
					{
						id: "chatcmpl-installed-live",
						created: 1,
						model: "chat",
						choices: [{ delta: {}, finish_reason: "stop" }],
						usage: { prompt_tokens: 7, completion_tokens: 4, total_tokens: 11 },
					},
				]
					.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`)
					.join("") + "data: [DONE]\n\n",
			);
		});
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			server.off("error", reject);
			resolve();
		});
	});
	const address = server.address();
	const baseUrl = `http://127.0.0.1:${address.port}`;
	try {
		return await fn(baseUrl, observed);
	} finally {
		await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
	}
}

async function withToolOpenAICompatibleServer(toolSpec, fn) {
	const observed = { auth: null, bodies: [], paths: [] };
	const server = createServer((req, res) => {
		observed.auth = req.headers.authorization ?? null;
		observed.paths.push(req.url);
		let body = "";
		req.setEncoding("utf8");
		req.on("data", (chunk) => {
			body += chunk;
		});
		req.on("end", () => {
			observed.bodies.push(body ? JSON.parse(body) : null);
			if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
				res.writeHead(404);
				res.end();
				return;
			}
			const firstCall = observed.bodies.length === 1;
			res.writeHead(200, { "content-type": "text/event-stream" });
			const chunks = firstCall
				? [
						{
							id: "chatcmpl-installed-tool",
							created: 1,
							model: "chat",
							choices: [
								{
									delta: {
										role: "assistant",
										tool_calls: [
											{
												index: 0,
												id: toolSpec.callId,
												type: "function",
												function: { name: toolSpec.tool, arguments: JSON.stringify(toolSpec.arguments) },
											},
										],
									},
									finish_reason: "tool_calls",
								},
							],
						},
					]
				: [
						{
							id: "chatcmpl-installed-tool",
							created: 1,
							model: "chat",
							choices: [{ delta: { role: "assistant", content: toolSpec.finalText } }],
						},
						{
							id: "chatcmpl-installed-tool",
							created: 1,
							model: "chat",
							choices: [{ delta: {}, finish_reason: "stop" }],
							usage: toolSpec.usage,
						},
					];
			res.end(chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") + "data: [DONE]\n\n");
		});
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			server.off("error", reject);
			resolve();
		});
	});
	const address = server.address();
	const baseUrl = `http://127.0.0.1:${address.port}`;
	try {
		return await fn(baseUrl, observed);
	} finally {
		await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
	}
}

async function withToolChainOpenAICompatibleServer(chainSpec, fn) {
	const observed = { auth: null, bodies: [], paths: [] };
	const server = createServer((req, res) => {
		observed.auth = req.headers.authorization ?? null;
		observed.paths.push(req.url);
		let body = "";
		req.setEncoding("utf8");
		req.on("data", (chunk) => {
			body += chunk;
		});
		req.on("end", () => {
			observed.bodies.push(body ? JSON.parse(body) : null);
			if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
				res.writeHead(404);
				res.end();
				return;
			}
			const requestIndex = observed.bodies.length - 1;
			const step = chainSpec.steps[requestIndex];
			res.writeHead(200, { "content-type": "text/event-stream" });
			const chunks = step
				? [
						{
							id: "chatcmpl-installed-chain",
							created: 1,
							model: "chat",
							choices: [
								{
									delta: {
										role: "assistant",
										tool_calls: [
											{
												index: 0,
												id: step.callId,
												type: "function",
												function: { name: step.tool, arguments: JSON.stringify(step.arguments) },
											},
										],
									},
									finish_reason: "tool_calls",
								},
							],
						},
					]
				: [
						{
							id: "chatcmpl-installed-chain",
							created: 1,
							model: "chat",
							choices: [{ delta: { role: "assistant", content: chainSpec.finalText } }],
						},
						{
							id: "chatcmpl-installed-chain",
							created: 1,
							model: "chat",
							choices: [{ delta: {}, finish_reason: "stop" }],
							usage: chainSpec.usage,
						},
					];
			res.end(chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") + "data: [DONE]\n\n");
		});
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			server.off("error", reject);
			resolve();
		});
	});
	const address = server.address();
	const baseUrl = `http://127.0.0.1:${address.port}`;
	try {
		return await fn(baseUrl, observed);
	} finally {
		await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
	}
}

async function withFailingOpenAICompatibleServer(fn) {
	const observed = { auth: null, body: null, path: null };
	const server = createServer((req, res) => {
		observed.auth = req.headers.authorization ?? null;
		observed.path = req.url;
		let body = "";
		req.setEncoding("utf8");
		req.on("data", (chunk) => {
			body += chunk;
		});
		req.on("end", () => {
			observed.body = body ? JSON.parse(body) : null;
			if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
				res.writeHead(404);
				res.end();
				return;
			}
			res.writeHead(500, { "content-type": "application/json" });
			res.end(JSON.stringify({ error: { message: "installed live failure" } }));
		});
	});
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			server.off("error", reject);
			resolve();
		});
	});
	const address = server.address();
	const baseUrl = `http://127.0.0.1:${address.port}`;
	try {
		return await fn(baseUrl, observed);
	} finally {
		await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
	}
}

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-package-"));
try {
	const pack = expectOk(run("npm", ["pack", "--pack-destination", tempRoot, "--json"], { timeout: 120_000 }), "npm pack");
	const packed = JSON.parse(pack.stdout)[0];
	const fileNames = new Set(packed.files.map((file) => file.path));
	assert.equal(packed.name, packageJson.name);
	assert.equal(packed.version, packageJson.version);
	assert.equal(fileNames.has(packageMembers.bin), true, "package includes bin shim");
	assert.equal(fileNames.has(packageMembers.tuiPreload), true, "package includes TUI preload");
	assert.equal(fileNames.has(packageMembers.distIndex), true, "package includes generated JS entrypoint");
	assert.equal(fileNames.has(packageMembers.runtimeResourceManifest), true, "package includes runtime resource manifest");
	assert.equal(fileNames.has(packageMembers.runtimeSmokeResource), true, "package includes copied runtime resource");
	assert.equal(fileNames.has(packageMembers.parserWorker), true, "package includes parser worker resource");
	assert.equal(fileNames.has(packageMembers.tuiWorker), true, "package includes TUI worker resource");
	assert.equal(fileNames.has(packageMembers.tsResourceManifest), true, "package includes TypeScript-side resource manifest");
	assert.equal(fileNames.has(packageMembers.tsIndex), true, "package includes generated TS source");
	assert.equal(fileNames.has(packageMembers.tuiIndex), true, "package includes generated TUI TSX entrypoint");
	assert.equal(fileNames.has(packageMembers.tuiScaffold), true, "package includes generated TUI scaffold TSX");
	for (const name of fileNames) {
		for (const prefix of packageForbiddenPrefixes) {
			assert.equal(name.startsWith(prefix), false, `package should not include ${prefix} files: ${name}`);
		}
	}

	const prefix = path.join(tempRoot, "prefix");
	const tarball = path.join(tempRoot, packed.filename);
	expectOk(run("npm", ["install", "-g", "--prefix", prefix, tarball], { timeout: 180_000 }), "npm install -g");
	const globalRoot = expectOk(run("npm", ["root", "-g", "--prefix", prefix]), "npm root -g").stdout.trim();
	const installedRoot = path.join(globalRoot, packageJson.name);
	const manifest = JSON.parse(await readFile(path.join(installedRoot, packageMembers.runtimeResourceManifest), "utf8"));
	assert.equal(manifest.version, 1, "installed manifest version");
	assert.equal(manifest.generatedBy, resourcePaths.generator, "installed manifest generator");
	assert.equal(manifestEntry(manifest, resourcePaths.promptExample).kind, "text", "installed prompt manifest kind");
	assert.equal(manifestEntry(manifest, resourcePaths.smokeResource).kind, "json", "installed json manifest kind");
	assert.equal(manifestEntry(manifest, resourcePaths.treeSitterWasm).kind, "wasm", "installed parser wasm manifest kind");
	assert.equal(manifestEntry(manifest, resourcePaths.parserWorker).kind, "worker", "installed parser worker manifest kind");
	assert.equal(manifestEntry(manifest, resourcePaths.tuiWorker).kind, "worker", "installed tui worker manifest kind");
	const bin = path.join(prefix, "bin", "opencodehx");
	assert.equal(existsSync(bin), true, "global install exposes opencodehx bin");
	const installedBun = path.join(installedRoot, "node_modules", ".bin", process.platform === "win32" ? "bun.cmd" : "bun");
	assert.equal(existsSync(installedBun), true, "installed package exposes package-local bun");
	const installedEnv = {
		...process.env,
		XDG_CONFIG_HOME: path.join(tempRoot, "installed-config"),
		XDG_DATA_HOME: path.join(tempRoot, "installed-data"),
		OPENCODE_TEST_HOME: path.join(tempRoot, "installed-home"),
	};
	delete installedEnv.OPENCODE_DB;

	const version = expectOk(run(bin, ["--version"]), "installed version");
	assert.equal(version.stdout, `${packageJson.version}\n`);

	const help = expectOk(run(bin, ["--help"]), "installed help");
	assert.match(help.stdout, /providers\s+manage AI providers and credentials/);

	const runResult = expectOk(run(bin, ["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "package."], { env: installedEnv }), "installed run");
	assert.equal(runResult.stdout, "Hello from the fake provider.\n");
	const projectDir = path.join(tempRoot, "workspace");
	mkdirSync(projectDir, { recursive: true });
	const attachment = path.join(projectDir, "installed-attached.txt");
	writeFileSync(attachment, "attached from installed package\n");
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
		], { env: installedEnv }),
		"installed run with dir",
	);
	const runJsonTranscript = JSON.parse(runJson.stdout);
	assert.equal(assistantCwd(runJsonTranscript), projectDir, "installed run assistant cwd");
	assert.match(runJsonTranscript.request.sessionID, /^ses_/, "installed default run session id");
	const defaultExport = expectOk(run(bin, ["export", runJsonTranscript.request.sessionID], { env: installedEnv }), "installed default export");
	assert.equal(JSON.parse(defaultExport.stdout).messages.length, 2, "installed default export messages");
	const defaultResume = expectOk(run(bin, ["run", "--format", "json", "--session", runJsonTranscript.request.sessionID, "Continue", "installed", "default."], { env: installedEnv }),
		"installed default resume");
	assert.equal(JSON.parse(defaultResume.stdout).request.sessionID, runJsonTranscript.request.sessionID, "installed default resume session id");
	const defaultContinue = expectOk(run(bin, ["run", "--format", "json", "--continue", "Continue", "latest", "installed", "default."], { env: installedEnv }),
		"installed default continue");
	assert.match(JSON.parse(defaultContinue.stdout).request.sessionID, /^ses_/, "installed default continue session id");
	const runWithFile = expectOk(
		run(bin, [
			"run",
			"--format",
			"json",
			"--model",
			"openai/gpt-5.2",
			"--dir",
			projectDir,
			"--file",
			"installed-attached.txt",
			"Use",
			"installed",
			"file.",
		], { env: installedEnv }),
		"installed run with file",
	);
	const runWithFileParts = JSON.parse(runWithFile.stdout).messages[0].parts;
	assert.equal(runWithFileParts[0].type, "file", "installed run file part type");
	assert.equal(runWithFileParts[0].filename, "installed-attached.txt", "installed run file part filename");
	assert.equal(runWithFileParts[1].text, "Use installed file.", "installed run file prompt");
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
		], { env: installedEnv }),
		"installed mock AI SDK run with dir",
	);
	const mockTranscript = JSON.parse(mockJson.stdout);
	assert.equal(mockTranscript.provider.id, "openai", "installed mock AI SDK provider");
	assert.equal(mockTranscript.events[0].type, "start", "installed mock AI SDK start event");
	assert.equal(assistantCwd(mockTranscript), projectDir, "installed mock AI SDK assistant cwd");
	assert.match(mockTranscript.request.sessionID, /^ses_/, "installed default mock AI SDK session id");
	const mockDefaultExport = expectOk(run(bin, ["export", mockTranscript.request.sessionID], { env: installedEnv }), "installed default mock AI SDK export");
	assert.equal(JSON.parse(mockDefaultExport.stdout).messages.length, 2, "installed default mock AI SDK export messages");
	await withLiveOpenAICompatibleServer(async (localUrl, observed) => {
		const liveConfigRoot = path.join(tempRoot, "installed-live-config");
		const liveDataRoot = path.join(tempRoot, "installed-live-data");
		mkdirSync(path.join(liveConfigRoot, "opencode"), { recursive: true });
		mkdirSync(path.join(liveDataRoot, "opencode"), { recursive: true });
		writeFileSync(
			path.join(liveConfigRoot, "opencode", "opencode.json"),
			JSON.stringify({
				$schema: "https://opencode.ai/config.json",
				model: "installed-live/chat",
				provider: {
					"installed-live": {
						npm: "@ai-sdk/openai-compatible",
						name: "Installed Live",
						options: { baseURL: `${localUrl}/v1`, apiKey: "installed-live-key" },
						models: { chat: { name: "Chat" } },
					},
				},
			}),
		);
		const liveEnv = {
			...process.env,
			XDG_CONFIG_HOME: liveConfigRoot,
			XDG_DATA_HOME: liveDataRoot,
		};
		const liveRun = await expectOkAsync(
			runAsync(
				bin,
				[
					"run",
					"--model",
					"installed-live/chat",
					"--format",
					"json",
					"--dir",
					projectDir,
					"Hello",
					"installed",
					"live.",
				],
				{ env: liveEnv },
			),
			"installed live AI SDK run",
		);
		const liveTranscript = JSON.parse(liveRun.stdout);
		assert.equal(liveTranscript.provider.id, "installed-live", "installed live AI SDK provider");
		assert.equal(liveTranscript.request.prompt, "Hello installed live.", "installed live AI SDK prompt");
		assert.equal(liveTranscript.messages[1].parts.find((part) => part.type === "text").text, "Hello from installed live.");
		assert.equal(realpathSync(assistantCwd(liveTranscript)), realpathSync(projectDir), "installed live AI SDK assistant cwd");
		assert.equal(observed.path, "/v1/chat/completions", "installed live AI SDK request path");
		assert.equal(observed.auth, "Bearer installed-live-key", "installed live AI SDK auth header");
		assert.equal(observed.body.stream, true, "installed live AI SDK stream flag");
		assert.match(liveTranscript.request.sessionID, /^ses_/, "installed live AI SDK session id");
		const liveExport = expectOk(run(bin, ["export", liveTranscript.request.sessionID], { env: liveEnv }), "installed live AI SDK export");
		const liveExportJson = JSON.parse(liveExport.stdout);
		assert.equal(liveExportJson.messages.length, 2, "installed live AI SDK export messages");
		assert.equal(liveExportJson.messages[0].parts[0].text, "Hello installed live.", "installed live AI SDK export prompt");
		const liveAppend = await expectOkAsync(
			runAsync(
				bin,
				[
					"run",
					"--live-ai-sdk",
					"--model",
					"installed-live/chat",
					"--format",
					"json",
					"--session",
					liveTranscript.request.sessionID,
					"Append",
					"installed",
					"live.",
				],
				{ env: liveEnv },
			),
			"installed resumed live AI SDK run",
		);
		assert.equal(JSON.parse(liveAppend.stdout).request.sessionID, liveTranscript.request.sessionID, "installed resumed live AI SDK session id");
		const liveAppendExport = expectOk(run(bin, ["export", liveTranscript.request.sessionID], { env: liveEnv }), "installed resumed live AI SDK export");
		const liveAppendExportJson = JSON.parse(liveAppendExport.stdout);
		assert.equal(liveAppendExportJson.messages.length, 4, "installed resumed live AI SDK export messages");
		assert.equal(liveAppendExportJson.messages[2].parts[0].text, "Append installed live.", "installed resumed live AI SDK export prompt");
		const liveContinue = await expectOkAsync(
			runAsync(
				bin,
				[
					"run",
					"--live-ai-sdk",
					"--model",
					"installed-live/chat",
					"--format",
					"json",
					"--continue",
					"Continue",
					"installed",
					"live.",
				],
				{ env: liveEnv },
			),
			"installed continued live AI SDK run",
		);
		assert.equal(JSON.parse(liveContinue.stdout).request.sessionID, liveTranscript.request.sessionID, "installed continued live AI SDK session id");
		const liveContinueExport = expectOk(run(bin, ["export", liveTranscript.request.sessionID], { env: liveEnv }), "installed continued live AI SDK export");
		const liveContinueExportJson = JSON.parse(liveContinueExport.stdout);
		assert.equal(liveContinueExportJson.messages.length, 6, "installed continued live AI SDK export messages");
		assert.equal(liveContinueExportJson.messages[4].parts[0].text, "Continue installed live.", "installed continued live AI SDK export prompt");
		const liveFork = await expectOkAsync(
			runAsync(
				bin,
				[
					"run",
					"--live-ai-sdk",
					"--model",
					"installed-live/chat",
					"--format",
					"json",
					"--continue",
					"--fork",
					"Fork",
					"installed",
					"live.",
				],
				{ env: liveEnv },
			),
			"installed forked live AI SDK run",
		);
		const liveForkJson = JSON.parse(liveFork.stdout);
		assert.match(liveForkJson.request.sessionID, /^ses_/, "installed forked live AI SDK session id");
		assert.notEqual(liveForkJson.request.sessionID, liveTranscript.request.sessionID, "installed forked live AI SDK child session id");
		const liveForkExport = expectOk(run(bin, ["export", liveForkJson.request.sessionID], { env: liveEnv }), "installed forked live AI SDK export");
		const liveForkExportJson = JSON.parse(liveForkExport.stdout);
		assert.equal(liveForkExportJson.info.parentID, liveTranscript.request.sessionID, "installed forked live AI SDK parent id");
		assert.equal(liveForkExportJson.messages.length, 2, "installed forked live AI SDK export messages");
		assert.equal(liveForkExportJson.messages[0].parts[0].text, "Fork installed live.", "installed forked live AI SDK export prompt");
		const configuredLiveEnv = {
			...liveEnv,
			XDG_DATA_HOME: path.join(tempRoot, "installed-live-configured-data"),
		};
		const configuredLive = await expectOkAsync(
			runAsync(
				bin,
				["run", "--format", "json", "--dir", projectDir, "Hello", "configured", "installed", "live."],
				{ env: configuredLiveEnv },
			),
			"installed configured live AI SDK run",
		);
		const configuredLiveTranscript = JSON.parse(configuredLive.stdout);
		assert.equal(configuredLiveTranscript.provider.id, "installed-live", "installed configured live AI SDK provider");
		assert.equal(configuredLiveTranscript.request.prompt, "Hello configured installed live.", "installed configured live AI SDK prompt");
		assert.equal(
			configuredLiveTranscript.messages[1].parts.find((part) => part.type === "text").text,
			"Hello from installed live.",
			"installed configured live AI SDK assistant text",
		);
		writeFileSync(
			path.join(liveConfigRoot, "opencode", "opencode.json"),
			JSON.stringify({
				$schema: "https://opencode.ai/config.json",
				default_agent: "reviewer",
				provider: {
					"installed-live": {
						npm: "@ai-sdk/openai-compatible",
						name: "Installed Live",
						options: { baseURL: `${localUrl}/v1`, apiKey: "installed-live-key" },
						models: { chat: { name: "Chat" } },
					},
				},
				agent: {
					reviewer: {
						model: "installed-live/chat",
						prompt: "Installed agent prompt from config.",
						tools: { write: false },
						options: { textVerbosity: "low" },
					},
				},
			}),
		);
		const agentConfiguredLiveEnv = {
			...liveEnv,
			XDG_DATA_HOME: path.join(tempRoot, "installed-live-agent-configured-data"),
		};
		const agentConfiguredLive = await expectOkAsync(
			runAsync(
				bin,
				["run", "--format", "json", "--dir", projectDir, "Hello", "configured", "installed", "agent."],
				{ env: agentConfiguredLiveEnv },
			),
			"installed agent-configured live AI SDK run",
		);
		const agentConfiguredLiveTranscript = JSON.parse(agentConfiguredLive.stdout);
		assert.equal(agentConfiguredLiveTranscript.provider.id, "installed-live", "installed agent-configured live provider");
		assert.equal(
			agentConfiguredLiveTranscript.request.system[0].startsWith("Installed agent prompt from config."),
			true,
			"installed agent-configured system prompt",
		);
		assert.equal(agentConfiguredLiveTranscript.request.system[0].includes("Working directory:"), true, "installed agent-configured env prompt");
		assert.equal(agentConfiguredLiveTranscript.request.tools.includes("write"), false, "installed agent-configured hides write");
		assert.equal(agentConfiguredLiveTranscript.messages[0].info.agent, "reviewer", "installed agent-configured user agent");
		assert.equal(
			observed.body.messages[0].content.startsWith("Installed agent prompt from config."),
			true,
			"installed agent-configured request body system",
		);
		assert.equal(observed.body.messages[0].content.includes("Working directory:"), true, "installed agent-configured body env prompt");
		const installedAgentToolNames = (observed.body.tools ?? []).map((tool) => tool.function.name);
		assert.equal(installedAgentToolNames.includes("read"), true, "installed agent-configured advertises read");
		assert.equal(installedAgentToolNames.includes("write"), false, "installed agent-configured hides write from body");
	});
	await withToolOpenAICompatibleServer(
		{
			tool: "read",
			callId: "call_read_1",
			arguments: { filePath: "installed-tool.txt" },
			finalText: "Installed read tool completed.",
			usage: { prompt_tokens: 11, completion_tokens: 4, total_tokens: 15 },
		},
		async (localUrl, observed) => {
			const liveToolConfigRoot = path.join(tempRoot, "installed-live-tool-config");
			const liveToolDataRoot = path.join(tempRoot, "installed-live-tool-data");
			mkdirSync(path.join(liveToolConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveToolDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveToolConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-tool/chat",
					provider: {
						"installed-tool": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Tool",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-tool-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			writeFileSync(path.join(projectDir, "installed-tool.txt"), "installed tool fixture contents\n");
			const liveToolEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveToolConfigRoot,
				XDG_DATA_HOME: liveToolDataRoot,
			};
			const liveTool = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Read", "installed", "tool", "fixture."], { env: liveToolEnv }),
				"installed live AI SDK tool run",
			);
			const liveToolJson = JSON.parse(liveTool.stdout);
			assert.equal(liveToolJson.provider.id, "installed-tool", "installed live tool provider");
			assert.equal(liveToolJson.messages[1].parts.find((part) => part.type === "text").text, "Installed read tool completed.", "installed live tool final text");
			assert.equal(liveToolJson.events.some((event) => event.type === "tool-call" && event.tool === "read"), true, "installed live tool-call event");
			assert.equal(liveToolJson.events.some((event) => event.type === "tool-call-start" && event.tool === "read"), true, "installed live tool start event");
			assert.equal(
				liveToolJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "read" && event.status === "completed"),
				true,
				"installed live tool finish event",
			);
			assert.equal(liveToolJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "read"), true, "installed live tool part");
			assert.equal(observed.auth, "Bearer installed-tool-key", "installed live tool auth header");
			assert.equal(observed.paths.length, 2, "installed live tool continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live tool first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live tool continuation stream flag");
			const liveToolExport = expectOk(run(bin, ["export", liveToolJson.request.sessionID], { env: liveToolEnv }), "installed live AI SDK tool export");
			const liveToolExportJson = JSON.parse(liveToolExport.stdout);
			assert.equal(liveToolExportJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "read"), true, "installed live tool export part");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "write",
			callId: "call_write_1",
			arguments: { filePath: "installed-written.txt", content: "written by installed live tool\n" },
			finalText: "Installed write tool completed.",
			usage: { prompt_tokens: 13, completion_tokens: 4, total_tokens: 17 },
		},
		async (localUrl, observed) => {
			const liveWriteConfigRoot = path.join(tempRoot, "installed-live-write-config");
			const liveWriteDataRoot = path.join(tempRoot, "installed-live-write-data");
			mkdirSync(path.join(liveWriteConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveWriteDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveWriteConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-write/chat",
					provider: {
						"installed-write": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Write",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-write-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveWriteEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveWriteConfigRoot,
				XDG_DATA_HOME: liveWriteDataRoot,
			};
			const liveWrite = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Write", "installed", "tool", "fixture."], { env: liveWriteEnv }),
				"installed live AI SDK write tool run",
			);
			const liveWriteJson = JSON.parse(liveWrite.stdout);
			assert.equal(liveWriteJson.provider.id, "installed-write", "installed live write provider");
			assert.equal(
				liveWriteJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed write tool completed.",
				"installed live write final text",
			);
			assert.equal(liveWriteJson.events.some((event) => event.type === "tool-call" && event.tool === "write"), true, "installed live write tool-call event");
			assert.equal(liveWriteJson.events.some((event) => event.type === "tool-call-start" && event.tool === "write"), true, "installed live write start event");
			assert.equal(
				liveWriteJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "write" && event.status === "completed"),
				true,
				"installed live write finish event",
			);
			assert.equal(liveWriteJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "write"), true, "installed live write tool part");
			assert.equal(readFileSync(path.join(projectDir, "installed-written.txt"), "utf8"), "written by installed live tool\n", "installed live write file content");
			assert.equal(observed.auth, "Bearer installed-write-key", "installed live write auth header");
			assert.equal(observed.paths.length, 2, "installed live write continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live write first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live write continuation stream flag");
			const liveWriteExport = expectOk(run(bin, ["export", liveWriteJson.request.sessionID], { env: liveWriteEnv }), "installed live AI SDK write export");
			const liveWriteExportJson = JSON.parse(liveWriteExport.stdout);
			assert.equal(liveWriteExportJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "write"), true, "installed live write export part");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "edit",
			callId: "call_edit_1",
			arguments: { filePath: "installed-edit.txt", oldString: "old installed line", newString: "edited installed line" },
			finalText: "Installed edit tool completed.",
			usage: { prompt_tokens: 15, completion_tokens: 4, total_tokens: 19 },
		},
		async (localUrl, observed) => {
			const liveEditConfigRoot = path.join(tempRoot, "installed-live-edit-config");
			const liveEditDataRoot = path.join(tempRoot, "installed-live-edit-data");
			mkdirSync(path.join(liveEditConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveEditDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveEditConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-edit/chat",
					provider: {
						"installed-edit": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Edit",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-edit-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			writeFileSync(path.join(projectDir, "installed-edit.txt"), "alpha\nold installed line\nomega\n");
			const liveEditEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveEditConfigRoot,
				XDG_DATA_HOME: liveEditDataRoot,
			};
			const liveEdit = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Edit", "installed", "tool", "fixture."], { env: liveEditEnv }),
				"installed live AI SDK edit tool run",
			);
			const liveEditJson = JSON.parse(liveEdit.stdout);
			assert.equal(liveEditJson.provider.id, "installed-edit", "installed live edit provider");
			assert.equal(
				liveEditJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed edit tool completed.",
				"installed live edit final text",
			);
			assert.equal(liveEditJson.events.some((event) => event.type === "tool-call" && event.tool === "edit"), true, "installed live edit tool-call event");
			assert.equal(liveEditJson.events.some((event) => event.type === "tool-call-start" && event.tool === "edit"), true, "installed live edit start event");
			assert.equal(
				liveEditJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "edit" && event.status === "completed"),
				true,
				"installed live edit finish event",
			);
			assert.equal(liveEditJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "edit"), true, "installed live edit tool part");
			assert.equal(readFileSync(path.join(projectDir, "installed-edit.txt"), "utf8"), "alpha\nedited installed line\nomega\n", "installed live edit file content");
			assert.equal(observed.auth, "Bearer installed-edit-key", "installed live edit auth header");
			assert.equal(observed.paths.length, 2, "installed live edit continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live edit first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live edit continuation stream flag");
			const liveEditExport = expectOk(run(bin, ["export", liveEditJson.request.sessionID], { env: liveEditEnv }), "installed live AI SDK edit export");
			const liveEditExportJson = JSON.parse(liveEditExport.stdout);
			assert.equal(liveEditExportJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "edit"), true, "installed live edit export part");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "apply_patch",
			callId: "call_apply_patch_1",
			arguments: {
				patchText: [
					"*** Begin Patch",
					"*** Update File: installed-patch.txt",
					"@@",
					"-old installed patch line",
					"+patched installed line",
					"*** End Patch",
				].join("\n"),
			},
			finalText: "Installed apply patch tool completed.",
			usage: { prompt_tokens: 17, completion_tokens: 5, total_tokens: 22 },
		},
		async (localUrl, observed) => {
			const livePatchConfigRoot = path.join(tempRoot, "installed-live-patch-config");
			const livePatchDataRoot = path.join(tempRoot, "installed-live-patch-data");
			mkdirSync(path.join(livePatchConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(livePatchDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(livePatchConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-patch/chat",
					provider: {
						"installed-patch": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Patch",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-patch-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			writeFileSync(path.join(projectDir, "installed-patch.txt"), "alpha\nold installed patch line\nomega\n");
			const livePatchEnv = {
				...process.env,
				XDG_CONFIG_HOME: livePatchConfigRoot,
				XDG_DATA_HOME: livePatchDataRoot,
			};
			const livePatch = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Patch", "installed", "tool", "fixture."], { env: livePatchEnv }),
				"installed live AI SDK apply_patch tool run",
			);
			const livePatchJson = JSON.parse(livePatch.stdout);
			assert.equal(livePatchJson.provider.id, "installed-patch", "installed live apply_patch provider");
			assert.equal(
				livePatchJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed apply patch tool completed.",
				"installed live apply_patch final text",
			);
			assert.equal(livePatchJson.events.some((event) => event.type === "tool-call" && event.tool === "apply_patch"), true, "installed live apply_patch tool-call event");
			assert.equal(livePatchJson.events.some((event) => event.type === "tool-call-start" && event.tool === "apply_patch"), true, "installed live apply_patch start event");
			assert.equal(
				livePatchJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "apply_patch" && event.status === "completed"),
				true,
				"installed live apply_patch finish event",
			);
			assert.equal(livePatchJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "apply_patch"), true, "installed live apply_patch tool part");
			assert.equal(readFileSync(path.join(projectDir, "installed-patch.txt"), "utf8"), "alpha\npatched installed line\nomega\n", "installed live apply_patch file content");
			assert.equal(observed.auth, "Bearer installed-patch-key", "installed live apply_patch auth header");
			assert.equal(observed.paths.length, 2, "installed live apply_patch continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live apply_patch first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live apply_patch continuation stream flag");
			const livePatchExport = expectOk(run(bin, ["export", livePatchJson.request.sessionID], { env: livePatchEnv }), "installed live AI SDK apply_patch export");
			const livePatchExportJson = JSON.parse(livePatchExport.stdout);
			assert.equal(
				livePatchExportJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "apply_patch"),
				true,
				"installed live apply_patch export part",
			);
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "bash",
			callId: "call_bash_1",
			arguments: {
				command: "printf 'bash installed live tool\\n' > installed-bash.txt",
				description: "Create installed live bash fixture",
			},
			finalText: "Installed bash tool completed.",
			usage: { prompt_tokens: 19, completion_tokens: 4, total_tokens: 23 },
		},
		async (localUrl, observed) => {
			const liveBashConfigRoot = path.join(tempRoot, "installed-live-bash-config");
			const liveBashDataRoot = path.join(tempRoot, "installed-live-bash-data");
			mkdirSync(path.join(liveBashConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveBashDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveBashConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-bash/chat",
					provider: {
						"installed-bash": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Bash",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-bash-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveBashEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveBashConfigRoot,
				XDG_DATA_HOME: liveBashDataRoot,
			};
			const liveBash = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Run", "installed", "bash", "fixture."], { env: liveBashEnv }),
				"installed live AI SDK bash tool run",
			);
			const liveBashJson = JSON.parse(liveBash.stdout);
			assert.equal(liveBashJson.provider.id, "installed-bash", "installed live bash provider");
			assert.equal(
				liveBashJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed bash tool completed.",
				"installed live bash final text",
			);
			assert.equal(liveBashJson.events.some((event) => event.type === "tool-call" && event.tool === "bash"), true, "installed live bash tool-call event");
			assert.equal(liveBashJson.events.some((event) => event.type === "tool-call-start" && event.tool === "bash"), true, "installed live bash start event");
			assert.equal(
				liveBashJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "bash" && event.status === "completed"),
				true,
				"installed live bash finish event",
			);
			assert.equal(liveBashJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "bash"), true, "installed live bash tool part");
			assert.equal(readFileSync(path.join(projectDir, "installed-bash.txt"), "utf8"), "bash installed live tool\n", "installed live bash file content");
			assert.equal(observed.auth, "Bearer installed-bash-key", "installed live bash auth header");
			assert.equal(observed.paths.length, 2, "installed live bash continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live bash first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live bash continuation stream flag");
			const liveBashExport = expectOk(run(bin, ["export", liveBashJson.request.sessionID], { env: liveBashEnv }), "installed live AI SDK bash export");
			const liveBashExportJson = JSON.parse(liveBashExport.stdout);
			assert.equal(liveBashExportJson.messages[1].parts.some((part) => part.type === "tool" && part.tool === "bash"), true, "installed live bash export part");
		},
	);
	await withToolChainOpenAICompatibleServer(
		{
			steps: [
				{
					tool: "write",
					callId: "call_installed_chain_write_1",
					arguments: { filePath: "installed-chain.txt", content: "chain written by installed live tool\n" },
				},
				{
					tool: "read",
					callId: "call_installed_chain_read_1",
					arguments: { filePath: "installed-chain.txt" },
				},
			],
			finalText: "Installed tool chain completed.",
			usage: { prompt_tokens: 23, completion_tokens: 6, total_tokens: 29 },
		},
		async (localUrl, observed) => {
			const liveChainConfigRoot = path.join(tempRoot, "installed-live-chain-config");
			const liveChainDataRoot = path.join(tempRoot, "installed-live-chain-data");
			mkdirSync(path.join(liveChainConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveChainDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveChainConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-chain/chat",
					provider: {
						"installed-chain": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Chain",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-chain-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveChainEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveChainConfigRoot,
				XDG_DATA_HOME: liveChainDataRoot,
			};
			const liveChain = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Write", "then", "read", "installed", "chain", "fixture."], { env: liveChainEnv }),
				"installed live AI SDK tool chain run",
			);
			const liveChainJson = JSON.parse(liveChain.stdout);
			assert.equal(liveChainJson.provider.id, "installed-chain", "installed live chain provider");
			assert.equal(
				liveChainJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed tool chain completed.",
				"installed live chain final text",
			);
			assert.equal(liveChainJson.events.some((event) => event.type === "tool-call" && event.tool === "write"), true, "installed live chain write call event");
			assert.equal(liveChainJson.events.some((event) => event.type === "tool-call" && event.tool === "read"), true, "installed live chain read call event");
			assert.equal(
				liveChainJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "write" && event.status === "completed"),
				true,
				"installed live chain write finish event",
			);
			assert.equal(
				liveChainJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "read" && event.status === "completed"),
				true,
				"installed live chain read finish event",
			);
			const liveChainToolParts = liveChainJson.messages[1].parts.filter((part) => part.type === "tool");
			assert.equal(liveChainToolParts.some((part) => part.tool === "write"), true, "installed live chain write tool part");
			assert.equal(liveChainToolParts.some((part) => part.tool === "read"), true, "installed live chain read tool part");
			assert.equal(readFileSync(path.join(projectDir, "installed-chain.txt"), "utf8"), "chain written by installed live tool\n", "installed live chain file content");
			assert.equal(observed.auth, "Bearer installed-chain-key", "installed live chain auth header");
			assert.equal(observed.paths.length, 3, "installed live chain continuation requests");
			assert.equal(observed.bodies[0].stream, true, "installed live chain first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live chain second stream flag");
			assert.equal(observed.bodies[2].stream, true, "installed live chain third stream flag");
			assert.match(JSON.stringify(observed.bodies[1]), /call_installed_chain_write_1/, "installed live chain write history");
			assert.match(JSON.stringify(observed.bodies[2]), /call_installed_chain_read_1/, "installed live chain read history");
			assert.match(JSON.stringify(observed.bodies[2]), /chain written by installed live tool/, "installed live chain read-result history");
			const liveChainExport = expectOk(run(bin, ["export", liveChainJson.request.sessionID], { env: liveChainEnv }), "installed live AI SDK tool chain export");
			const liveChainExportJson = JSON.parse(liveChainExport.stdout);
			const liveChainExportToolParts = liveChainExportJson.messages[1].parts.filter((part) => part.type === "tool");
			assert.equal(liveChainExportToolParts.some((part) => part.tool === "write"), true, "installed live chain export write part");
			assert.equal(liveChainExportToolParts.some((part) => part.tool === "read"), true, "installed live chain export read part");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "write",
			callId: "call_installed_denied_write_1",
			arguments: { filePath: "installed-denied.txt", content: "should not be written\n" },
			finalText: "Installed denied write should not continue.",
			usage: { prompt_tokens: 7, completion_tokens: 1, total_tokens: 8 },
		},
		async (localUrl, observed) => {
			const liveDeniedConfigRoot = path.join(tempRoot, "installed-live-denied-config");
			const liveDeniedDataRoot = path.join(tempRoot, "installed-live-denied-data");
			mkdirSync(path.join(liveDeniedConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveDeniedDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveDeniedConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-denied/chat",
					permission: { edit: "deny" },
					provider: {
						"installed-denied": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Denied",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-denied-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveDeniedEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveDeniedConfigRoot,
				XDG_DATA_HOME: liveDeniedDataRoot,
			};
			const liveDenied = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "Try", "an", "installed", "denied", "write."], { env: liveDeniedEnv }),
				"installed live AI SDK denied write run",
			);
			const liveDeniedJson = JSON.parse(liveDenied.stdout);
			assert.equal(liveDeniedJson.provider.id, "installed-denied", "installed live denied provider");
			assert.equal(liveDeniedJson.events.some((event) => event.type === "tool-call" && event.tool === "write"), true, "installed live denied write call");
			const liveDeniedFinish = liveDeniedJson.events.find((event) => event.type === "tool-call-finish" && event.tool === "write");
			assert.equal(liveDeniedFinish.status, "error", "installed live denied write status");
			assert.match(liveDeniedFinish.error, /specified a rule which prevents this tool call/, "installed live denied write event error");
			const liveDeniedTool = liveDeniedJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveDeniedTool.state.status, "error", "installed live denied write tool state");
			assert.match(liveDeniedTool.state.error, /write tool was denied permission/, "installed live denied write tool error");
			assert.equal(existsSync(path.join(projectDir, "installed-denied.txt")), false, "installed live denied write no file");
			assert.equal(observed.auth, "Bearer installed-denied-key", "installed live denied auth header");
			assert.equal(observed.paths.length, 1, "installed live denied no continuation");
			assert.equal(observed.bodies[0].stream, true, "installed live denied stream flag");
			const liveDeniedExport = expectOk(run(bin, ["export", liveDeniedJson.request.sessionID], { env: liveDeniedEnv }), "installed live AI SDK denied write export");
			const liveDeniedExportJson = JSON.parse(liveDeniedExport.stdout);
			const liveDeniedExportTool = liveDeniedExportJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveDeniedExportTool.state.status, "error", "installed live denied export tool state");
			assert.match(liveDeniedExportTool.state.error, /write tool was denied permission/, "installed live denied export tool error");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "write",
			callId: "call_installed_skip_write_1",
			arguments: { filePath: "installed-skip.txt", content: "skip permission installed write\n" },
			finalText: "Installed permission skip write completed.",
			usage: { prompt_tokens: 9, completion_tokens: 3, total_tokens: 12 },
		},
		async (localUrl, observed) => {
			const liveSkipConfigRoot = path.join(tempRoot, "installed-live-skip-config");
			const liveSkipDataRoot = path.join(tempRoot, "installed-live-skip-data");
			mkdirSync(path.join(liveSkipConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveSkipDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveSkipConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-skip/chat",
					permission: { edit: "ask" },
					provider: {
						"installed-skip": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Skip",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-skip-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveSkipEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveSkipConfigRoot,
				XDG_DATA_HOME: liveSkipDataRoot,
			};
			const liveSkip = await expectOkAsync(
				runAsync(bin, ["run", "--format", "json", "--dir", projectDir, "--dangerously-skip-permissions", "Write", "with", "installed", "permission", "skip."], {
					env: liveSkipEnv,
				}),
				"installed live AI SDK permission skip write run",
			);
			const liveSkipJson = JSON.parse(liveSkip.stdout);
			assert.equal(liveSkipJson.provider.id, "installed-skip", "installed live skip provider");
			assert.equal(
				liveSkipJson.messages[1].parts.find((part) => part.type === "text").text,
				"Installed permission skip write completed.",
				"installed live skip final text",
			);
			assert.equal(liveSkipJson.events.some((event) => event.type === "tool-call" && event.tool === "write"), true, "installed live skip write call");
			assert.equal(liveSkipJson.events.some((event) => event.type === "tool-call-start" && event.tool === "write"), true, "installed live skip write start");
			assert.equal(
				liveSkipJson.events.some((event) => event.type === "tool-call-finish" && event.tool === "write" && event.status === "completed"),
				true,
				"installed live skip write finish",
			);
			const liveSkipTool = liveSkipJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveSkipTool.state.status, "completed", "installed live skip write tool state");
			assert.equal(readFileSync(path.join(projectDir, "installed-skip.txt"), "utf8"), "skip permission installed write\n", "installed live skip write file");
			assert.equal(observed.auth, "Bearer installed-skip-key", "installed live skip auth header");
			assert.equal(observed.paths.length, 2, "installed live skip continuation request");
			assert.equal(observed.bodies[0].stream, true, "installed live skip first stream flag");
			assert.equal(observed.bodies[1].stream, true, "installed live skip continuation stream flag");
			assert.match(JSON.stringify(observed.bodies[1]), /call_installed_skip_write_1/, "installed live skip history call ID");
			assert.match(JSON.stringify(observed.bodies[1]), /skip permission installed write/, "installed live skip tool-result history");
			const liveSkipExport = expectOk(run(bin, ["export", liveSkipJson.request.sessionID], { env: liveSkipEnv }), "installed live AI SDK permission skip write export");
			const liveSkipExportJson = JSON.parse(liveSkipExport.stdout);
			const liveSkipExportTool = liveSkipExportJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveSkipExportTool.state.status, "completed", "installed live skip export tool state");
		},
	);
	await withToolOpenAICompatibleServer(
		{
			tool: "write",
			callId: "call_installed_skip_denied_write_1",
			arguments: { filePath: "installed-skip-denied.txt", content: "installed skip must not override deny\n" },
			finalText: "Installed denied skip write should not continue.",
			usage: { prompt_tokens: 7, completion_tokens: 1, total_tokens: 8 },
		},
		async (localUrl, observed) => {
			const liveSkipDeniedConfigRoot = path.join(tempRoot, "installed-live-skip-denied-config");
			const liveSkipDeniedDataRoot = path.join(tempRoot, "installed-live-skip-denied-data");
			mkdirSync(path.join(liveSkipDeniedConfigRoot, "opencode"), { recursive: true });
			mkdirSync(path.join(liveSkipDeniedDataRoot, "opencode"), { recursive: true });
			writeFileSync(
				path.join(liveSkipDeniedConfigRoot, "opencode", "opencode.json"),
				JSON.stringify({
					$schema: "https://opencode.ai/config.json",
					model: "installed-skip-denied/chat",
					permission: { edit: "deny" },
					provider: {
						"installed-skip-denied": {
							npm: "@ai-sdk/openai-compatible",
							name: "Installed Skip Denied",
							options: { baseURL: `${localUrl}/v1`, apiKey: "installed-skip-denied-key" },
							models: { chat: { name: "Chat" } },
						},
					},
				}),
			);
			const liveSkipDeniedEnv = {
				...process.env,
				XDG_CONFIG_HOME: liveSkipDeniedConfigRoot,
				XDG_DATA_HOME: liveSkipDeniedDataRoot,
			};
			const liveSkipDenied = await expectOkAsync(
				runAsync(
					bin,
					["run", "--format", "json", "--dir", projectDir, "--dangerously-skip-permissions", "Try", "an", "installed", "denied", "permission", "skip", "write."],
					{ env: liveSkipDeniedEnv },
				),
				"installed live AI SDK permission skip denied write run",
			);
			const liveSkipDeniedJson = JSON.parse(liveSkipDenied.stdout);
			assert.equal(liveSkipDeniedJson.provider.id, "installed-skip-denied", "installed live skip denied provider");
			assert.equal(liveSkipDeniedJson.events.some((event) => event.type === "tool-call" && event.tool === "write"), true, "installed live skip denied write call");
			const liveSkipDeniedFinish = liveSkipDeniedJson.events.find((event) => event.type === "tool-call-finish" && event.tool === "write");
			assert.equal(liveSkipDeniedFinish.status, "error", "installed live skip denied write status");
			assert.match(liveSkipDeniedFinish.error, /specified a rule which prevents this tool call/, "installed live skip denied write event error");
			const liveSkipDeniedTool = liveSkipDeniedJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveSkipDeniedTool.state.status, "error", "installed live skip denied write tool state");
			assert.match(liveSkipDeniedTool.state.error, /write tool was denied permission/, "installed live skip denied write tool error");
			assert.equal(existsSync(path.join(projectDir, "installed-skip-denied.txt")), false, "installed live skip denied write no file");
			assert.equal(observed.auth, "Bearer installed-skip-denied-key", "installed live skip denied auth header");
			assert.equal(observed.paths.length, 1, "installed live skip denied no continuation");
			assert.equal(observed.bodies[0].stream, true, "installed live skip denied stream flag");
			const liveSkipDeniedExport = expectOk(
				run(bin, ["export", liveSkipDeniedJson.request.sessionID], { env: liveSkipDeniedEnv }),
				"installed live AI SDK permission skip denied write export",
			);
			const liveSkipDeniedExportJson = JSON.parse(liveSkipDeniedExport.stdout);
			const liveSkipDeniedExportTool = liveSkipDeniedExportJson.messages[1].parts.find((part) => part.type === "tool" && part.tool === "write");
			assert.equal(liveSkipDeniedExportTool.state.status, "error", "installed live skip denied export tool state");
			assert.match(liveSkipDeniedExportTool.state.error, /write tool was denied permission/, "installed live skip denied export tool error");
		},
	);
	await withFailingOpenAICompatibleServer(async (localUrl, observed) => {
		const liveFailureConfigRoot = path.join(tempRoot, "installed-live-failure-config");
		const liveFailureDataRoot = path.join(tempRoot, "installed-live-failure-data");
		mkdirSync(path.join(liveFailureConfigRoot, "opencode"), { recursive: true });
		mkdirSync(path.join(liveFailureDataRoot, "opencode"), { recursive: true });
		writeFileSync(
			path.join(liveFailureConfigRoot, "opencode", "opencode.json"),
			JSON.stringify({
				$schema: "https://opencode.ai/config.json",
				provider: {
					"installed-fail": {
						npm: "@ai-sdk/openai-compatible",
						name: "Installed Fail",
						options: { baseURL: `${localUrl}/v1`, apiKey: "installed-fail-key" },
						models: { chat: { name: "Chat" } },
					},
				},
			}),
		);
		const liveFailureEnv = {
			...process.env,
			XDG_CONFIG_HOME: liveFailureConfigRoot,
			XDG_DATA_HOME: liveFailureDataRoot,
			OPENCODE_DB: path.join(tempRoot, "installed-live-failure.sqlite"),
		};
		const liveFailure = await expectOkAsync(
			runAsync(
				bin,
				["run", "--live-ai-sdk", "--model", "installed-fail/chat", "--format", "json", "--dir", projectDir, "Fail", "installed", "live."],
				{ env: liveFailureEnv },
			),
			"installed failed live AI SDK run",
		);
		const liveFailureJson = JSON.parse(liveFailure.stdout);
		assert.equal(liveFailureJson.provider.id, "installed-fail", "installed failed live AI SDK provider");
		assert.equal(
			liveFailureJson.events.some((event) => event.type === "error" && event.message === "installed live failure"),
			true,
			"installed failed live AI SDK provider error event",
		);
		assert.equal(
			liveFailureJson.events.some((event) => event.type === "error" && event.message === "No output generated. Check the stream for errors."),
			true,
			"installed failed live AI SDK no-output error event",
		);
		assert.equal(liveFailureJson.messages[1].info.finish, "error", "installed failed live AI SDK assistant finish");
		assert.equal(observed.path, "/v1/chat/completions", "installed failed live AI SDK request path");
		assert.equal(observed.auth, "Bearer installed-fail-key", "installed failed live AI SDK auth header");
		assert.equal(observed.body.stream, true, "installed failed live AI SDK stream flag");
		const liveFailureExport = expectOk(run(bin, ["export", liveFailureJson.request.sessionID], { env: liveFailureEnv }), "installed failed live AI SDK export");
		const liveFailureExportJson = JSON.parse(liveFailureExport.stdout);
		assert.equal(liveFailureExportJson.messages[1].info.finish, "error", "installed failed live AI SDK export assistant finish");
		assert.equal(
			liveFailureExportJson.messages[1].parts.find((part) => part.type === "text").text,
			"",
			"installed failed live AI SDK export empty assistant text",
		);
	});
	const installedDbEnv = {
		...installedEnv,
		OPENCODE_DB: path.join(tempRoot, "installed-run.sqlite"),
	};
	const persistedRun = expectOk(
		run(bin, ["run", "--format", "json", "Persist", "from", "installed", "package."], { env: installedDbEnv }),
		"installed persisted run",
	);
	const persistedSessionID = JSON.parse(persistedRun.stdout).request.sessionID;
	assert.match(persistedSessionID, /^ses_/, "installed persisted run session id");
	const persistedExport = expectOk(run(bin, ["export", persistedSessionID], { env: installedDbEnv }), "installed persisted export");
	assert.equal(JSON.parse(persistedExport.stdout).messages.length, 2, "installed persisted export messages");
	const persistedFileRun = expectOk(
		run(bin, ["run", "--format", "json", "--dir", projectDir, "--file", "installed-attached.txt", "Persist", "installed", "file."], {
			env: installedDbEnv,
		}),
		"installed persisted file run",
	);
	const persistedFileSessionID = JSON.parse(persistedFileRun.stdout).request.sessionID;
	const persistedFileExport = expectOk(run(bin, ["export", persistedFileSessionID], { env: installedDbEnv }), "installed persisted file export");
	const persistedFileMessages = JSON.parse(persistedFileExport.stdout).messages;
	assert.equal(persistedFileMessages[0].parts[0].filename, "installed-attached.txt", "installed persisted file export filename");
	assert.equal(persistedFileMessages[0].parts[1].text, "Persist installed file.", "installed persisted file export prompt");
	const resumedRun = expectOk(
		run(bin, ["run", "--format", "json", "--session", persistedSessionID, "Append", "from", "installed", "package."], { env: installedDbEnv }),
		"installed resumed run",
	);
	assert.equal(JSON.parse(resumedRun.stdout).request.sessionID, persistedSessionID, "installed resumed run session id");
	const resumedExport = expectOk(run(bin, ["export", persistedSessionID], { env: installedDbEnv }), "installed resumed export");
	const resumedMessages = JSON.parse(resumedExport.stdout).messages;
	assert.equal(resumedMessages.length, 4, "installed resumed export messages");
	assert.equal(resumedMessages[2].parts[0].text, "Append from installed package.", "installed resumed export prompt");
	const continuedRun = expectOk(
		run(bin, ["run", "--format", "json", "--continue", "Continue", "from", "installed", "package."], { env: installedDbEnv }),
		"installed continue run",
	);
	assert.equal(JSON.parse(continuedRun.stdout).request.sessionID, persistedSessionID, "installed continue run session id");
	const continuedExport = expectOk(run(bin, ["export", persistedSessionID], { env: installedDbEnv }), "installed continue export");
	const continuedMessages = JSON.parse(continuedExport.stdout).messages;
	assert.equal(continuedMessages.length, 6, "installed continue export messages");
	assert.equal(continuedMessages[4].parts[0].text, "Continue from installed package.", "installed continue export prompt");
	const forkedRun = expectOk(
		run(bin, ["run", "--format", "json", "--session", persistedSessionID, "--fork", "Fork", "from", "installed", "package."], {
			env: installedDbEnv,
		}),
		"installed fork run",
	);
	const forkedSessionID = JSON.parse(forkedRun.stdout).request.sessionID;
	assert.match(forkedSessionID, /^ses_/, "installed fork run session id");
	assert.notEqual(forkedSessionID, persistedSessionID, "installed fork uses child session id");
	const forkedExport = expectOk(run(bin, ["export", forkedSessionID], { env: installedDbEnv }), "installed fork export");
	const forkedExportJson = JSON.parse(forkedExport.stdout);
	assert.equal(forkedExportJson.info.parentID, persistedSessionID, "installed fork parent id");
	assert.equal(forkedExportJson.messages.length, 2, "installed fork export messages");
	assert.equal(forkedExportJson.messages[0].parts[0].text, "Fork from installed package.", "installed fork export prompt");
	const installedMockDbEnv = {
		...installedEnv,
		OPENCODE_DB: path.join(tempRoot, "installed-mock-run.sqlite"),
	};
	const persistedMockRun = expectOk(
		run(bin, ["run", "--mock-ai-sdk", "--format", "json", "Persist", "from", "installed", "mock", "SDK."], { env: installedMockDbEnv }),
		"installed persisted mock AI SDK run",
	);
	const persistedMockSessionID = JSON.parse(persistedMockRun.stdout).request.sessionID;
	assert.match(persistedMockSessionID, /^ses_/, "installed persisted mock AI SDK session id");
	const persistedMockExport = expectOk(run(bin, ["export", persistedMockSessionID], { env: installedMockDbEnv }), "installed persisted mock AI SDK export");
	assert.equal(JSON.parse(persistedMockExport.stdout).messages.length, 2, "installed persisted mock AI SDK export messages");
	const resumedMockRun = expectOk(
		run(bin, ["run", "--mock-ai-sdk", "--format", "json", "--session", persistedMockSessionID, "Append", "from", "installed", "mock", "SDK."], {
			env: installedMockDbEnv,
		}),
		"installed resumed mock AI SDK run",
	);
	assert.equal(JSON.parse(resumedMockRun.stdout).request.sessionID, persistedMockSessionID, "installed resumed mock AI SDK session id");
	const resumedMockExport = expectOk(run(bin, ["export", persistedMockSessionID], { env: installedMockDbEnv }), "installed resumed mock AI SDK export");
	const resumedMockMessages = JSON.parse(resumedMockExport.stdout).messages;
	assert.equal(resumedMockMessages.length, 4, "installed resumed mock AI SDK export messages");
	assert.equal(resumedMockMessages[2].parts[0].text, "Append from installed mock SDK.", "installed resumed mock AI SDK export prompt");
	const tui = expectOk(
		run(
			installedBun,
			[
				"--preload",
				path.join(installedRoot, packageMembers.tuiPreload),
				path.join(installedRoot, packageMembers.tuiIndex),
			],
			{ cwd: installedRoot, timeout: 60_000 },
		),
		"installed TUI scaffold",
	);
	assert.match(tui.stdout, /tui-scaffold:ok/);

	const serveHelp = expectOk(run(bin, ["serve", "--help"], { env: installedEnv }), "installed serve help");
	assert.match(serveHelp.stdout, /opencodehx serve/);
	assert.match(serveHelp.stdout, /--hostname <value>/);

	const serverEnv = {
		...process.env,
		XDG_DATA_HOME: path.join(tempRoot, "server-data"),
		XDG_CONFIG_HOME: path.join(tempRoot, "server-config"),
		OPENCODE_TEST_HOME: path.join(tempRoot, "server-home"),
	};
	const server = await startInstalledServer(bin, ["serve", "--hostname", "127.0.0.1", "--port", "0"], serverEnv);
	let events = null;
	try {
		const health = await fetchJson(`${server.url}/health`);
		assert.equal(health.ok, true, "installed server health ok");
		assert.equal(health.service, "opencodehx", "installed server health service");
		events = await openEventStream(`${server.url}/event`);
		const createdSession = await fetchJson(
			`${server.url}/session`,
			jsonRequest("POST", {
				prompt: "Say hello from installed serve.",
				title: "Installed package session",
			}),
		);
		assert.equal(createdSession.id, "ses_server_1", "installed server session id");
		assert.equal(createdSession.title, "Installed package session", "installed server session title");
		const eventText = await events.readUntil((text) => {
			return text.includes('"type":"server.connected"') && text.includes('"type":"session.created"') && text.includes(`"sessionID":"${createdSession.id}"`);
		});
		assert.match(eventText, /"type":"server\.connected"/, "installed server SSE connected event");
		assert.match(eventText, /"type":"session\.created"/, "installed server SSE session event");
		const sessions = await fetchJson(`${server.url}/session`);
		assert.equal(sessions.some((session) => session.id === createdSession.id), true, "installed server lists created session");
		const sessionID = encodeURIComponent(createdSession.id);
		const messages = await fetchJson(`${server.url}/session/${sessionID}/message?limit=1`);
		assert.equal(Array.isArray(messages), true, "installed server message page is an array");
		assert.equal(messages.length, 1, "installed server message page length");
		assert.equal(messages[0].info.sessionID, createdSession.id, "installed server message session id");
		const selected = await fetchJson(`${server.url}/tui/select-session`, jsonRequest("POST", { sessionID: createdSession.id }));
		assert.equal(selected, true, "installed server selects session through TUI route");
		const aborted = await fetchJson(`${server.url}/session/${sessionID}/abort`, jsonRequest("POST"));
		assert.equal(aborted, true, "installed server aborts session");
		await verifyInstalledPty(server.url);
	} finally {
		if (events != null) {
			await events.close();
		}
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

function jsonRequest(method, body) {
	const request = {
		method,
		headers: {
			"content-type": "application/json",
		},
	};
	if (body !== undefined) {
		request.body = JSON.stringify(body);
	}
	return request;
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

async function fetchJson(url, init = {}) {
	const deadline = Date.now() + 10_000;
	let lastError;
	while (Date.now() < deadline) {
		try {
			const response = await fetch(url, init);
			assert.equal(response.status, 200, `${url} status`);
			return await response.json();
		} catch (error) {
			lastError = error;
			await new Promise((resolve) => setTimeout(resolve, 100));
		}
	}
	throw lastError ?? new Error(`timed out fetching ${url}`);
}

async function openEventStream(url) {
	const controller = new AbortController();
	const response = await fetch(url, {
		headers: { accept: "text/event-stream" },
		signal: controller.signal,
	});
	assert.equal(response.status, 200, `${url} status`);
	assert.match(response.headers.get("content-type") ?? "", /text\/event-stream/, `${url} content-type`);
	assert.ok(response.body, `${url} body`);
	const reader = response.body.getReader();
	const decoder = new TextDecoder();
	let text = "";
	return {
		async readUntil(predicate) {
			const deadline = Date.now() + 10_000;
			while (Date.now() < deadline) {
				const remaining = Math.max(1, deadline - Date.now());
				const chunk = await Promise.race([
					reader.read(),
					new Promise((_, reject) => {
						setTimeout(() => reject(new Error(`timed out reading ${url}`)), remaining);
					}),
				]);
				if (chunk.done) break;
				text += decoder.decode(chunk.value, { stream: true });
				if (predicate(text)) return text;
			}
			throw new Error(`timed out waiting for SSE event from ${url}\nreceived:\n${text}`);
		},
		async close() {
			controller.abort();
			try {
				await reader.cancel();
			} catch {
				// Aborting the fetch is the intended way to close this long-lived smoke stream.
			}
		},
	};
}

async function verifyInstalledPty(baseUrl) {
	const created = await fetchJson(
		`${baseUrl}/pty`,
		jsonRequest("POST", {
			command: "cat",
			title: "Installed WebSocket PTY",
		}),
	);
	assert.match(created.id, /^pty_/, "installed server PTY id");
	assert.equal(created.title, "Installed WebSocket PTY", "installed server PTY title");
	const ptyList = await fetchJson(`${baseUrl}/pty`);
	assert.equal(ptyList.some((pty) => pty.id === created.id), true, "installed server lists created PTY");
	const pty = await fetchJson(`${baseUrl}/pty/${encodeURIComponent(created.id)}`);
	assert.equal(pty.status, "running", "installed server PTY status");
	const wsBase = baseUrl.replace(/^http:\/\//, "ws://");
	const wsPath = `${wsBase}/pty/${encodeURIComponent(created.id)}/connect`;
	const first = await ptyWebSocket(`${wsPath}?cursor=0`, "installed-pty\n", "installed-pty");
	assert.equal(first.text.includes("installed-pty"), true, "installed server PTY websocket write output");
	assert.equal(first.cursor >= 0, true, "installed server PTY websocket initial cursor");
	const replay = await ptyWebSocket(`${wsPath}?cursor=0`, null, "installed-pty");
	assert.equal(replay.text.includes("installed-pty"), true, "installed server PTY websocket replay output");
	assert.equal(replay.cursor > first.cursor, true, "installed server PTY websocket replay cursor advances");
	const tail = await ptyWebSocket(`${wsPath}?cursor=-1`, null, null);
	assert.equal(tail.text.includes("installed-pty"), false, "installed server PTY websocket tail skips replay");
	assert.equal(tail.cursor >= replay.cursor, true, "installed server PTY websocket tail cursor");
	const removed = await fetchJson(`${baseUrl}/pty/${encodeURIComponent(created.id)}`, jsonRequest("DELETE"));
	assert.equal(removed, true, "installed server deletes PTY");
}

function ptyWebSocket(url, message, expected) {
	return new Promise((resolve, reject) => {
		const socket = new WebSocket(url);
		let text = "";
		let cursor = -1;
		let done = false;
		const timeout = setTimeout(() => {
			done = true;
			socket.close();
			reject(new Error(`timed out waiting for PTY WebSocket ${url}\nreceived:\n${text}`));
		}, 3000);

		function finish() {
			if (done) return;
			done = true;
			clearTimeout(timeout);
			socket.close();
			resolve({ text, cursor });
		}

		socket.on("open", () => {
			if (message != null) {
				socket.send(message);
			}
		});
		socket.on("message", (data) => {
			const payload = websocketPayloadText(data);
			if (payload.length > 0 && payload.charCodeAt(0) === 0) {
				cursor = JSON.parse(payload.slice(1)).cursor;
			} else {
				text += payload;
			}
			if (cursor >= 0 && (expected == null || text.includes(expected))) {
				finish();
			}
		});
		socket.on("error", (error) => {
			if (done) return;
			done = true;
			clearTimeout(timeout);
			reject(error);
		});
	});
}

function websocketPayloadText(data) {
	if (typeof data === "string") return data;
	if (Buffer.isBuffer(data)) return data.toString("utf8");
	if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
	if (ArrayBuffer.isView(data)) return Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString("utf8");
	return String(data);
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
