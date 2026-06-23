#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import assert from "node:assert/strict";
import { distIndexArgs, repoRoot } from "./paths.mjs";

const root = repoRoot;

function runJson(command, args, label) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status !== 0) {
    throw new Error(`${label} failed with exit ${result.status}\n${result.stderr}`);
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`${label} did not emit JSON: ${error.message}\n${result.stdout}`);
  }
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

const upstream = runJson("node", ["scripts/harness/upstream-fake-provider-oracle.mjs"], "upstream fake-provider oracle");
const hx = runJson("node", [...distIndexArgs, "--transcript-fixture"], "OpenCodeHX transcript fixture");
const hxRun = runJson(
  "node",
  [...distIndexArgs, "run", "--format", "json", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."],
  "OpenCodeHX run transcript",
);
const goldenPath = path.join(root, "fixtures/transcripts/one-turn.golden.json");
const golden = JSON.parse(readFileSync(goldenPath, "utf8"));

assert.equal(canonical(upstream), canonical(golden), "upstream oracle drifted from golden transcript");
assert.equal(canonical(hx), canonical(golden), "OpenCodeHX transcript drifted from golden transcript");
assert.equal(canonical(hxRun), canonical(golden), "OpenCodeHX run transcript drifted from golden transcript");
assert.equal(canonical(hx), canonical(upstream), "OpenCodeHX transcript differs from upstream oracle");

console.log("transcript-parity:ok");
