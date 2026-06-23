#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");

if (process.platform !== "win32") {
	console.log(`windows-shell-smoke:skip platform=${process.platform}`);
	process.exit(0);
}

const { NodeProcess } = await import(pathToFileURL(path.join(root, "dist/opencodehx/host/node/NodeProcess.js")).href);
const { PtyService } = await import(pathToFileURL(path.join(root, "dist/opencodehx/pty/PtyService.js")).href);

const tempRoot = mkdtempSync(path.join(os.tmpdir(), "opencodehx-windows-shell-"));
try {
	const shells = discoverShells();
	assert.ok(shells.cmd, "cmd.exe or COMSPEC is available on Windows");

	runThroughNodeProcess("cmd", shells.cmd, "echo opencodehx-cmd", /opencodehx-cmd/);
	if (shells.pwsh) runThroughNodeProcess("pwsh", shells.pwsh, "Write-Output opencodehx-pwsh", /opencodehx-pwsh/);
	if (shells.powershell) {
		runThroughNodeProcess("powershell", shells.powershell, "Write-Output opencodehx-powershell", /opencodehx-powershell/);
	}
	if (shells.gitBash) runThroughNodeProcess("git bash", shells.gitBash, "printf opencodehx-bash", /opencodehx-bash/);

	await ptyArgs(shells);
	await killTree(shells);
} finally {
	rmSync(tempRoot, { recursive: true, force: true });
}

console.log("windows-shell-smoke:ok");

function discoverShells() {
	const git = which("git.exe") ?? which("git");
	const gitBash = process.env.OPENCODE_GIT_BASH_PATH
		?? (git ? path.resolve(path.dirname(git), "../../bin/bash.exe") : null);
	return {
		cmd: process.env.COMSPEC || which("cmd.exe") || "cmd.exe",
		pwsh: which("pwsh.exe") ?? which("pwsh"),
		powershell: which("powershell.exe") ?? which("powershell"),
		gitBash: gitBash && existsSync(gitBash) ? gitBash : null,
	};
}

function which(name) {
	const result = spawnSync("where.exe", [name], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
	if (result.status !== 0) return null;
	const first = result.stdout.split(/\r?\n/).map((item) => item.trim()).find(Boolean);
	return first || null;
}

function runThroughNodeProcess(label, shell, command, expected) {
	const previousShell = process.env.SHELL;
	process.env.SHELL = shell;
	try {
		const result = NodeProcess.runShell({
			command,
			cwd: tempRoot,
			env: Object.fromEntries(Object.entries(process.env).filter(([, value]) => value != null)),
			timeout: 10_000,
			maxBuffer: 1024 * 1024,
		});
		assert.equal(result.status, 0, `${label} command failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
		assert.match(result.stdout, expected, `${label} stdout`);
	} finally {
		if (previousShell == null) delete process.env.SHELL;
		else process.env.SHELL = previousShell;
	}
}

async function ptyArgs(shells) {
	const service = new PtyService(tempRoot);
	try {
		const powershell = shells.pwsh ?? shells.powershell;
		if (powershell) {
			const info = service.create({ command: powershell, title: "powershell" });
			try {
				assert.deepEqual(info.args, [], "PowerShell PTY gets no login args");
			} finally {
				service.remove(info.id);
			}
		}
		if (shells.gitBash) {
			const info = service.create({ command: shells.gitBash, title: "git-bash" });
			try {
				assert.deepEqual(info.args, ["-l"], "Git Bash PTY gets login args");
			} finally {
				service.remove(info.id);
			}
		}
	} finally {
		service.dispose();
	}
}

async function killTree() {
	const ticks = path.join(tempRoot, "kill-tree-ticks.txt");
	writeFileSync(ticks, "");
	const childScript = 'const fs=require("node:fs");const file=process.argv[1];setInterval(()=>fs.appendFileSync(file,"tick"),25);';
	const parentScript =
		'const {spawn}=require("node:child_process");'
		+ 'const file=process.argv[1];'
		+ `const child=spawn(process.execPath,["-e",${JSON.stringify(childScript)},file],{stdio:"ignore"});`
		+ "child.unref();"
		+ "setInterval(()=>{},1000);";
	const proc = spawn(process.execPath, ["-e", parentScript, ticks], {
		detached: true,
		stdio: "ignore",
		windowsHide: true,
	});
	let exited = false;
	proc.once("exit", () => {
		exited = true;
	});
	await waitFor(() => readFileSync(ticks, "utf8").length > 0, "killTree descendant tick");
	await NodeProcess.killTree(proc, { exited: () => exited });
	await delay(250);
	const afterKill = readFileSync(ticks, "utf8");
	await delay(150);
	assert.equal(readFileSync(ticks, "utf8"), afterKill, "killTree stops descendant output");
}

function waitFor(check, label) {
	const started = Date.now();
	return new Promise((resolve, reject) => {
		const tick = () => {
			try {
				if (check()) return resolve();
				if (Date.now() - started > 5000) return reject(new Error(`timeout waiting for ${label}`));
				setTimeout(tick, 25);
			} catch (error) {
				reject(error);
			}
		};
		tick();
	});
}

function delay(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}
