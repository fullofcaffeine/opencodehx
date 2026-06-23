#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { performance } from "node:perf_hooks";
import { pathToFileURL } from "node:url";
import { distIndexArgs, localBunExecutable, repoRoot, tuiScaffoldPaths } from "./paths.mjs";

const root = repoRoot;
const iterations = positiveInt(process.env.OPENCODEHX_BENCH_ITERATIONS, 7);
const warmups = positiveInt(process.env.OPENCODEHX_BENCH_WARMUPS, 1);
const outputPath = path.join(root, ".artifacts", "benchmarks", "performance-ux-benchmark.json");
const upstreamRoot = path.join(root, "..", "opencode", "packages", "opencode");
const upstreamBin = path.join(upstreamRoot, "bin", "opencode");
const upstreamPin = JSON.parse(readFileSync(path.join(root, "reference", "upstream-opencode.pin.json"), "utf8"));

const report = {
	schema: "opencodehx.performance-ux-benchmark.v1",
	recordedAt: new Date().toISOString(),
	iterations,
	warmups,
	environment: {
		platform: process.platform,
		arch: process.arch,
		node: process.version,
		bun: readCommand(localBunExecutable(), ["--version"]),
	},
	upstream: {
		commit: upstreamPin.checkout.commit,
		version: upstreamPin.package.version,
		nativeCli: probe("upstream native CLI", upstreamBin, ["--help"], { cwd: upstreamRoot }),
		bunSource: probe("upstream Bun source", localBunExecutable(), ["run", "--conditions=browser", "./src/index.ts", "--help"], {
			cwd: upstreamRoot,
		}),
	},
	benchmarks: [],
	notes: [
		"Durations are wall-clock milliseconds on this machine; compare trends, not absolute values.",
		"The upstream-shaped transcript oracle is a deterministic fixture builder, not the full upstream CLI runtime.",
	],
};

report.benchmarks.push(
	measureCommand("upstream_oracle_transcript_json", "node", ["scripts/harness/upstream-fake-provider-oracle.mjs"], {
		cwd: root,
		expect: (result) => {
			assert.equal(result.status, 0);
			assert.match(result.stdout, /Hello from the fake provider/);
		},
	}),
);

report.benchmarks.push(
	measureCommand("opencodehx_transcript_fixture_json", "node", [...distIndexArgs, "--transcript-fixture"], {
		cwd: root,
		expect: (result) => {
			assert.equal(result.status, 0);
			assert.match(result.stdout, /Hello from the fake provider/);
		},
	}),
);

report.benchmarks.push(
	measureCommand("opencodehx_cold_start_help", "node", [...distIndexArgs, "--help"], {
		cwd: root,
		expect: (result) => {
			assert.equal(result.status, 0);
			assert.match(result.stdout, /run\s+run opencode with a message/);
		},
	}),
);

report.benchmarks.push(
	measureCommand(
		"opencodehx_fake_provider_cli",
		"node",
		[...distIndexArgs, "run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "benchmark."],
		{
			cwd: root,
			expect: (result) => {
				assert.equal(result.status, 0);
				assert.equal(result.stdout, "Hello from the fake provider.\n");
			},
		},
	),
);

report.benchmarks.push(await measureToolOverhead());

report.benchmarks.push(
	measureCommand("opencodehx_tui_scaffold_entry", localBunExecutable(), ["--preload", tuiScaffoldPaths.sourcePreload, tuiScaffoldPaths.entryArg], {
		cwd: root,
		timeout: 60_000,
		expect: (result) => {
			assert.equal(result.status, 0);
			assert.match(result.stdout, /tui-scaffold:ok/);
		},
	}),
);

mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`);
printReport(report);

function positiveInt(value, fallback) {
	const parsed = Number.parseInt(value ?? "", 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function measureCommand(name, command, args, options = {}) {
	for (let i = 0; i < warmups; i++) {
		const result = run(command, args, options);
		options.expect?.(result);
	}
	const samples = [];
	for (let i = 0; i < iterations; i++) {
		const started = performance.now();
		const result = run(command, args, options);
		const duration = performance.now() - started;
		options.expect?.(result);
		samples.push(duration);
	}
	return {
		name,
		kind: "process",
		command: commandLabel(command, args),
		summary: summarize(samples),
	};
}

async function measureToolOverhead() {
	const { ToolRegistry } = await import(pathToFileURL(path.join(root, "dist", "opencodehx", "tool", "ToolRegistry.js")).href);
	const registry = new ToolRegistry();
	const samples = [];
	for (let i = 0; i < warmups; i++) runToolFixture(registry, i);
	for (let i = 0; i < iterations; i++) {
		const started = performance.now();
		runToolFixture(registry, i);
		samples.push(performance.now() - started);
	}
	return {
		name: "opencodehx_tool_overhead_direct",
		kind: "in-process",
		command: "ToolRegistry write/read/edit/apply_patch fixture",
		summary: summarize(samples),
	};
}

function runToolFixture(registry, index) {
	const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-bench-tool-"));
	try {
		const ctx = {
			directory: tempRoot,
			worktree: tempRoot,
			sessionID: "ses_bench",
			messageID: "msg_bench",
			agent: "benchmark",
		};
		registry.execute("write", { filePath: "src/bench.txt", content: `line one ${index}\nline two\n` }, ctx);
		registry.execute("read", { filePath: "src/bench.txt", limit: 20 }, ctx);
		registry.execute("edit", { filePath: "src/bench.txt", oldString: "line two", newString: "line three" }, ctx);
		registry.execute(
			"apply_patch",
			{
				patchText: [
					"*** Begin Patch",
					"*** Update File: src/bench.txt",
					"@@",
					"-line three",
					"+line four",
					"*** End Patch",
				].join("\n"),
			},
			ctx,
		);
	} finally {
		rmSync(tempRoot, { recursive: true, force: true });
	}
}

function run(command, args, options = {}) {
	return spawnSync(command, args, {
		cwd: options.cwd ?? root,
		env: options.env ?? process.env,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: options.timeout ?? 30_000,
	});
}

function probe(label, command, args, options = {}) {
	const result = run(command, args, { ...options, timeout: 20_000 });
	return {
		available: result.status === 0,
		status: result.status,
		error: result.error == null ? null : result.error.message,
		detail: oneLine(result.status === 0 ? result.stdout : result.stderr || result.stdout),
		label,
		command: commandLabel(command, args),
	};
}

function readCommand(command, args) {
	const result = run(command, args, { timeout: 10_000 });
	return result.status === 0 ? result.stdout.trim() : null;
}

function summarize(samples) {
	const sorted = [...samples].sort((a, b) => a - b);
	return {
		minMs: round(sorted[0]),
		medianMs: round(percentile(sorted, 0.5)),
		p95Ms: round(percentile(sorted, 0.95)),
		maxMs: round(sorted[sorted.length - 1]),
		samplesMs: sorted.map(round),
	};
}

function percentile(sorted, p) {
	if (sorted.length === 1) return sorted[0];
	const index = Math.ceil(p * sorted.length) - 1;
	return sorted[Math.max(0, Math.min(sorted.length - 1, index))];
}

function round(value) {
	return Math.round(value * 100) / 100;
}

function commandLabel(command, args) {
	const relative = path.isAbsolute(command) && command.startsWith(root) ? path.relative(root, command) : command;
	return [relative, ...args].join(" ");
}

function oneLine(value) {
	return String(value ?? "").replace(/\s+/g, " ").trim().slice(0, 240);
}

function printReport(value) {
	console.log("performance-benchmark:ok");
	console.log(`output=${path.relative(root, outputPath)}`);
	for (const item of value.benchmarks) {
		console.log(`${item.name}: median=${item.summary.medianMs}ms p95=${item.summary.p95Ms}ms`);
	}
	for (const [name, probeResult] of Object.entries(value.upstream)) {
		if (typeof probeResult !== "object" || probeResult == null || !("available" in probeResult)) continue;
		console.log(`upstream.${name}: ${probeResult.available ? "available" : "unavailable"} ${probeResult.detail}`);
	}
}
