#!/usr/bin/env node

import { readFileSync } from "node:fs";

function fail(message) {
  console.error(`[version-sync] ERROR: ${message}`);
  process.exitCode = 1;
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

const packageJson = readJson("package.json");
const packageLock = readJson("package-lock.json");
const readme = readFileSync("README.md", "utf8");
const buildInfo = readFileSync("src/opencodehx/BuildInfo.hx", "utf8");
const version = packageJson.version;

if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
  fail(`package.json version is not semver: ${version}`);
}

if (!/^0\.[0-9]+\.[0-9]+-beta\.[0-9]+$/.test(version)) {
  fail(`OpenCodeHX public baselines must use 0.x beta semver before parity, got ${version}`);
}

if (packageLock.version !== version) {
  fail(`package-lock.json version ${packageLock.version} != package.json version ${version}`);
}

const rootPackage = packageLock.packages?.[""];
if (!rootPackage) {
  fail("package-lock.json missing root package entry");
} else if (rootPackage.version !== version) {
  fail(`package-lock root version ${rootPackage.version} != package.json version ${version}`);
}

if (!readme.includes(`current \`${version}\` beta baseline`)) {
  fail(`README release status does not mention current ${version} beta baseline`);
}

const buildInfoVersion = buildInfo.match(/public static final version:String = "([^"]+)";/);
if (!buildInfoVersion) {
  fail("BuildInfo.hx missing public static final version string");
} else if (buildInfoVersion[1] !== version) {
  fail(`BuildInfo.hx version ${buildInfoVersion[1]} != package.json version ${version}`);
}

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log(`[version-sync] OK: ${version}`);
