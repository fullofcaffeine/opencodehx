#!/usr/bin/env node

import { existsSync, readFileSync, writeFileSync } from "node:fs";

function readUtf8(path) {
  return readFileSync(path, "utf8");
}

function writeUtf8(path, text) {
  writeFileSync(path, text);
}

function updateJsonFile(path, update) {
  const original = readUtf8(path);
  const json = JSON.parse(original);
  update(json);
  const next = `${JSON.stringify(json, null, 2)}\n`;
  if (next !== original) {
    writeUtf8(path, next);
  }
}

function ensureBetaSemver(version) {
  if (!/^0\.[0-9]+\.[0-9]+-beta\.[0-9]+$/.test(version)) {
    throw new Error(`OpenCodeHX public baselines must use 0.x beta semver before parity: ${version}`);
  }
}

function updateReadmeCurrentVersion(path, version) {
  const original = readUtf8(path);
  const pattern = /current `[^`]+` beta baseline/;
  if (!pattern.test(original)) {
    throw new Error(`No current beta baseline found to update in ${path}`);
  }
  const next = original.replace(pattern, `current \`${version}\` beta baseline`);
  if (next !== original) {
    writeUtf8(path, next);
  }
}

function updateBuildInfoVersion(path, version) {
  const original = readUtf8(path);
  const pattern = /public static final version:String = "[^"]+";/;
  if (!pattern.test(original)) {
    throw new Error(`No BuildInfo.version string found to update in ${path}`);
  }
  const next = original.replace(pattern, `public static final version:String = "${version}";`);
  if (next !== original) {
    writeUtf8(path, next);
  }
}

function main() {
  const version = process.argv[2];
  if (!version) {
    console.error("Usage: node scripts/release/sync-versions.mjs <version>");
    process.exit(2);
  }
  ensureBetaSemver(version);

  updateJsonFile("package.json", (json) => {
    json.version = version;
  });

  if (existsSync("package-lock.json")) {
    updateJsonFile("package-lock.json", (json) => {
      json.version = version;
      if (json.packages?.[""]) {
        json.packages[""].version = version;
      }
    });
  }

  updateReadmeCurrentVersion("README.md", version);
  updateBuildInfoVersion("src/opencodehx/BuildInfo.hx", version);
}

main();
