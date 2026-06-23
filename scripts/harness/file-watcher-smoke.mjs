#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

const { EventBus } = await import(pathToFileURL(path.join(root, "dist/opencodehx/bus/EventBus.js")).href);
const { FileWatcherRuntime } = await import(
	pathToFileURL(path.join(root, "dist/opencodehx/file/FileWatcherRuntime.js")).href
);
const { VcsRuntime } = await import(pathToFileURL(path.join(root, "dist/opencodehx/project/VcsRuntime.js")).href);

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-file-watcher-"));
try {
	git(["init", "-b", "main"], tempRoot);
	git(["config", "user.email", "watcher@example.test"], tempRoot);
	git(["config", "user.name", "Watcher Smoke"], tempRoot);
	writeFileSync(path.join(tempRoot, "README.md"), "watcher\n");
	git(["add", "."], tempRoot);
	git(["commit", "-m", "initial"], tempRoot);
	git(["branch", "feature/watcher"], tempRoot);

	const fileBus = new EventBus();
	const branchBus = new EventBus();
	const watcher = new FileWatcherRuntime(tempRoot, fileBus);
	const vcs = new VcsRuntime(tempRoot, branchBus, fileBus);
	try {
		if (!watcher.init(false, true)) {
			console.log("file-watcher-smoke:skip native watcher unavailable");
			process.exit(0);
		}

		const branch = waitForBranch(branchBus, "feature/watcher");
		writeFileSync(path.join(tempRoot, ".git", "HEAD"), "ref: refs/heads/feature/watcher\n");
		await branch;
		assert.equal(vcs.branch(), "feature/watcher", "native watcher refreshed VCS branch");
		assert.equal(fileBus.snapshot().some((event) => event.file.endsWith(path.join(".git", "HEAD"))), true);
	} finally {
		watcher.dispose();
		vcs.dispose();
	}
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

console.log("file-watcher-smoke:ok");

function git(args, cwd) {
	const result = spawnSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
	assert.equal(result.status, 0, `git ${args.join(" ")} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
	return result.stdout;
}

function waitForBranch(bus, expected) {
	return new Promise((resolve, reject) => {
		const timeout = setTimeout(() => {
			unsubscribe();
			reject(new Error(`timed out waiting for branch ${expected}`));
		}, 10_000);
		const unsubscribe = bus.subscribe((event) => {
			if (event.branch !== expected) return;
			clearTimeout(timeout);
			unsubscribe();
			resolve(event);
		});
	});
}
