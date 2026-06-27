#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { readFile } from "node:fs/promises";
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
	const installedDbEnv = {
		...process.env,
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
	const resumedRun = expectOk(
		run(bin, ["run", "--format", "json", "--session", persistedSessionID, "Append", "from", "installed", "package."], { env: installedDbEnv }),
		"installed resumed run",
	);
	assert.equal(JSON.parse(resumedRun.stdout).request.sessionID, persistedSessionID, "installed resumed run session id");
	const resumedExport = expectOk(run(bin, ["export", persistedSessionID], { env: installedDbEnv }), "installed resumed export");
	const resumedMessages = JSON.parse(resumedExport.stdout).messages;
	assert.equal(resumedMessages.length, 4, "installed resumed export messages");
	assert.equal(resumedMessages[2].parts[0].text, "Append from installed package.", "installed resumed export prompt");
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
