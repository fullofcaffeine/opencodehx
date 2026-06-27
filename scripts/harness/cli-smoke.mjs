#!/usr/bin/env node
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import Database from "better-sqlite3";
import { distIndexArgs, repoRoot } from "./paths.mjs";

const root = repoRoot;
const packageJson = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));

function run(args, options = {}) {
	return spawnSync("node", [...distIndexArgs, ...args], {
		cwd: options.cwd ?? root,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: 15_000,
	});
}

function runAsync(args, options = {}) {
	return new Promise((resolve, reject) => {
		const child = spawn("node", [...distIndexArgs, ...args], {
			cwd: options.cwd ?? root,
			env: options.env ?? process.env,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		const timeout = setTimeout(() => {
			child.kill("SIGTERM");
			reject(new Error(`Timed out running ${distIndexArgs[0]} ${args.join(" ")}`));
		}, 15_000);
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

async function withRemoteConfigServer(fn) {
	const observed = { accountAuth: null, accountOrg: null };
	const server = createServer((req, res) => {
		if (req.url === "/api/config") {
			observed.accountAuth = req.headers.authorization ?? null;
			observed.accountOrg = req.headers["x-org-id"] ?? null;
			res.writeHead(200, { "content-type": "application/json" });
			res.end(
				JSON.stringify({
					config: {
						provider: {
							"account-live": {
								npm: "@ai-sdk/openai-compatible",
								name: "Account Live",
								options: { baseURL: "https://account.example.com/v1", apiKey: "{env:OPENCODE_CONSOLE_TOKEN}" },
								models: { chat: { name: "Chat" } },
							},
						},
					},
				}),
			);
			return;
		}
		if (req.url !== "/.well-known/opencode") {
			res.writeHead(404);
			res.end();
			return;
		}
		res.writeHead(200, { "content-type": "application/json" });
		res.end(
			JSON.stringify({
				config: {
					provider: {
						"remote-live": {
							npm: "@ai-sdk/openai-compatible",
							name: "Remote Live",
							options: { baseURL: "https://remote.example.com/v1", apiKey: "{env:LIVE_REMOTE_TOKEN}" },
							models: { chat: { name: "Chat" } },
						},
					},
				},
			}),
		);
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
						id: "chatcmpl-local-live",
						created: 1,
						model: "chat",
						choices: [{ delta: { role: "assistant", content: "Hello " } }],
					},
					{
						id: "chatcmpl-local-live",
						created: 1,
						model: "chat",
						choices: [{ delta: { content: "from local live." } }],
					},
					{
						id: "chatcmpl-local-live",
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
			res.end(JSON.stringify({ error: { message: "local live failure" } }));
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

function writeAccountDatabase(file, url) {
	const db = new Database(file);
	try {
		db.exec("create table account (id text primary key, email text not null, url text not null, access_token text not null, refresh_token text not null, token_expiry integer)");
		db.exec("create table account_state (id integer primary key, active_account_id text, active_org_id text)");
		db.prepare(
			"insert into account (id, email, url, access_token, refresh_token, token_expiry) values (?, ?, ?, ?, ?, ?)",
		).run("account-live", "user@example.com", url, "account-live-token", "refresh-token", 9999999999999);
		db.prepare("insert into account_state (id, active_account_id, active_org_id) values (?, ?, ?)").run(
			1,
			"account-live",
			"org-live",
		);
	} finally {
		db.close();
	}
}

const help = run(["--help"]);
assert.equal(help.status, 0);
assert.match(help.stdout, /run\s+run opencode with a message/);
assert.match(help.stdout, /providers\s+manage AI providers and credentials/);
assert.match(help.stdout, /--print-logs\s+print logs to stderr/);

const runHelp = run(["run", "--help"]);
assert.equal(runHelp.status, 0);
assert.match(runHelp.stdout, /--file <value>\s+file\(s\) to attach to message/);
assert.match(runHelp.stdout, /--dangerously-skip-permissions\s+auto-approve permissions/);

const authHelp = run(["auth", "login", "--help"]);
assert.equal(authHelp.status, 0);
assert.match(authHelp.stdout, /opencodehx providers login \[url\]/);
assert.match(authHelp.stdout, /-p, --provider <value>\s+provider id or name/);

const plugHelp = run(["plug", "--help"]);
assert.equal(plugHelp.status, 0);
assert.match(plugHelp.stdout, /Aliases: plug/);
assert.match(plugHelp.stdout, /-g, --global\s+install in global config/);

const unsupportedKnown = run(["providers", "list"]);
assert.equal(unsupportedKnown.status, 1);
assert.match(unsupportedKnown.stderr, /Command not implemented yet: providers list/);

const version = run(["--version"]);
assert.equal(version.status, 0);
assert.equal(version.stdout, `${packageJson.version}\n`);

const defaultRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-cli-default-"));
try {
	const defaultEnv = {
		...process.env,
		XDG_CONFIG_HOME: path.join(defaultRoot, "config"),
		XDG_DATA_HOME: path.join(defaultRoot, "data"),
	};
	delete defaultEnv.OPENCODE_DB;
	const text = run(["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."], { env: defaultEnv });
	assert.equal(text.status, 0);
	assert.equal(text.stdout, "Hello from the fake provider.\n");

	const json = run(["run", "--format", "json", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."], { env: defaultEnv });
	assert.equal(json.status, 0);
	const parsedJson = JSON.parse(json.stdout);
	assert.equal(parsedJson.provider.id, "openai");
	assert.equal(parsedJson.request.prompt, "Say hello from the fixture.");
	assert.match(parsedJson.request.sessionID, /^ses_/);
	assert.equal(parsedJson.messages[1].parts.find((part) => part.type === "text").text, "Hello from the fake provider.");
	const defaultExport = run(["export", parsedJson.request.sessionID], { env: defaultEnv });
	assert.equal(defaultExport.status, 0);
	assert.equal(JSON.parse(defaultExport.stdout).messages.length, 2);
	const defaultResume = run(["run", "--format", "json", "--session", parsedJson.request.sessionID, "Continue", "default", "store."], { env: defaultEnv });
	assert.equal(defaultResume.status, 0);
	assert.equal(JSON.parse(defaultResume.stdout).request.sessionID, parsedJson.request.sessionID);
	const defaultContinue = run(["run", "--format", "json", "--continue", "Continue", "latest", "default", "store."], { env: defaultEnv });
	assert.equal(defaultContinue.status, 0);
	assert.match(JSON.parse(defaultContinue.stdout).request.sessionID, /^ses_/);

	const mockText = run(["run", "--mock-ai-sdk", "Say", "hello", "through", "the", "SDK."], { env: defaultEnv });
	assert.equal(mockText.status, 0);
	assert.equal(mockText.stdout, "Hello from the AI SDK session.\n");

	const mockJson = run(["run", "--mock-ai-sdk", "--format", "json", "Say", "hello", "through", "the", "SDK."], { env: defaultEnv });
	assert.equal(mockJson.status, 0);
	const mockParsed = JSON.parse(mockJson.stdout);
	assert.equal(mockParsed.provider.id, "openai");
	assert.equal(mockParsed.request.system[0], "You are an AI SDK provider runtime.");
	assert.equal(mockParsed.events[0].type, "start");
	assert.equal(mockParsed.events[1].text, "Hello ");

	const liveMissingModel = run(["run", "--live-ai-sdk", "Hello"], { env: defaultEnv });
	assert.equal(liveMissingModel.status, 1);
	assert.match(liveMissingModel.stderr, /require --model/);

	const liveMissingProvider = run(["run", "--live-ai-sdk", "--model", "missing-provider\/model", "Hello"], { env: defaultEnv });
	assert.equal(liveMissingProvider.status, 1);
	assert.match(liveMissingProvider.stderr, /Provider not available/);
} finally {
	rmSync(defaultRoot, { recursive: true, force: true });
}

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-cli-"));
try {
	const xdg = path.join(tempRoot, "xdg");
	const xdgData = path.join(tempRoot, "data");
	const globalConfig = path.join(xdg, "opencode");
	const authDir = path.join(xdgData, "opencode");
	const project = path.join(tempRoot, "project");
	mkdirSync(globalConfig, { recursive: true });
	mkdirSync(authDir, { recursive: true });
	mkdirSync(project, { recursive: true });
	const attachment = path.join(project, "attached.txt");
	const attachmentDir = path.join(project, "attached-dir");
	writeFileSync(attachment, "attached from generated CLI\n");
	mkdirSync(attachmentDir, { recursive: true });
	const configFor = (provider, baseURL) =>
		JSON.stringify({
			$schema: "https://opencode.ai/config.json",
			provider: {
				[provider]: {
					npm: "@ai-sdk/openai-compatible",
					name: provider,
					options: { baseURL, apiKey: "test-key" },
					models: { chat: { name: "Chat" } },
				},
			},
		});
	writeFileSync(path.join(globalConfig, "opencode.json"), configFor("global-live", "https://global.example.com"));
	writeFileSync(path.join(project, "opencode.json"), configFor("project-live", "https://project.example.com"));
	writeFileSync(
		path.join(authDir, "auth.json"),
		JSON.stringify({
			"cloudflare-ai-gateway": {
				type: "api",
				key: "auth-cf-token",
				metadata: { accountId: "auth-account", gatewayId: "auth-gateway" },
			},
		}),
	);
	const env = { ...process.env, XDG_CONFIG_HOME: xdg, XDG_DATA_HOME: xdgData };
	delete env.CLOUDFLARE_ACCOUNT_ID;
	delete env.CLOUDFLARE_GATEWAY_ID;
	delete env.CLOUDFLARE_API_TOKEN;
	delete env.CF_AIG_TOKEN;
	const withFile = run(["run", "--format", "json", "--dir", project, "--file", "attached.txt", "-f", "attached-dir", "Use", "generated", "attachments."], {
		env,
	});
	assert.equal(withFile.status, 0);
	const withFileJson = JSON.parse(withFile.stdout);
	assert.equal(withFileJson.messages[0].parts[0].type, "file");
	assert.equal(withFileJson.messages[0].parts[0].filename, "attached.txt");
	assert.equal(withFileJson.messages[0].parts[0].mime, "text/plain");
	assert.match(withFileJson.messages[0].parts[0].url, /^file:/);
	assert.equal(withFileJson.messages[0].parts[1].mime, "application/x-directory");
	assert.equal(withFileJson.messages[0].parts[2].text, "Use generated attachments.");
	const missingFile = run(["run", "--dir", project, "--file", "missing.txt", "Hello"], { env });
	assert.equal(missingFile.status, 1);
	assert.match(missingFile.stderr, /File not found: missing.txt/);
	const persistedEnv = { ...env, OPENCODE_DB: path.join(tempRoot, "headless-run.sqlite") };
	const persisted = run(["run", "--format", "json", "Persist", "from", "generated", "CLI."], { env: persistedEnv });
	assert.equal(persisted.status, 0);
	const persistedSessionID = JSON.parse(persisted.stdout).request.sessionID;
	assert.match(persistedSessionID, /^ses_/);
	const persistedExport = run(["export", persistedSessionID], { env: persistedEnv });
	assert.equal(persistedExport.status, 0);
	const persistedExportJson = JSON.parse(persistedExport.stdout);
	assert.equal(persistedExportJson.info.id, persistedSessionID);
	assert.equal(persistedExportJson.messages.length, 2);
	assert.equal(persistedExportJson.messages[0].parts[0].text, "Persist from generated CLI.");
	const persistedWithFile = run(["run", "--format", "json", "--dir", project, "--file", "attached.txt", "Persist", "generated", "file."], {
		env: persistedEnv,
	});
	assert.equal(persistedWithFile.status, 0);
	const persistedWithFileSessionID = JSON.parse(persistedWithFile.stdout).request.sessionID;
	const persistedWithFileExport = run(["export", persistedWithFileSessionID], { env: persistedEnv });
	assert.equal(persistedWithFileExport.status, 0);
	const persistedWithFileJson = JSON.parse(persistedWithFileExport.stdout);
	assert.equal(persistedWithFileJson.messages[0].parts[0].filename, "attached.txt");
	assert.equal(persistedWithFileJson.messages[0].parts[1].text, "Persist generated file.");
	const appended = run(["run", "--format", "json", "--session", persistedSessionID, "Append", "from", "generated", "CLI."], { env: persistedEnv });
	assert.equal(appended.status, 0);
	assert.equal(JSON.parse(appended.stdout).request.sessionID, persistedSessionID);
	const appendedExport = run(["export", persistedSessionID], { env: persistedEnv });
	assert.equal(appendedExport.status, 0);
	const appendedExportJson = JSON.parse(appendedExport.stdout);
	assert.equal(appendedExportJson.messages.length, 4);
	assert.equal(appendedExportJson.messages[2].parts[0].text, "Append from generated CLI.");
	const forked = run(["run", "--format", "json", "--session", persistedSessionID, "--fork", "Fork", "from", "generated", "CLI."], {
		env: persistedEnv,
	});
	assert.equal(forked.status, 0);
	const forkedSessionID = JSON.parse(forked.stdout).request.sessionID;
	assert.match(forkedSessionID, /^ses_/);
	assert.notEqual(forkedSessionID, persistedSessionID);
	const forkedExport = run(["export", forkedSessionID], { env: persistedEnv });
	assert.equal(forkedExport.status, 0);
	const forkedExportJson = JSON.parse(forkedExport.stdout);
	assert.equal(forkedExportJson.info.parentID, persistedSessionID);
	assert.equal(forkedExportJson.messages.length, 2);
	assert.equal(forkedExportJson.messages[0].parts[0].text, "Fork from generated CLI.");
	const mockEnv = { ...env, OPENCODE_DB: path.join(tempRoot, "mock-sdk-run.sqlite") };
	const mockPersisted = run(["run", "--mock-ai-sdk", "--format", "json", "Persist", "from", "generated", "mock", "SDK."], { env: mockEnv });
	assert.equal(mockPersisted.status, 0);
	const mockSessionID = JSON.parse(mockPersisted.stdout).request.sessionID;
	assert.match(mockSessionID, /^ses_/);
	const mockExport = run(["export", mockSessionID], { env: mockEnv });
	assert.equal(mockExport.status, 0);
	assert.equal(JSON.parse(mockExport.stdout).messages.length, 2);
	const mockAppended = run(["run", "--mock-ai-sdk", "--format", "json", "--session", mockSessionID, "Append", "from", "generated", "mock", "SDK."], {
		env: mockEnv,
	});
	assert.equal(mockAppended.status, 0);
	assert.equal(JSON.parse(mockAppended.stdout).request.sessionID, mockSessionID);
	const mockAppendedExport = run(["export", mockSessionID], { env: mockEnv });
	assert.equal(mockAppendedExport.status, 0);
	assert.equal(JSON.parse(mockAppendedExport.stdout).messages.length, 4);
	const globalLoaded = run(["run", "--live-ai-sdk", "--model", "global-live/missing", "Hello"], { env });
	assert.equal(globalLoaded.status, 1);
	assert.match(globalLoaded.stderr, /Model not found: global-live\/missing/);
	assert.match(globalLoaded.stderr, /Try: `opencode models` to list available models/);
	const projectLoaded = run(["run", "--live-ai-sdk", "--model", "project-live/missing", "--dir", project, "Hello"], { env });
	assert.equal(projectLoaded.status, 1);
	assert.match(projectLoaded.stderr, /Model not found: project-live\/missing/);
	const authLoaded = run(["run", "--live-ai-sdk", "--model", "cloudflare-ai-gateway/missing", "Hello"], { env });
	assert.equal(authLoaded.status, 1);
	assert.match(authLoaded.stderr, /Model not found: cloudflare-ai-gateway\/missing/);
	await withLiveOpenAICompatibleServer(async (localUrl, observed) => {
		writeFileSync(path.join(project, "opencode.json"), configFor("local-live", `${localUrl}/v1`));
		const liveEnv = { ...env, OPENCODE_DB: path.join(tempRoot, "live-sdk-run.sqlite") };
		const liveRun = await runAsync(["run", "--live-ai-sdk", "--model", "local-live/chat", "--format", "json", "--dir", project, "--file", "attached.txt", "Hello", "live."], {
			env: liveEnv,
		});
		assert.equal(liveRun.status, 0);
		const liveJson = JSON.parse(liveRun.stdout);
		assert.equal(liveJson.provider.id, "local-live");
		assert.equal(liveJson.request.prompt, "Hello live.");
		assert.match(liveJson.request.sessionID, /^ses_/);
		assert.equal(liveJson.messages[0].parts[0].filename, "attached.txt");
		assert.equal(liveJson.messages[1].parts.find((part) => part.type === "text").text, "Hello from local live.");
		assert.equal(observed.path, "/v1/chat/completions");
		assert.equal(observed.auth, "Bearer test-key");
		assert.equal(observed.body.stream, true);
		const liveExport = run(["export", liveJson.request.sessionID], { env: liveEnv });
		assert.equal(liveExport.status, 0);
		const liveExportJson = JSON.parse(liveExport.stdout);
		assert.equal(liveExportJson.messages.length, 2);
		assert.equal(liveExportJson.messages[0].parts[0].filename, "attached.txt");
		const liveAppend = await runAsync(["run", "--live-ai-sdk", "--model", "local-live/chat", "--format", "json", "--session", liveJson.request.sessionID, "Append", "live."], {
			env: liveEnv,
		});
		assert.equal(liveAppend.status, 0);
		assert.equal(JSON.parse(liveAppend.stdout).request.sessionID, liveJson.request.sessionID);
		const liveAppendExport = run(["export", liveJson.request.sessionID], { env: liveEnv });
		assert.equal(liveAppendExport.status, 0);
		const liveAppendExportJson = JSON.parse(liveAppendExport.stdout);
		assert.equal(liveAppendExportJson.messages.length, 4);
		assert.equal(liveAppendExportJson.messages[2].parts[0].text, "Append live.");
		const liveContinue = await runAsync(["run", "--live-ai-sdk", "--model", "local-live/chat", "--format", "json", "--continue", "Continue", "live."], {
			env: liveEnv,
		});
		assert.equal(liveContinue.status, 0);
		assert.equal(JSON.parse(liveContinue.stdout).request.sessionID, liveJson.request.sessionID);
		const liveContinueExport = run(["export", liveJson.request.sessionID], { env: liveEnv });
		assert.equal(liveContinueExport.status, 0);
		const liveContinueExportJson = JSON.parse(liveContinueExport.stdout);
		assert.equal(liveContinueExportJson.messages.length, 6);
		assert.equal(liveContinueExportJson.messages[4].parts[0].text, "Continue live.");
		const liveFork = await runAsync(["run", "--live-ai-sdk", "--model", "local-live/chat", "--format", "json", "--continue", "--fork", "Fork", "live."], {
			env: liveEnv,
		});
		assert.equal(liveFork.status, 0);
		const liveForkJson = JSON.parse(liveFork.stdout);
		assert.match(liveForkJson.request.sessionID, /^ses_/);
		assert.notEqual(liveForkJson.request.sessionID, liveJson.request.sessionID);
		const liveForkExport = run(["export", liveForkJson.request.sessionID], { env: liveEnv });
		assert.equal(liveForkExport.status, 0);
		const liveForkExportJson = JSON.parse(liveForkExport.stdout);
		assert.equal(liveForkExportJson.info.parentID, liveJson.request.sessionID);
		assert.equal(liveForkExportJson.messages.length, 2);
		assert.equal(liveForkExportJson.messages[0].parts[0].text, "Fork live.");
	});
	await withFailingOpenAICompatibleServer(async (localUrl, observed) => {
		writeFileSync(path.join(project, "opencode.json"), configFor("local-fail", `${localUrl}/v1`));
		const liveFailureEnv = { ...env, OPENCODE_DB: path.join(tempRoot, "live-sdk-failure.sqlite") };
		const liveFailure = await runAsync(["run", "--live-ai-sdk", "--model", "local-fail/chat", "--format", "json", "--dir", project, "Fail", "live."], {
			env: liveFailureEnv,
		});
		assert.equal(liveFailure.status, 0);
		const liveFailureJson = JSON.parse(liveFailure.stdout);
		assert.equal(liveFailureJson.provider.id, "local-fail");
		assert.equal(liveFailureJson.events.some((event) => event.type === "error" && event.message === "local live failure"), true);
		assert.equal(
			liveFailureJson.events.some((event) => event.type === "error" && event.message === "No output generated. Check the stream for errors."),
			true,
		);
		assert.equal(liveFailureJson.messages[1].info.finish, "error");
		assert.equal(observed.path, "/v1/chat/completions");
		assert.equal(observed.auth, "Bearer test-key");
		assert.equal(observed.body.stream, true);
		const liveFailureExport = run(["export", liveFailureJson.request.sessionID], { env: liveFailureEnv });
		assert.equal(liveFailureExport.status, 0);
		const liveFailureExportJson = JSON.parse(liveFailureExport.stdout);
		assert.equal(liveFailureExportJson.messages[1].info.finish, "error");
		assert.equal(liveFailureExportJson.messages[1].parts.find((part) => part.type === "text").text, "");
	});
	await withRemoteConfigServer(async (remoteUrl, observed) => {
		writeFileSync(
			path.join(authDir, "auth.json"),
			JSON.stringify({
				[remoteUrl]: {
					type: "wellknown",
					key: "LIVE_REMOTE_TOKEN",
					token: "remote-live-token",
				},
			}),
		);
		const remoteLoaded = await runAsync(["run", "--live-ai-sdk", "--model", "remote-live/missing", "Hello"], { env });
		assert.equal(remoteLoaded.status, 1);
		assert.match(remoteLoaded.stderr, /Model not found: remote-live\/missing/);
		writeAccountDatabase(path.join(authDir, "opencode.db"), `${remoteUrl}/`);
		const accountLoaded = await runAsync(["run", "--live-ai-sdk", "--model", "account-live/missing", "Hello"], { env });
		assert.equal(accountLoaded.status, 1);
		assert.match(accountLoaded.stderr, /Model not found: account-live\/missing/);
		assert.equal(observed.accountAuth, "Bearer account-live-token");
		assert.equal(observed.accountOrg, "org-live");
	});
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

const missing = run(["run"]);
assert.equal(missing.status, 1);
assert.match(missing.stderr, /You must provide a message/);

console.log("cli-smoke:ok");
