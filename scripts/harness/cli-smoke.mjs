#!/usr/bin/env node
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");
const packageJson = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));

function run(args, options = {}) {
	return spawnSync("node", ["dist/index.js", ...args], {
		cwd: options.cwd ?? root,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});
}

function canonical(value) {
  return `${JSON.stringify(value, Object.keys(flattenKeys(value)).sort(), 2)}\n`;
}

function flattenKeys(value, keys = {}) {
  if (Array.isArray(value)) {
    for (const item of value) flattenKeys(item, keys);
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      keys[key] = true;
      flattenKeys(child, keys);
    }
  }
  return keys;
}

const help = run(["--help"]);
assert.equal(help.status, 0);
assert.match(help.stdout, /opencodehx run \[message\.\.\]/);

const version = run(["--version"]);
assert.equal(version.status, 0);
assert.equal(version.stdout, `${packageJson.version}\n`);

const text = run(["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."]);
assert.equal(text.status, 0);
assert.equal(text.stdout, "Hello from the fake provider.\n");

const json = run(["run", "--format", "json", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."]);
assert.equal(json.status, 0);
const golden = JSON.parse(readFileSync(path.join(root, "fixtures/transcripts/one-turn.golden.json"), "utf8"));
assert.equal(canonical(JSON.parse(json.stdout)), canonical(golden));

const mockText = run(["run", "--mock-ai-sdk", "Say", "hello", "through", "the", "SDK."]);
assert.equal(mockText.status, 0);
assert.equal(mockText.stdout, "Hello from the AI SDK session.\n");

const mockJson = run(["run", "--mock-ai-sdk", "--format", "json", "Say", "hello", "through", "the", "SDK."]);
assert.equal(mockJson.status, 0);
const mockParsed = JSON.parse(mockJson.stdout);
assert.equal(mockParsed.provider.id, "openai");
assert.equal(mockParsed.request.system[0], "You are an AI SDK provider runtime.");
assert.equal(mockParsed.events[0].type, "start");
assert.equal(mockParsed.events[1].text, "Hello ");

const liveMissingModel = run(["run", "--live-ai-sdk", "Hello"]);
assert.equal(liveMissingModel.status, 1);
assert.match(liveMissingModel.stderr, /require --model/);

const liveMissingProvider = run(["run", "--live-ai-sdk", "--model", "missing-provider\/model", "Hello"]);
assert.equal(liveMissingProvider.status, 1);
assert.match(liveMissingProvider.stderr, /Provider not available/);

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
	const globalLoaded = run(["run", "--live-ai-sdk", "--model", "global-live/missing", "Hello"], { env });
	assert.equal(globalLoaded.status, 1);
	assert.match(globalLoaded.stderr, /Provider model not found: global-live\/missing/);
	const projectLoaded = run(["run", "--live-ai-sdk", "--model", "project-live/missing", "--dir", project, "Hello"], { env });
	assert.equal(projectLoaded.status, 1);
	assert.match(projectLoaded.stderr, /Provider model not found: project-live\/missing/);
	const authLoaded = run(["run", "--live-ai-sdk", "--model", "cloudflare-ai-gateway/missing", "Hello"], { env });
	assert.equal(authLoaded.status, 1);
	assert.match(authLoaded.stderr, /Provider model not found: cloudflare-ai-gateway\/missing/);
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

const missing = run(["run"]);
assert.equal(missing.status, 1);
assert.match(missing.stderr, /You must provide a message/);

console.log("cli-smoke:ok");
