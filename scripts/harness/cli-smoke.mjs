#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");
const packageJson = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));

function run(args) {
  return spawnSync("node", ["dist/index.js", ...args], {
    cwd: root,
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

const missing = run(["run"]);
assert.equal(missing.status, 1);
assert.match(missing.stderr, /You must provide a message/);

console.log("cli-smoke:ok");
