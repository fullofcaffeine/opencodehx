#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { localBunExecutable, repoRoot, rootPath } from "./paths.mjs";

const root = repoRoot;
const bun = localBunExecutable();

if (!existsSync(bun)) {
	console.log(`abort-leak-smoke:skip bun=${bun}`);
	process.exit(0);
}

const abortModule = rootPath("dist", "opencodehx", "util", "Abort.js");
if (!existsSync(abortModule)) {
	throw new Error("abort-leak-smoke requires built dist output; run npm run build first");
}

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-abort-leak-"));
try {
	const worker = path.join(tempRoot, "abort-leak-worker.mjs");
	writeFileSync(worker, workerSource(pathToFileURL(abortModule).href));
	const result = spawnSync(bun, [worker], {
		cwd: root,
		env: process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: 60_000,
	});
	if (result.error) throw result.error;
	assert.equal(result.status, 0, `abort leak worker failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
	const out = JSON.parse(result.stdout.trim());
	assert.equal(out.webfetch.iterations, 50, "webfetch iteration count");
	assert.ok(out.webfetch.growth < 5, `webfetch heap growth ${out.webfetch.growth.toFixed(2)} MB should stay under 5 MB`);
	assert.equal(out.bind.iterations, 500, "bind comparison iteration count");
	assert.ok(out.bind.boundGrowth <= out.bind.closureGrowth, "bound abort handler should not retain more heap than closure pattern");
	console.log(
		[
			"abort-leak-smoke:ok",
			`webfetch-growth=${out.webfetch.growth.toFixed(2)}MB`,
			`closure-growth=${out.bind.closureGrowth.toFixed(2)}MB`,
			`bound-growth=${out.bind.boundGrowth.toFixed(2)}MB`,
		].join(" "),
	);
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

function workerSource(abortModuleUrl) {
	return `
import { Abort } from ${JSON.stringify(abortModuleUrl)};

const MB = 1024 * 1024;

function heap() {
	Bun.gc(true);
	return process.memoryUsage().heapUsed / MB;
}

function sleep(ms) {
	return Bun.sleep(ms);
}

async function runWebfetchIteration(url) {
	const controller = new AbortController();
	const abort = Abort.abortAfterAny(30000, [controller.signal]);
	try {
		const response = await fetch(url, { signal: abort.signal });
		await response.text();
	} finally {
		abort.clearTimeout();
		controller.abort();
	}
}

async function webfetchProbe() {
	const iterations = 50;
	const server = Bun.serve({
		port: 0,
		fetch() {
			return new Response("hello from local", {
				headers: { "content-type": "text/plain" },
			});
		},
	});
	try {
		const url = "http://127.0.0.1:" + server.port;
		await runWebfetchIteration(url);
		await sleep(100);
		const baseline = heap();
		for (let i = 0; i < iterations; i++) {
			await runWebfetchIteration(url);
		}
		await sleep(100);
		const after = heap();
		return { iterations, baseline, after, growth: after - baseline };
	} finally {
		await server.stop(true);
	}
}

async function bindComparisonProbe() {
	const iterations = 500;
	const timers = [];
	const controllers = [];
	const closureMap = new Map();
	await sleep(100);
	const baseline = heap();
	for (let i = 0; i < iterations; i++) {
		const content = i + ":" + "x".repeat(50 * 1024);
		const controller = new AbortController();
		controllers.push(controller);
		const handler = () => {
			if (content.length > 1000000000) controller.abort();
		};
		closureMap.set(content, handler);
		timers.push(setTimeout(handler, 30000));
	}
	await sleep(100);
	const closureAfter = heap();
	const closureGrowth = closureAfter - baseline;
	for (const timer of timers) clearTimeout(timer);
	for (const controller of controllers) controller.abort();
	closureMap.clear();

	const boundTimers = [];
	const boundControllers = [];
	const boundHandlers = [];
	await sleep(100);
	const boundBaseline = heap();
	for (let i = 0; i < iterations; i++) {
		const _content = i + ":" + "x".repeat(50 * 1024);
		const controller = new AbortController();
		boundControllers.push(controller);
		const handler = controller.abort.bind(controller);
		boundHandlers.push(handler);
		boundTimers.push(setTimeout(handler, 30000));
	}
	await sleep(100);
	const boundAfter = heap();
	const boundGrowth = boundAfter - boundBaseline;
	for (const timer of boundTimers) clearTimeout(timer);
	for (const controller of boundControllers) controller.abort();
	boundHandlers.length = 0;
	return { iterations, closureGrowth, boundGrowth };
}

if (typeof Bun.gc !== "function") {
	throw new Error("Bun.gc is required for abort leak smoke");
}

const webfetch = await webfetchProbe();
const bind = await bindComparisonProbe();
process.stdout.write(JSON.stringify({ webfetch, bind }));
`;
}
