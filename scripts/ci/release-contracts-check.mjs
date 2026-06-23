#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";

function fail(message) {
  console.error(`[release-contracts] ERROR: ${message}`);
  process.exitCode = 1;
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function expectIncludes(haystack, needle, label) {
  if (!haystack.includes(needle)) {
    fail(`${label} missing ${needle}`);
  }
}

function expectExcludes(haystack, needle, label) {
  if (haystack.includes(needle)) {
    fail(`${label} must not include ${needle}`);
  }
}

const packageJson = readJson("package.json");
const haxerc = readJson(".haxerc");
const ciWorkflow = readFileSync(".github/workflows/ci.yml", "utf8");
const releaseWorkflow = readFileSync(".github/workflows/release.yml", "utf8");
const securityWorkflow = readFileSync(".github/workflows/security-gitleaks.yml", "utf8");
const dependabot = readFileSync(".github/dependabot.yml", "utf8");
const readme = readFileSync("README.md", "utf8");
const hooksInstall = readFileSync("scripts/hooks/install.sh", "utf8");
const preCommit = readFileSync("scripts/hooks/pre-commit", "utf8");
const beadsPreCommit = readFileSync(".beads-hooks/pre-commit", "utf8");
const gitleaks = readFileSync("scripts/security/run-gitleaks.sh", "utf8");
const genesHxml = readFileSync("haxe_libraries/genes-ts.hxml", "utf8");
const syncVersions = readFileSync("scripts/release/sync-versions.mjs", "utf8");
const versionSync = readFileSync("scripts/ci/version-sync-check.mjs", "utf8");
const license = existsSync("LICENSE") ? readFileSync("LICENSE", "utf8") : "";

if (packageJson.name !== "opencodehx") {
  fail(`package.json name must be opencodehx, got ${packageJson.name}`);
}
if (packageJson.license !== "MIT") {
  fail(`package.json license must stay MIT while the upstream OpenCode oracle is MIT, got ${packageJson.license}`);
}
expectIncludes(license, "MIT License", "LICENSE");
expectIncludes(readme, "0.x beta versioning", "README release status");
expectIncludes(readme, "sibling `../genes` checkout", "README dependency notes");
expectIncludes(genesHxml, "-cp ../genes/src", "genes-ts hxml");
expectIncludes(genesHxml, "-D genes-ts=1.11.0", "genes-ts hxml");
expectIncludes(versionSync, "BuildInfo.hx version", "version sync check");

for (const script of ["ci:version-sync", "ci:release-contracts", "ci:full", "public:precommit", "release", "release:dry-run"]) {
  if (!packageJson.scripts?.[script]) {
    fail(`package.json scripts missing ${script}`);
  }
}
if (packageJson.bin?.opencodehx !== "./bin/opencodehx.mjs") {
  fail("package.json bin must expose opencodehx through ./bin/opencodehx.mjs");
}
for (const entry of ["bin/", "dist/", "src-gen/"]) {
  if (!packageJson.files?.includes(entry)) {
    fail(`package.json files missing ${entry}`);
  }
}
if (!packageJson.scripts?.["package:smoke"]?.includes("package-smoke.mjs")) {
  fail("package.json scripts missing package:smoke harness");
}
expectIncludes(packageJson.scripts.test, "ci:version-sync", "npm test");
expectIncludes(packageJson.scripts.test, "ci:release-contracts", "npm test");
expectIncludes(packageJson.scripts["public:precommit"], "format:haxe:check", "public:precommit");
expectIncludes(packageJson.scripts["public:precommit"], "security:gitleaks", "public:precommit");
expectIncludes(packageJson.scripts["ci:full"], "npm run build", "ci:full");
expectIncludes(packageJson.scripts["ci:full"], "npm run package:smoke", "ci:full");
expectIncludes(packageJson.scripts["ci:full"], "npm run tui:scaffold", "ci:full");

for (const dependency of [
  "lix",
  "semantic-release",
  "@semantic-release/changelog",
  "@semantic-release/commit-analyzer",
  "@semantic-release/exec",
  "@semantic-release/git",
  "@semantic-release/github",
  "@semantic-release/release-notes-generator",
]) {
  if (!packageJson.devDependencies?.[dependency]) {
    fail(`package.json devDependencies missing ${dependency}`);
  }
}

const releaseConfig = packageJson.release;
if (!releaseConfig || !Array.isArray(releaseConfig.plugins)) {
  fail("package.json release.plugins must be configured");
} else {
  const betaMain = releaseConfig.branches?.some((branch) => branch?.name === "main" && branch?.prerelease === "beta");
  if (!betaMain) {
    fail("semantic-release branches must keep main on beta prereleases until parity");
  }
  for (const plugin of [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/exec",
    "@semantic-release/git",
    "@semantic-release/github",
  ]) {
    if (!releaseConfig.plugins.some((entry) => Array.isArray(entry) ? entry[0] === plugin : entry === plugin)) {
      fail(`semantic-release plugin missing: ${plugin}`);
    }
  }

  const execPlugin = releaseConfig.plugins.find((entry) => Array.isArray(entry) && entry[0] === "@semantic-release/exec");
  expectIncludes(execPlugin?.[1]?.prepareCmd ?? "", "sync-versions.mjs ${nextRelease.version}", "@semantic-release/exec prepareCmd");
  expectIncludes(syncVersions, "updateReadmeCurrentVersion", "sync-versions script");
  expectIncludes(syncVersions, "updateBuildInfoVersion", "sync-versions script");

  const gitPlugin = releaseConfig.plugins.find((entry) => Array.isArray(entry) && entry[0] === "@semantic-release/git");
  const assets = gitPlugin?.[1]?.assets ?? [];
  for (const requiredAsset of ["package.json", "package-lock.json", "README.md", "CHANGELOG.md"]) {
    if (!assets.includes(requiredAsset)) {
      fail(`release git assets missing required file: ${requiredAsset}`);
    }
  }
  const releaseMessage = gitPlugin?.[1]?.message ?? "";
  if (!releaseMessage.includes("\n\n")) {
    fail("@semantic-release/git message must separate subject and notes with a blank line");
  }
}

expectIncludes(ciWorkflow, `HAXE_VERSION: "${haxerc.version}"`, "CI workflow");
expectIncludes(ciWorkflow, "actions/checkout@v6", "CI workflow");
expectIncludes(ciWorkflow, "actions/setup-node@v6", "CI workflow");
expectIncludes(ciWorkflow, "repository: ${{ env.GENES_REPOSITORY }}", "CI workflow");
expectIncludes(ciWorkflow, "path: genes", "CI workflow");
expectIncludes(ciWorkflow, "npx lix download haxe", "CI workflow");
expectIncludes(ciWorkflow, "npm run ci:version-sync", "CI workflow");
expectIncludes(ciWorkflow, "npm run ci:release-contracts", "CI workflow");
expectIncludes(ciWorkflow, "npm run format:haxe:check", "CI workflow");
expectIncludes(ciWorkflow, "npm run build", "CI workflow");
expectIncludes(ciWorkflow, "npm run test:haxe:unit", "CI workflow");
expectIncludes(ciWorkflow, "npm run smoke", "CI workflow");
expectIncludes(ciWorkflow, "npm run package:smoke", "CI workflow");
expectIncludes(ciWorkflow, "npm run tui:scaffold", "CI workflow");
expectExcludes(ciWorkflow, "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24", "CI workflow");

expectIncludes(releaseWorkflow, "npx semantic-release", "Release workflow");
expectIncludes(releaseWorkflow, "fetch-depth: 0", "Release workflow");
expectIncludes(releaseWorkflow, "actions/checkout@v6", "Release workflow");
expectIncludes(releaseWorkflow, "actions/setup-node@v6", "Release workflow");
expectExcludes(releaseWorkflow, "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24", "Release workflow");

expectIncludes(securityWorkflow, "gitleaks/gitleaks-action@v3", "Gitleaks workflow");
expectIncludes(dependabot, "package-ecosystem: github-actions", "Dependabot");
expectIncludes(dependabot, "package-ecosystem: npm", "Dependabot");
expectIncludes(hooksInstall, "core.hooksPath .beads-hooks", "hook installer");
expectIncludes(hooksInstall, "bd hooks install --shared --chain", "hook installer");
expectIncludes(preCommit, "run-gitleaks.sh", "pre-commit hook");
expectIncludes(preCommit, "haxelib run formatter", "pre-commit hook");
expectIncludes(beadsPreCommit, "bd hooks run pre-commit", "shared Beads pre-commit hook");
expectIncludes(beadsPreCommit, "run-gitleaks.sh", "shared Beads pre-commit hook");
expectIncludes(beadsPreCommit, "haxelib run formatter", "shared Beads pre-commit hook");
expectIncludes(gitleaks, "--staged", "gitleaks wrapper");

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log("[release-contracts] OK");
